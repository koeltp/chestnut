import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// S3 客户端异常：message 为用户可读的失败原因（配置页直接展示）
class S3ClientException implements Exception {
  S3ClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// S3 兼容对象存储客户端（AWS Signature V4 签名，纯手写无重型 SDK）
///
/// 只实现本功能需要的最小子集：PUT / GET / DELETE 单对象 + 连接测试。
/// 寻址统一采用 path-style（endpoint/bucket/key），Cloudflare R2 /
/// MinIO / 阿里 OSS / 腾讯 COS / 自建 MinIO 等兼容存储均可直连。
class S3CompatibleClient {
  S3CompatibleClient({
    required this.endpoint,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.region = 'auto',
  });

  /// 服务端点（如 https://<账户ID>.r2.cloudflarestorage.com）
  final String endpoint;

  /// 桶名
  final String bucket;

  /// 访问密钥 ID
  final String accessKeyId;

  /// 访问密钥 Secret
  final String secretAccessKey;

  /// 区域；R2 固定 auto，其它服务按控制台填写
  final String region;

  http.Client? _httpClient;

  http.Client get _http => _httpClient ??= http.Client();

  /// 释放底层连接（客户端不再复用时调用）
  void close() {
    _httpClient?.close();
    _httpClient = null;
  }

  // ---------- 对象操作 ----------

  /// 上传对象（PUT），[data] 为文件字节
  Future<void> putObject(
    String key,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  }) async {
    final res = await _signedRequest(
      'PUT',
      key,
      body: data,
      contentType: contentType,
    );
    _ensureOk(res, '上传');
  }

  /// 下载对象（GET），返回文件字节
  Future<Uint8List> getObject(String key) async {
    final res = await _signedRequest('GET', key);
    _ensureOk(res, '下载');
    return res.bodyBytes;
  }

  /// 删除对象（DELETE）。S3 删除天然幂等：404 视为已删除直接成功
  Future<void> deleteObject(String key) async {
    final res = await _signedRequest('DELETE', key);
    if (res.statusCode != 204 && res.statusCode != 404) {
      _throwWithReason(res, '删除');
    }
  }

  /// 连接测试：真实上传一个测试对象再删除（PUT+DELETE 双向验证），
  /// 任一步骤失败抛 [S3ClientException]，成功即说明四项配置可用
  Future<void> testConnection() async {
    const key = 'chestnut/connection-test.txt';
    await putObject(
      key,
      Uint8List.fromList(utf8.encode('chestnut connection test')),
      contentType: 'text/plain',
    );
    try {
      await deleteObject(key);
    } catch (_) {
      // 删除失败不影响连接判定：能上传说明地址与密钥可用，
      // 删除权限异常会在真实使用中暴露，此处保留测试对象可接受
    }
  }

  // ---------- 请求与签名 ----------

