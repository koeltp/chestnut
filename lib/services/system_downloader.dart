import 'package:flutter/services.dart';

/// 系统 DownloadManager 的状态码（对齐 android.app.DownloadManager 常量）
sealed class SystemDownloadStatus {
  static const pending = 1;
  static const running = 2;
  static const paused = 4;
  static const successful = 8;
  static const failed = 16;
}

/// 单条系统下载的快照
class SystemDownloadSnapshot {
  const SystemDownloadSnapshot({
    required this.status,
    required this.received,
    required this.total,
    this.localUri = '',
    this.reason = 0,
  });

  /// 0 = 系统里已无此记录（被清理或从未入队）
  final int status;
  final int received;

  /// 总字节；系统未知大小时为 -1
  final int total;

  /// 下载完成后的本地 file:// URI（仅成功时有意义）
  final String localUri;

  /// 失败/暂停原因码（仅排查用）
  final int reason;

  bool get isSuccessful => status == SystemDownloadStatus.successful;
  bool get isFailed => status == SystemDownloadStatus.failed;
  bool get isActive =>
      status == SystemDownloadStatus.pending ||
      status == SystemDownloadStatus.running ||
      status == SystemDownloadStatus.paused;
}

/// Android 系统 DownloadManager 的 Dart 封装。
///
/// 下载由系统进程执行：App 退后台、被冻结甚至被杀都不中断，
/// 断网重连与断点续传由系统自理——这是应用内自更新改走它的根本原因。
/// [channel] 仅供测试注入；生产用默认通道（原生侧实现在 MainActivity.kt）。
class SystemDownloader {
  SystemDownloader({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('top.taipi.chestnut/system_downloader');

  final MethodChannel _channel;

  /// 入队下载，返回 downloadId；失败抛 [PlatformException]
  Future<int> start({
    required String url,
    required String fileName,
    required String title,
  }) async {
    final id = await _channel.invokeMethod<int>('start', {
      'url': url,
      'fileName': fileName,
      'title': title,
    });
    if (id == null) {
      throw PlatformException(code: 'DOWNLOAD_ERROR', message: '入队失败');
    }
    return id;
  }

  /// 查询下载快照；通道异常原样抛 [PlatformException]，
  /// 记录不存在时返回 status=0 的快照而非 null（与原生约定一致）
  Future<SystemDownloadSnapshot> query(int id) async {
    final raw =
        await _channel.invokeMethod<Map<Object?, Object?>>('query', {'id': id});
    if (raw == null) {
      return const SystemDownloadSnapshot(status: 0, received: 0, total: -1);
    }
    return SystemDownloadSnapshot(
      status: (raw['status'] as num?)?.toInt() ?? 0,
      received: (raw['received'] as num?)?.toInt() ?? 0,
      total: (raw['total'] as num?)?.toInt() ?? -1,
      localUri: raw['localUri'] as String? ?? '',
      reason: (raw['reason'] as num?)?.toInt() ?? 0,
    );
  }

  /// 取消并删除下载（含半途/已落盘文件）
  Future<void> cancel(int id) => _channel.invokeMethod<void>('cancel', {'id': id});

  /// 清空更新目录里的历次残留 APK
  Future<void> cleanup() => _channel.invokeMethod<void>('cleanup');
}
