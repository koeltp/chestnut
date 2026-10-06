import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新检查/下载失败的统一异常，message 可直接展示给用户
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 最新版本信息（对应博客上托管的 latest.json 清单）
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.sha256,
    this.fileSize,
    this.forceUpdate = false,
    this.releaseNotes = const [],
    this.publishedAt,
  });

  /// 从清单 JSON 解析；versionCode/versionName/apkUrl 为必填三件套，
  /// 缺失说明清单损坏（不能当成"无更新"静默吞掉，要让调用方感知）
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final code = json['versionCode'];
    final name = json['versionName'];
    final url = json['apkUrl'] as String?;
    if (code is! int || name is! String || url == null || url.isEmpty) {
      throw const UpdateException('版本清单格式错误');
    }
    final hash = json['sha256'];
    return UpdateInfo(
      versionCode: code,
      versionName: name,
      apkUrl: url,
      sha256: hash is String && hash.isNotEmpty ? hash.toLowerCase() : null,
      fileSize: json['fileSize'] is int ? json['fileSize'] as int : null,
      forceUpdate: json['forceUpdate'] == true,
      releaseNotes: (json['releaseNotes'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      publishedAt: json['publishedAt'] as String?,
    );
  }

  /// 构建号（pubspec version 的 +N），版本比较只认它
  final int versionCode;

  /// 版本名（如 1.0.1），用于展示
  final String versionName;

  /// APK 直链
  final String apkUrl;

  /// 安装包 SHA-256（小写十六进制），null = 清单未提供则不校验
  final String? sha256;

  /// 安装包字节数，null = 清单未提供则不校验
  final int? fileSize;

  /// 是否强制更新：true 时弹窗不可关闭、不允许忽略
  final bool forceUpdate;

  /// 更新内容条目
  final List<String> releaseNotes;

  /// 发布日期（仅展示用）
  final String? publishedAt;
}

/// 应用内自更新服务：检查清单 → 下载 APK（带进度）→ 校验 → 拉起安装器。
///
/// 清单与安装包均托管在个人博客（GitHub Pages），无自建服务器；
/// 任何失败都只提示、绝不阻塞记账主流程。
class UpdateService {
  /// 版本清单地址；追加时间戳绕开 GitHub Pages/CDN 缓存，保证及时生效
  static const _manifestUrl = 'https://www.taipi.top/chestnut/latest.json';

  /// "以后再说"记忆键：记录用户已忽略的版本构建号，同版本自动提示只弹一次
  static const _kIgnoredUpdateCode = 'ignored_update_code';

  /// 检查更新：有新版返回 [UpdateInfo]，当前已是最新返回 null；
  /// 网络或清单异常抛 [UpdateException]（自动检测与手动检查共用）
  Future<UpdateInfo?> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;

    final uri = Uri.parse(
      '$_manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final http.Response resp;
    try {
      resp = await http.get(uri).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const UpdateException('网络连接失败，请稍后再试');
    }
    if (resp.statusCode != 200) {
      throw UpdateException('版本服务暂不可用（HTTP ${resp.statusCode}）');
    }

    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateException('版本清单格式错误');
      }
      final latest = UpdateInfo.fromJson(decoded);
      return latest.versionCode > currentCode ? latest : null;
    } on FormatException {
      throw const UpdateException('版本清单解析失败');
    }
  }

  /// 下载 APK 到应用缓存目录，[onProgress] 回调 (已收字节, 总字节)；
  /// 服务端未返回 content-length 时 total 为 -1。
  /// 不做断点续传：包体约 60MB，失败整体重下更简单可靠；
  /// 缓存在 App 私有目录，卸载即清，不需要任何存储权限。
  Future<File> downloadApk(
    UpdateInfo info, {
    required void Function(int received, int total) onProgress,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final updateDir = Directory(p.join(cacheDir.path, 'updates'));
    if (!await updateDir.exists()) await updateDir.create(recursive: true);
    final apkFile = File(
      p.join(updateDir.path, 'chestnut-${info.versionName}.apk'),
    );
    // 同名残包（上次失败/下完未安装）直接删掉重下，避免追加脏数据
    if (await apkFile.exists()) await apkFile.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.apkUrl));
      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        throw UpdateException('下载失败（HTTP ${streamed.statusCode}）');
      }
      final total = streamed.contentLength ?? -1;
      var received = 0;
      final sink = apkFile.openWrite();
      try {
        await for (final chunk in streamed.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } catch (e) {
      if (await apkFile.exists()) await apkFile.delete();
      if (e is UpdateException) rethrow;
      throw const UpdateException('下载中断，请检查网络后重试');
    } finally {
      client.close();
    }
    return apkFile;
  }

  /// 安装包完整性校验：清单给了大小/哈希就必校，任一不符拒绝安装。
  /// 防止网络中断产生残包或中间链路被替换。
  Future<bool> verifyApk(File file, UpdateInfo info) async {
    final size = await file.length();
    if (info.fileSize != null && size != info.fileSize) return false;
    final expected = info.sha256;
    if (expected != null) {
      final digest = await sha256.bind(file.openRead()).last;
      if (digest.toString() != expected) return false;
    }
    return true;
  }

  /// 拉起系统包安装器；未授权"未知来源"时 open_filex 会引导用户去设置页
  Future<bool> installApk(File file) async {
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }

  /// 记录用户主动忽略的版本（"以后再说"）
  Future<void> markIgnored(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kIgnoredUpdateCode, versionCode);
  }

  /// 该版本是否已被忽略：自动检测同版本只打扰一次；
  /// 我的页手动"检查更新"不读这个标记
  Future<bool> isIgnored(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kIgnoredUpdateCode) == versionCode;
  }
}