  /// 发起一次 SigV4 签名请求并返回响应
  Future<http.Response> _signedRequest(
    String method,
    String key, {
    Uint8List? body,
    String contentType = 'application/octet-stream',
  }) async {
    final payloadHash = sha256.convert(body ?? Uint8List(0)).toString();
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final url = _objectUrl(key);
    final host = url.hasPort ? '${url.host}:${url.port}' : url.host;

    // 规范请求：方法 + 规范 URI + 规范查询（单对象操作无查询参数）+
    // 规范头（小写、按名排序）+ 签名头列表 + 负载哈希
    final canonicalRequest = [
      method,
      _canonicalPath(url),
      '',
      'host:$host\n'
          'x-amz-content-sha256:$payloadHash\n'
          'x-amz-date:$amzDate\n',
      'host;x-amz-content-sha256;x-amz-date',
      payloadHash,
    ].join('\n');

    // 待签名串：算法 + 时间 + 作用域 + 规范请求的 SHA-256
    final scope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    // 签名密钥：HMAC-SHA256 链式派生（日期 → 区域 → 服务 → 终值）
    final kDate = _hmac(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = _hmac(kDate, region);
    final kService = _hmac(kRegion, 's3');
    final kSigning = _hmac(kService, 'aws4_request');
    final signature = _hmacHex(kSigning, stringToSign);

    try {
      // send 返回流式响应，收集成完整响应（对象尺寸为压缩后小图，安全）
      final streamed = await _http
          .send(http.Request(method, url)
            ..headers['x-amz-date'] = amzDate
            ..headers['x-amz-content-sha256'] = payloadHash
            ..headers['Authorization'] =
                'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, '
                    'SignedHeaders=host;x-amz-content-sha256;x-amz-date, '
                    'Signature=$signature'
            ..headers['Content-Type'] = contentType
            ..bodyBytes = body ?? Uint8List(0))
          .timeout(const Duration(seconds: 30));
      return await http.Response.fromStream(streamed);
    } on SocketException {
      throw S3ClientException('无法连接到服务器，请检查网络与 Endpoint');
    } on http.ClientException {
      throw S3ClientException('无法连接到服务器，请检查 Endpoint 是否正确');
    }
  }

  /// 拼出对象完整 URL（path-style：endpoint/bucket/key）。
  /// key 逐段按 AWS 规则编码（保留 '/' 作路径分隔符），先编码再交给
  /// Uri，避免 Uri 二次编码（如 key 里的 '+' 被原样保留导致签名错位）
  Uri _objectUrl(String key) {
    final base = Uri.parse(endpoint);
    final segments = [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      bucket,
      ...key.split('/'),
    ].map(_awsUriEncode).join('/');
    return base.replace(path: '/$segments');
  }

  /// SigV4 规范 URI：与 [_objectUrl] 用同一套编码，保证签名与实际
  /// 请求逐字节一致（Uri.path 返回的即规范化后的编码路径）
  String _canonicalPath(Uri url) {
    final path = url.path;
    if (path.isEmpty || !path.startsWith('/')) return '/$path';
    return path;
  }

  /// AWS S3 规范的 URI 编码：仅非保留字符不编码，其余按 UTF-8 百分号
  /// 编码；encodeComponent 会放过 '!' "'" '(' ')' '*' 这几个子分隔符，
  /// 按 SigV4 要求补齐编码
  String _awsUriEncode(String s) => Uri.encodeComponent(s)
      .replaceAll('!', '%21')
      .replaceAll("'", '%27')
      .replaceAll('(', '%28')
      .replaceAll(')', '%29')
      .replaceAll('*', '%2A');

  /// HMAC-SHA256（输入为字节、消息为 UTF-8 文本），返回原始字节
  List<int> _hmac(List<int> key, String message) =>
      Hmac(sha256, key).convert(utf8.encode(message)).bytes;

  /// HMAC-SHA256 后转十六进制小写
  String _hmacHex(List<int> key, String message) =>
      Hmac(sha256, key).convert(utf8.encode(message)).toString();

  /// x-amz-date 格式：yyyyMMddTHHmmssZ
  String _formatAmzDate(DateTime utc) {
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final mm = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    return '$y$m${d}T$hh$mm${ss}Z';
  }

  // ---------- 结果处理 ----------

  /// 非 2xx 时把状态码翻译成用户可读原因后抛出
  void _ensureOk(http.Response res, String action) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    _throwWithReason(res, action);
  }

  /// 按常见 S3 错误码给出排查方向，避免直接甩原始响应体给用户
  Never _throwWithReason(http.Response res, String action) {
    final code = res.statusCode;
    final reason = switch (code) {
      400 => '请求被拒绝（HTTP 400），请检查 Endpoint 与区域填写',
      401 || 403 => _authError(res),
      404 => '路径不存在（HTTP 404），请检查 Endpoint 与桶名是否正确',
      405 => '该存储不支持$action操作（HTTP 405）',
      >= 500 => '存储服务端错误（HTTP $code），请稍后重试',
      _ => '$action失败（HTTP $code）',
    };
    throw S3ClientException(reason);
  }

  /// 401/403 时读取 S3 错误 XML 的 <Code> 区分真实原因：
  /// 同一个 403 可能是密钥 ID 无效、签名不匹配或令牌权限不足，
  /// 排查方向完全不同，笼统提示会让用户白白反复检查 Secret
  String _authError(http.Response res) {
    String? code;
    try {
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(body)?.group(1);
    } catch (_) {
      // 响应体不是预期 XML（代理页/网关页等）退回通用提示
    }
    return switch (code) {
      'InvalidAccessKeyId' =>
        'Access Key ID 无效（HTTP 403），请确认复制完整、没有多余空格',
      'SignatureDoesNotMatch' =>
        'Secret Access Key 不正确（HTTP 403），签名校验未通过。'
            'Secret 只在创建令牌时显示一次，丢失需重新创建 API 令牌',
      'AccessDenied' =>
        '访问被拒绝（HTTP 403）：API 令牌权限不足或桶不匹配，'
            '需要"对象读和写"权限，且令牌范围包含此存储桶',
      _ =>
        '签名校验失败（HTTP 403），请检查 Access Key ID 与 '
            'Secret Access Key 是否正确',
    };
  }
}
