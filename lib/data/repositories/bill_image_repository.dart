import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database.dart';
import '../../models/enums.dart';
import '../../services/s3_compatible_client.dart';

/// 账单图片仓储：压缩、本地缓存、上传与级联清理
///
/// 双写架构的落地点：
/// · 记一笔面板选图 → [stageImage] 压缩后进暂存目录（未保存前不入库）；
/// · 账单保存 → [attachStagedImages] 把暂存文件转正到正式目录并写行；
/// · 上传 → [uploadImages] / [uploadPending]，失败改状态等补传；
/// · 读取 → 永远本地优先，缓存缺失时 [ensureLocalFile] 按 objectKey
///   从云端拉回；删除 → 记录 + 本地文件同步删，云端对象异步删
///   （失败留孤儿对象可接受，不打扰用户）。
class BillImageRepository {
  BillImageRepository(this._db);

  final AppDatabase _db;

  /// 压缩目标：长边 1800、JPEG q80，单张约 200~400KB
  static const _maxEdge = 1800;
  static const _quality = 80;

  /// 暂存目录（应用支持目录 receipts/.staging/，保存时转正移走）
  Future<Directory> _stagingDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'receipts', '.staging'))
        .create(recursive: true);
  }

  /// 正式目录（receipts/{billId}/，与云端按账单分目录的 key 对应）
  Future<Directory> _billDir(int billId) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'receipts', '$billId'))
        .create(recursive: true);
  }

  /// 云端对象键：chestnut/receipts/{billId}/{时间戳}_{随机}.jpg
  /// 前缀 chestnut/ 让桶内与本 App 相关的对象聚在一起，便于用户清理
  String _objectKeyFor(int billId, String fileName) =>
      'chestnut/receipts/$billId/$fileName';

  // ---------- 暂存（记一笔面板） ----------

  /// 压缩并暂存一张图片，返回暂存文件路径；账单保存时由
  /// [attachStagedImages] 转正入库
  Future<String> stageImage(Uint8List raw) async {
    Uint8List data = raw;
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: _maxEdge,
        minHeight: _maxEdge,
        quality: _quality,
        format: CompressFormat.jpeg,
        // 拍照原图可能带 EXIF 旋转标记，压缩时一并摆正
        autoCorrectionAngle: true,
      );
      if (compressed.isNotEmpty) data = compressed;
    } catch (_) {
      // 压缩失败（动图/异常编码等）退回原图，保证不丢图
    }
    final dir = await _stagingDir();
    final file = File(p.join(dir.path, '${_uniqueName()}.jpg'));
    await file.writeAsBytes(data, flush: true);
    return file.path;
  }

  /// 丢弃一张暂存图片（面板中删除 / 页面退出未保存时清理）
  Future<void> discardStagedImage(String path) async {
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
  /// 纯目录操作不依赖数据库，做成静态方法供 main() 在建库前调用
  static Future<void> cleanupStaging() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'receipts', '.staging'));
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

  /// 唯一文件名：毫秒时间戳 + 4 位随机，同毫秒添加多张也不冲突
  String _uniqueName() {
    final rand = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  // ---------- 入库（账单保存时） ----------

  /// 账单保存时登记暂存图片：移入正式目录、生成 objectKey、写行。
  /// 返回新记录列表（uploadState = pending），供调用方异步上传
  Future<List<BillImage>> attachStagedImages(
    int billId,
    List<String> stagedPaths,
  ) async {
    final result = <BillImage>[];
    var sort = await countImagesByBillId(billId);
    for (final path in stagedPaths) {
      final src = File(path);
      if (!await src.exists()) continue;
      final name = _uniqueName();
      final dest = p.join((await _billDir(billId)).path, '$name.jpg');
      // 同一分区内 rename 是原子操作，比 copy+delete 快且不留中间态
      try {
        await src.rename(dest);
      } on FileSystemException {
        // 跨分区 rename 失败（极罕见）退回复制
        await src.copy(dest);
        await src.delete();
      }
      final id = await _db.into(_db.billImages).insert(
            BillImagesCompanion.insert(
              billId: billId,
              objectKey: _objectKeyFor(billId, '$name.jpg'),
              localPath: dest,
              uploadState: BillImageUploadState.pending,
              sort: Value(sort++),
            ),
          );
      result.add(
        await (_db.select(_db.billImages)..where((i) => i.id.equals(id)))
            .getSingle(),
      );
    }
    return result;
  }

  // ---------- 查询 ----------

  /// 某账单的全部图片（按 sort 升序，同序按 id 稳定）
  Future<List<BillImage>> getImagesByBillId(int billId) {
    return (_db.select(_db.billImages)
          ..where((i) => i.billId.equals(billId))
          ..orderBy([
            (i) => OrderingTerm.asc(i.sort),
            (i) => OrderingTerm.asc(i.id),
          ]))
        .get();
  }

  /// 某账单图片流（详情弹窗用：上传状态变化时自动刷新）
  Stream<List<BillImage>> watchImagesByBillId(int billId) {
    return (_db.select(_db.billImages)
          ..where((i) => i.billId.equals(billId))
          ..orderBy([
            (i) => OrderingTerm.asc(i.sort),
            (i) => OrderingTerm.asc(i.id),
          ]))
        .watch();
  }

  /// 订阅哪些账单有图（列表相机角标用）：bill_images 表任何增删
  /// （含面板删图、账单级联删）都会重新发射。列表角标必须用本流而非
  /// 一次性查询——删图不更新 bills 表，快照会让角标残留
  Stream<Set<int>> watchBillIdsWithImages(List<int> billIds) {
    if (billIds.isEmpty) return Stream.value(const <int>{});
    return (_db.select(_db.billImages)
          ..where((i) => i.billId.isIn(billIds)))
        .watch()
        .map((rows) => rows.map((r) => r.billId).toSet());
  }

  /// 某账单图片数量（记一笔页图片(N) 计数用）
  Future<int> countImagesByBillId(int billId) async {
    final count = _db.billImages.id.count();
    final row = await (_db.selectOnly(_db.billImages)
          ..addColumns([count])
          ..where(_db.billImages.billId.equals(billId)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  // ---------- 上传 ----------

  /// 上传一批图片（记一笔保存后异步触发）。逐张隔离失败：
  /// 单张失败改 failed 状态，不影响其余继续传
  Future<void> uploadImages(
    List<BillImage> images,
    S3CompatibleClient client,
  ) async {
    for (final image in images) {
      await _uploadOne(image, client);
    }
  }

  /// 启动补传：扫描全部非 done 记录逐个上传，返回成功张数。
  /// 数据量为个人记账量级，全量取回后 Dart 端过滤足够
  Future<int> uploadPending(S3CompatibleClient client) async {
    final rows = await _db.select(_db.billImages).get();
    final pending = rows
        .where((r) => r.uploadState != BillImageUploadState.done)
        .toList();
    var success = 0;
    for (final image in pending) {
      if (await _uploadOne(image, client)) success++;
    }
    return success;
  }

  /// 手动重传单张（详情弹窗"未上传"角标点击触发），返回是否成功
  Future<bool> uploadOne(BillImage image, S3CompatibleClient client) =>
      _uploadOne(image, client);

  /// 上传单张：本地文件已丢的记录直接作废（图片本体都没了，记录
  /// 只剩空壳）；上传失败改 failed 等待补传，不在这里重试
  Future<bool> _uploadOne(BillImage image, S3CompatibleClient client) async {
    final file = File(image.localPath);
    if (!await file.exists()) {
      await (_db.delete(_db.billImages)..where((i) => i.id.equals(image.id)))
          .go();
      return false;
    }
    await _updateUploadState(image.id, BillImageUploadState.uploading);
    try {
      await client.putObject(
        image.objectKey,
        await file.readAsBytes(),
        contentType: 'image/jpeg',
      );
      await _updateUploadState(image.id, BillImageUploadState.done);
      return true;
    } catch (_) {
      await _updateUploadState(image.id, BillImageUploadState.failed);
      return false;
    }
  }

  Future<void> _updateUploadState(int id, BillImageUploadState state) {
    return (_db.update(_db.billImages)..where((i) => i.id.equals(id)))
        .write(BillImagesCompanion(uploadState: Value(state)));
  }

  // ---------- 读取兜底与删除 ----------

  /// 本地缓存缺失时从云端拉回并落盘（读取永远本地优先，此为兜底）；
  /// 失败返回 null，UI 显示占位态
  Future<File?> ensureLocalFile(
    BillImage image,
    S3CompatibleClient client,
  ) async {
    final file = File(image.localPath);
    if (await file.exists()) return file;
    try {
      final bytes = await client.getObject(image.objectKey);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 删除单张图片：记录与本地文件同步删；云存储已启用时异步删云端
  /// 对象（失败留孤儿可接受，静默不打扰）
  Future<void> deleteImage(BillImage image, {S3CompatibleClient? client}) async {
    await (_db.delete(_db.billImages)..where((i) => i.id.equals(image.id)))
        .go();
    final file = File(image.localPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // 本地清理失败忽略，不阻塞 UI 流程
      }
    }
    final c = client;
    if (c != null) {
      unawaited(
        c.deleteObject(image.objectKey).catchError((_) {
          // 云端删除失败留孤儿对象，可接受
          return;
        }),
      );
    }
  }

  /// 删除账单的级联图片清理（删除账单时调用）：删全部记录 + 本地
  /// 文件 + 云端对象
  Future<void> deleteImagesOfBill(
    int billId, {
    S3CompatibleClient? client,
  }) async {
    final images = await getImagesByBillId(billId);
    for (final image in images) {
      await deleteImage(image, client: client);
    }
  }
}
