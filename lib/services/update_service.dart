import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'system_downloader.dart';

/// 更新检查/下载失败的统一异常，message 可直接展示给用户
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 最新版本信息（对应 GitHub Release 上的 latest.json 清单）
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

  /// 发布时间的本地时区展示文本（"yyyy-MM-dd HH:mm"），
  /// 缺失或解析失败返回 null，由调用方自行兜底
  String? get publishedAtLocalText {
    final iso = publishedAt;
    if (iso == null) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    return DateFormat('yyyy-MM-dd HH:mm').format(t.toLocal());
  }
}

/// 进行中的系统下载记录：持久化到 prefs，App 重启后凭它重新挂上
/// 系统里仍在跑（或已完成）的下载任务
class _PendingDownload {
  const _PendingDownload({
    required this.downloadId,
    required this.info,
    required this.fileName,
  });

  static _PendingDownload? fromJson(Map<String, dynamic> json) {
    final id = json['downloadId'];
    final code = json['versionCode'];
    final name = json['versionName'];
    final url = json['apkUrl'];
    if (id is! int || code is! int || name is! String || url is! String) {
      return null;
    }
    return _PendingDownload(
      downloadId: id,
      info: UpdateInfo(
        versionCode: code,
        versionName: name,
        apkUrl: url,
        sha256: json['sha256'] as String?,
        fileSize: json['fileSize'] is int ? json['fileSize'] as int : null,
      ),
      fileName: json['fileName'] as String? ?? 'chestnut-$name.apk',
    );
  }

  Map<String, dynamic> toJson() => {
        'downloadId': downloadId,
        'versionCode': info.versionCode,
        'versionName': info.versionName,
        'apkUrl': info.apkUrl,
        'sha256': info.sha256,
        'fileSize': info.fileSize,
        'fileName': fileName,
      };

  final int downloadId;
  final UpdateInfo info;
  final String fileName;
}

/// 应用内自更新服务：检查清单 → 系统下载器下载 APK → 校验 → 拉起安装器。
///
/// 下载改走 Android 系统 DownloadManager（原生通道见 MainActivity.kt）：
/// 切后台/进程冻结/杀 App 都不中断，断点续传由系统自理；
/// 下载凭据（downloadId + 版本信息）持久化在 prefs，重启后可重新接管。
/// 清单与安装包经 Cloudflare Worker 反代（chestnut.taipi.top）分发；
/// 任何失败都只提示、绝不阻塞记账主流程。
class UpdateService {
  /// [client] 与 [downloader] 仅供测试注入 mock；生产路径不传按需自建
  UpdateService({http.Client? client, SystemDownloader? downloader})
      : _injectedClient = client,
        _downloader = downloader ?? SystemDownloader();

  final http.Client? _injectedClient;
  final SystemDownloader _downloader;

  /// 版本清单地址。GitHub Releases 国内直连不可靠，清单与 APK 均走
  /// Cloudflare Worker 反代（cloudflare/worker.js 部署在 chestnut.taipi.top），
  /// `latest/download` 直链恒指向最新 Release 的同名资产；
  /// 追加时间戳绕开 CDN 缓存，保证及时生效
  static const _manifestUrl =
      'https://chestnut.taipi.top/latest/download/latest.json';

  /// "以后再说"记忆键：记录用户已忽略的版本构建号，同版本自动提示只弹一次
  static const _kIgnoredUpdateCode = 'ignored_update_code';

  /// 进行中下载的持久化记录键（JSON 字符串）
  static const _kPendingDownload = 'pending_update_download';

