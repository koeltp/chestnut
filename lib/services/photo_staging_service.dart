import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 照片暂存服务：账单图片与借据照片共用同一套「压缩-暂存-转正」
///
/// [dirName] 同时决定本地子目录与云端路径段：
/// · 账单图片：`receipts`（本地 {support}/receipts/，云端 chestnut/receipts/）
/// · 借据照片：`debt_photos`（本地 {support}/debt_photos/，云端 chestnut/debt_photos/）
///
/// 服务无状态（仅持有目录名），各处可直接构造，无需依赖注入。
class PhotoStagingService {
  PhotoStagingService({required this.dirName});

  /// 本地 / 云端共用的目录段名
  final String dirName;

  /// 压缩目标：长边 1800、JPEG q80，单张约 200~400KB
  static const int maxEdge = 1800;
  static const int quality = 80;

  /// 暂存目录（{dirName}/.staging/，保存时转正移走）
  Future<Directory> stagingDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, dirName, '.staging'))
        .create(recursive: true);
  }

  /// 正式目录（{dirName}/{entityId}/，与云端按实体分目录的 key 对应）
  Future<Directory> entityDir(int entityId) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, dirName, '$entityId'))
        .create(recursive: true);
  }

  /// 云端对象键：chestnut/{dirName}/{entityId}/{时间戳}_{随机}.jpg。
  /// 前缀 chestnut/ 让桶内与本 App 相关的对象聚在一起，便于用户清理
  String objectKeyFor(int entityId, String fileName) =>
      'chestnut/$dirName/$entityId/$fileName';

  /// 唯一文件名（含扩展名）：毫秒时间戳 + 4 位随机，同毫秒添加多张也不冲突
  String uniqueFileName() {
    final rand = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${DateTime.now().millisecondsSinceEpoch}_$rand.jpg';
  }

  /// 压缩并暂存一张照片，返回暂存文件路径；实体保存时由各仓储转正入库
  Future<String> stage(Uint8List raw) async {
    Uint8List data = raw;
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: maxEdge,
        minHeight: maxEdge,
        quality: quality,
        format: CompressFormat.jpeg,
        // 拍照原图可能带 EXIF 旋转标记，压缩时一并摆正
        autoCorrectionAngle: true,
      );
      if (compressed.isNotEmpty) data = compressed;
    } catch (_) {
      // 压缩失败（动图/异常编码等）退回原图，保证不丢图
    }
    final dir = await stagingDir();
    final file = File(p.join(dir.path, uniqueFileName()));
    await file.writeAsBytes(data, flush: true);
    return file.path;
  }

  /// 丢弃一张暂存照片（选图后删除 / 页面退出未保存时清理）
  Future<void> discard(String path) async {
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {
        // 单个清理失败忽略，启动时有 [cleanupStaging] 兜底
      }
    }
  }

  /// 清空暂存目录：App 启动时调用，清理崩溃/退出遗留的未转正文件。
  /// 纯目录操作不依赖数据库，可在建库前调用
  Future<void> cleanupStaging() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, dirName, '.staging'));
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        try {
          await entity.delete();
        } catch (_) {
          // 单个清理失败忽略
        }
      }
    } catch (_) {
      // 目录不存在等情况忽略
    }
  }
}
