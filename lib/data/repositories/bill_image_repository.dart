import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database.dart';
import '../../models/enums.dart';
import '../../services/photo_staging_service.dart';
import '../../services/s3_compatible_client.dart';

/// 账单图片仓储：入库、本地缓存、上传与级联清理
///
/// 双写架构的落地点（选图压缩等暂存逻辑统一走 [photos] 服务）：
/// · 记一笔面板选图 → [photos].stage 压缩后进暂存目录（未保存前不入库）；
/// · 账单保存 → [attachStagedImages] 把暂存文件转正到正式目录并写行；
/// · 上传 → [uploadImages] / [uploadPending]，失败改状态等补传；
/// · 读取 → 永远本地优先，缓存缺失时 [ensureLocalFile] 按 objectKey
///   从云端拉回；删除 → 记录 + 本地文件同步删，云端对象异步删
///   （失败留孤儿对象可接受，不打扰用户）。
class BillImageRepository {
  BillImageRepository(this._db);

  final AppDatabase _db;

  /// 账单图片暂存服务（receipts 目录）：选图/压缩/转正路径共用
  final PhotoStagingService photos =
      PhotoStagingService(dirName: 'receipts');

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
      final fileName = photos.uniqueFileName();
      final dest =
          p.join((await photos.entityDir(billId)).path, fileName);
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
              objectKey: photos.objectKeyFor(billId, fileName),
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