  /// 拉取线上版本清单并解析（不与本地版本比较）。
  /// 更新日志弹层与更新记录页顶部用它展示最新一版的日志；
  /// [checkForUpdate] 在此之上做版本比较
  Future<UpdateInfo> fetchLatestManifest() async {
    final uri = Uri.parse(
      '$_manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final client = _injectedClient ?? http.Client();
    final http.Response resp;
    try {
      resp = await client.get(uri).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const UpdateException('网络连接失败，请稍后再试');
    } finally {
      // 注入的 client 由调用方（测试）管理，仅自建的用完即关
      if (_injectedClient == null) client.close();
    }
    if (resp.statusCode != 200) {
      throw UpdateException('版本服务暂不可用（HTTP ${resp.statusCode}）');
    }

    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateException('版本清单格式错误');
      }
      return UpdateInfo.fromJson(decoded);
    } on FormatException {
      throw const UpdateException('版本清单解析失败');
    }
  }

  /// 检查更新：有新版返回 [UpdateInfo]，当前已是最新返回 null；
  /// 网络或清单异常抛 [UpdateException]（自动检测与手动检查共用）
  Future<UpdateInfo?> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;

    final latest = await fetchLatestManifest();
    return latest.versionCode > currentCode ? latest : null;
  }

  /// 把更新包下载任务交给系统 DownloadManager。
  /// 先清空更新目录的历史残留，再入队并把下载凭据落 prefs；
  /// 通道异常统一转 [UpdateException]（message 可直接展示）
  Future<void> startDownload(UpdateInfo info) async {
    try {
      await _downloader.cleanup();
    } on PlatformException {
      // 目录清理失败不阻断下载
    }
    final fileName = 'chestnut-${info.versionName}.apk';
    // CDN 按完整 URL（含查询串）缓存对象：同名 APK 被新版本替换后，
    // 各边缘节点可能在缓存 TTL 内继续吐旧包，必须带时间戳强制回源
    final original = Uri.parse(info.apkUrl);
    final url = original.replace(
      queryParameters: <String, String>{
        ...original.queryParameters,
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    ).toString();
    final int id;
    try {
      id = await _downloader.start(
        url: url,
        fileName: fileName,
        title: '栗子记账 v${info.versionName}',
      );
    } on PlatformException {
      throw const UpdateException('无法开始下载，请稍后再试');
    }
    final prefs = await SharedPreferences.getInstance();
    final record = _PendingDownload(
      downloadId: id,
      info: info,
      fileName: fileName,
    );
    await prefs.setString(_kPendingDownload, jsonEncode(record.toJson()));
  }

  /// 查询进行中下载的快照；无下载记录或系统查询失败返回 null。
  /// 弹窗以固定间隔轮询它刷新进度，App 重启后也凭它恢复进度显示
  Future<SystemDownloadSnapshot?> pollDownloadSnapshot() async {
    final record = await _readRecord();
    if (record == null) return null;
    try {
      return await _downloader.query(record.downloadId);
    } on PlatformException {
      return null;
    }
  }

  /// 下载完成后的收尾：定位系统落盘的 APK → 完整性校验 → 返回文件。
  /// 校验失败删除残包并清记录（重试会整体重下，系统下载器对同名目标
  /// 不会续传校验失败的文件）；成功返回文件并清记录
  Future<File> consumeDownloadedApk() async {
    final record = await _readRecord();
    if (record == null) throw const UpdateException('没有可用的下载记录');
    final snapshot = await _downloader.query(record.downloadId);
    if (!snapshot.isSuccessful) {
      throw const UpdateException('下载尚未完成');
    }
    if (!snapshot.localUri.startsWith('file://')) {
      await _clearRecord();
      throw const UpdateException('无法定位下载的安装包');
    }
    final file = File(Uri.parse(snapshot.localUri).toFilePath());
    try {
      await verifyApk(file, record.info);
    } on UpdateException {
      await _clearRecord();
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // 删不掉就留给下次 cleanup
        }
      }
      rethrow;
    }
    await _clearRecord();
    return file;
  }

  /// 用户取消下载：让系统删除任务与半途文件，清掉本地记录。
  /// 无进行中下载时是空操作
  Future<void> cancelDownload() async {
    final record = await _readRecord();
    if (record == null) return;
    try {
      await _downloader.cancel(record.downloadId);
    } on PlatformException {
      // 系统里已无此任务即视为取消成功
    }
    await _clearRecord();
  }

  /// 复用已存在的下载记录：目标版本一致返回 true（弹窗直接恢复进度）；
  /// 不一致（更新清单已变或已装更新）则取消旧任务并清记录，返回 false
  Future<bool> reusePendingDownload(int versionCode) async {
    final record = await _readRecord();
    if (record == null) return false;
    if (record.info.versionCode == versionCode) return true;
    await cancelDownload();
    return false;
  }

  Future<_PendingDownload?> _readRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingDownload);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return _PendingDownload.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> _clearRecord() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingDownload);
  }

  /// 安装包完整性校验：清单给了大小/哈希就必校，任一不符抛 [UpdateException]。
  /// 防止网络中断产生残包或中间链路被替换；错误信息带实际值，便于远程排查。
  Future<void> verifyApk(File file, UpdateInfo info) async {
    final size = await file.length();
    if (info.fileSize != null && size != info.fileSize) {
      throw UpdateException('安装包大小不符（实得 $size / 应为 ${info.fileSize} 字节）');
    }
    final expected = info.sha256;
    if (expected != null) {
      final digest = await sha256.bind(file.openRead()).last;
      if (digest.toString() != expected) {
        throw UpdateException('安装包哈希校验失败（$digest）');
      }
    }
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
