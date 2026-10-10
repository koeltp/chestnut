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
import 'asset_repository.dart';

/// 借条仓储：借出/借入台账的增删改与借据照片管理
///
/// 照片与账单图片同架构的"暂存-转正-双写"（一借条可挂多图）：
/// · 表单选图 → [stagePhoto] 压缩后进 debt_photos/.staging/；
/// · 借条保存 → [attachStagedPhotos] 把暂存文件转正到
///   debt_photos/{noteId}/ 并落 debt_note_images 行（uploadState = pending）；
/// · 上传 → [uploadPhotos] / [uploadPending]，失败改 failed 等启动补传；
/// · 读取 → 永远本地优先，缓存缺失时 [ensureLocalFile] 按 objectKey
///   从云端拉回；删除 → 记录与本地文件同步清，云端对象异步删
///   （失败留孤儿对象可接受，与账单图片同口径）。
///
/// 余额联动：关联账户的借条保存时同步增减账户余额
/// （借出 = 从账户扣钱，借入 = 钱进账户），改/删做差值修正。
class DebtNoteRepository {
  DebtNoteRepository(this._db);

  final AppDatabase _db;

  /// 记账联动引擎（AssetRepository 无状态仅持 _db，就地构造零成本）
  late final _assetRepo = AssetRepository(_db);

  /// 压缩目标：与账单图片一致（长边 1800、JPEG q80）
  static const _maxEdge = 1800;
  static const _quality = 80;

  /// 暂存目录（debt_photos/.staging/，保存时转正移走）
  Future<Directory> _stagingDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'debt_photos', '.staging'))
        .create(recursive: true);
  }

  /// 正式目录（debt_photos/{noteId}/，与云端按借条分目录的 key 对应）
  Future<Directory> _noteDir(int noteId) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'debt_photos', '$noteId'))
        .create(recursive: true);
  }

  /// 云端对象键：chestnut/debt_photos/{noteId}/{时间戳}_{随机}.jpg
  /// 前缀 chestnut/ 让桶内与本 App 相关的对象聚在一起，便于用户清理
  String _objectKeyFor(int noteId, String fileName) =>
      'chestnut/debt_photos/$noteId/$fileName';

  /// 压缩并暂存一张借据照片，返回暂存文件路径；借条保存时转正
  Future<String> stagePhoto(Uint8List raw) async {
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

  /// 丢弃一张暂存照片（表单内删除 / 页面退出未保存时清理）
  Future<void> discardStagedPhoto(String path) async {
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {
        // 单个清理失败忽略，启动时有 [cleanupStaging] 兜底
      }
    }
  }

  /// 清空暂存目录：App 启动时调用，清理崩溃/退出遗留的未转正文件
  static Future<void> cleanupStaging() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'debt_photos', '.staging'));
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

  /// 唯一文件名：毫秒时间戳 + 4 位随机（与账单图片同规则）
  String _uniqueName() {
    final rand = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  /// 把一批暂存照片转正到借条正式目录并落 debt_note_images 行
  /// （uploadState = pending，由调用方触发上传）；
  /// 单张失败（暂存文件丢失）跳过不阻塞其余，与账单图片同口径
  Future<List<DebtNoteImage>> attachStagedPhotos(
    int noteId,
    List<String> stagedPaths,
  ) async {
    final result = <DebtNoteImage>[];
    var sort = await countPhotosByNoteId(noteId);
    for (final stagedPath in stagedPaths) {
      final src = File(stagedPath);
      if (!await src.exists()) continue;
      final name = '${_uniqueName()}.jpg';
      final dest = p.join((await _noteDir(noteId)).path, name);
      try {
        // 同一分区内 rename 是原子操作，比 copy+delete 快且不留中间态
        await src.rename(dest);
      } on FileSystemException {
        // 跨分区 rename 失败（极罕见）退回复制
        await src.copy(dest);
        await src.delete();
      }
      final id = await _db.into(_db.debtNoteImages).insert(
            DebtNoteImagesCompanion.insert(
              noteId: noteId,
              objectKey: _objectKeyFor(noteId, name),
              localPath: dest,
              uploadState: BillImageUploadState.pending,
              sort: Value(sort++),
            ),
          );
      result.add(
        await (_db.select(_db.debtNoteImages)..where((i) => i.id.equals(id)))
            .getSingle(),
      );
    }
    return result;
  }

  // ---------- 查询 ----------

  /// 监听全部借条（借款日期倒序，最近记录在前）
  Stream<List<DebtNote>> watchAll() {
    return (_db.select(_db.debtNotes)
          ..orderBy([
            (n) => OrderingTerm.desc(n.borrowedAt),
            (n) => OrderingTerm.desc(n.id),
          ]))
        .watch();
  }

  /// 监听关联某账户的借条（删除资产前检查引用用）
  Future<List<DebtNote>> getByRelatedAsset(int assetId) {
    return (_db.select(_db.debtNotes)
          ..where((n) => n.relatedAssetId.equals(assetId)))
        .get();
  }

  /// 监听关联某账户的借条流（账户明细页）：借出 = 钱从此账户出、
  /// 借入 = 钱入此账户，按借款日期倒序
  Stream<List<DebtNote>> watchOfAsset(int assetId) {
    return (_db.select(_db.debtNotes)
          ..where((n) => n.relatedAssetId.equals(assetId))
          ..orderBy([
            (n) => OrderingTerm.desc(n.borrowedAt),
            (n) => OrderingTerm.desc(n.id),
          ]))
        .watch();
  }

  /// 某借条的全部照片（按 sort 升序，同序按 id 稳定）
  Future<List<DebtNoteImage>> getPhotosByNoteId(int noteId) {
    return (_db.select(_db.debtNoteImages)
          ..where((i) => i.noteId.equals(noteId))
          ..orderBy([
            (i) => OrderingTerm.asc(i.sort),
            (i) => OrderingTerm.asc(i.id),
          ]))
        .get();
  }

  /// 某借条照片流（详情弹窗订阅：上传状态变化自动刷新缩略图）
  Stream<List<DebtNoteImage>> watchPhotosByNoteId(int noteId) {
    return (_db.select(_db.debtNoteImages)
          ..where((i) => i.noteId.equals(noteId))
          ..orderBy([
            (i) => OrderingTerm.asc(i.sort),
            (i) => OrderingTerm.asc(i.id),
          ]))
        .watch();
  }

  /// 监听哪些借条有照片（列表页附件角标用）：debt_note_images 表任何
  /// 增删（含编辑页删图、借条级联删）都会重新发射
  Stream<Set<int>> watchNoteIdsWithPhotos() {
    return (_db.select(_db.debtNoteImages))
        .watch()
        .map((rows) => rows.map((r) => r.noteId).toSet());
  }

  /// 某借条照片数量（attachStagedPhotos 追加 sort 用）
  Future<int> countPhotosByNoteId(int noteId) async {
    final count = _db.debtNoteImages.id.count();
    final row = await (_db.selectOnly(_db.debtNoteImages)
          ..addColumns([count])
          ..where(_db.debtNoteImages.noteId.equals(noteId)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  // ---------- 增删改 ----------

  /// 应用/撤销借条对关联账户余额的影响（必须在调用方事务内执行）：
  /// 借出 = 支付语义（资产减/信用卡欠款增），借入 = 收款语义；撤销取反
  Future<void> _applyDebtNoteEffect(
    DebtDirection direction, {
    required int? relatedAssetId,
    required int amountCents,
    required bool revert,
  }) async {
    if (relatedAssetId == null) return;
    final isOutflow = direction == DebtDirection.lendOut;
    await _assetRepo.applyAccountDelta(
      relatedAssetId,
      isOutflow: revert ? !isOutflow : isOutflow,
      amountCents: amountCents,
      // 应用新影响（借出扣钱）校验余额不足；撤销旧影响不校验
      enforceBalance: !revert,
    );
  }

  /// 新增借条。[stagedPhotoPaths] 非空时逐张转正落 debt_note_images 行
  /// （uploadState = pending，由调用方触发上传）。
  /// 返回落库后的借条实体，供调用方查询/上传照片
  Future<DebtNote> insertDebtNote({
    required DebtDirection direction,
    required String personName,
    required int amountCents,
    required DateTime borrowedAt,
    DateTime? repayDueAt,
    String? note,
    int? relatedAssetId,
    bool includeInTotal = true,
    List<String> stagedPhotoPaths = const [],
  }) async {
    return _db.transaction(() async {
      final id = await _db
          .into(_db.debtNotes)
          .insert(
            DebtNotesCompanion.insert(
              direction: direction,
              personName: personName,
              amountCents: amountCents,
              borrowedAt: borrowedAt,
              repayDueAt: Value(repayDueAt),
              note: Value(note),
              relatedAssetId: Value(relatedAssetId),
              includeInTotal: Value(includeInTotal),
            ),
          );
      await attachStagedPhotos(id, stagedPhotoPaths);
      // 关联账户时同步增减余额（借出扣钱/借入进账）
      await _applyDebtNoteEffect(
        direction,
        relatedAssetId: relatedAssetId,
        amountCents: amountCents,
        revert: false,
      );
      return (_db.select(_db.debtNotes)..where((n) => n.id.equals(id)))
          .getSingle();
    });
  }

  /// 更新借条。照片规则：[removedPhotoIds] 内的已有照片整条删除
  /// （记录/本地文件/云端对象），[stagedPhotoPaths] 为本次新加的暂存图。
  /// 两者互不影响，可同时传入；[client] 非空时同步清理被删照片的云端对象。
  /// 返回更新后借条实体
  Future<DebtNote> updateDebtNote(
    DebtNote existing, {
    required String personName,
    required int amountCents,
    required DateTime borrowedAt,
    DateTime? repayDueAt,
    String? note,
    int? relatedAssetId,
    required bool includeInTotal,
    List<int> removedPhotoIds = const [],
    List<String> stagedPhotoPaths = const [],
    S3CompatibleClient? client,
  }) async {
    await _db.transaction(() async {
      // 余额联动差值修正：先撤销旧影响（旧账户/旧金额），落库后应用新影响。
      // 方向不可编辑，新旧方向一致，直接用 existing.direction
      await _applyDebtNoteEffect(
        existing.direction,
        relatedAssetId: existing.relatedAssetId,
        amountCents: existing.amountCents,
        revert: true,
      );
      for (final photoId in removedPhotoIds) {
        final rows = await (_db.select(_db.debtNoteImages)
              ..where((i) => i.id.equals(photoId)))
            .get();
        for (final image in rows) {
          await deletePhoto(image, client: client);
        }
      }
      await attachStagedPhotos(existing.id, stagedPhotoPaths);
      await (_db.update(_db.debtNotes)..where((n) => n.id.equals(existing.id)))
          .write(
        DebtNotesCompanion(
          personName: Value(personName),
          amountCents: Value(amountCents),
          borrowedAt: Value(borrowedAt),
          repayDueAt: Value(repayDueAt),
          note: Value(note),
          relatedAssetId: Value(relatedAssetId),
          includeInTotal: Value(includeInTotal),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _applyDebtNoteEffect(
        existing.direction,
        relatedAssetId: relatedAssetId,
        amountCents: amountCents,
        revert: false,
      );
    });
    return (_db.select(_db.debtNotes)..where((n) => n.id.equals(existing.id)))
        .getSingle();
  }

  /// 删除借条：记录、照片与关联账户余额影响同步撤销；
  /// [client] 非空时异步清云端对象
  Future<void> deleteDebtNote(
    DebtNote note, {
    S3CompatibleClient? client,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.debtNotes)..where((n) => n.id.equals(note.id)))
          .go();
      await _applyDebtNoteEffect(
        note.direction,
        relatedAssetId: note.relatedAssetId,
        amountCents: note.amountCents,
        revert: true,
      );
    });
    final photos = await getPhotosByNoteId(note.id);
    for (final image in photos) {
      await deletePhoto(image, client: client);
    }
  }

  // ---------- 照片删除 ----------

  /// 删除单张照片：记录与本地文件同步删；[client] 非空时异步删云端
  /// 对象（失败留孤儿可接受，静默不打扰）
  Future<void> deletePhoto(
    DebtNoteImage image, {
    S3CompatibleClient? client,
  }) async {
    await (_db.delete(_db.debtNoteImages)..where((i) => i.id.equals(image.id)))
        .go();
    final file = File(image.localPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // 本地清理失败忽略，不阻塞 UI 流程
      }
    }
    if (client != null) {
      unawaited(
        client.deleteObject(image.objectKey).catchError((_) {
          // 云端删除失败留孤儿对象，可接受
          return;
        }),
      );
    }
  }

  // ---------- 上传与云端回源 ----------

  /// 手动/保存后触发上传一批照片（记借条保存后异步触发）。
  /// 逐张隔离失败：单张失败改 failed 状态，不影响其余继续传
  Future<void> uploadPhotos(
    List<DebtNoteImage> photos,
    S3CompatibleClient client,
  ) async {
    for (final image in photos) {
      await _uploadOne(image, client);
    }
  }

  /// 启动补传：扫描全部非 done 的照片记录逐个上传，返回成功张数。
  /// 数据量为个人记账量级，全量取回后 Dart 端过滤足够
  Future<int> uploadPending(S3CompatibleClient client) async {
    final rows = await _db.select(_db.debtNoteImages).get();
    final pending = rows
        .where((r) => r.uploadState != BillImageUploadState.done)
        .toList();
    var success = 0;
    for (final image in pending) {
      if (await _uploadOne(image, client)) success++;
    }
    return success;
  }

  /// 手动重传单张（编辑页"未上传"角标点击触发），返回是否成功
  Future<bool> uploadOne(DebtNoteImage image, S3CompatibleClient client) =>
      _uploadOne(image, client);

  /// 上传单张：本地文件已丢的记录直接作废（图片本体没了，记录只剩
  /// 空壳；借条本体不受影响）；上传失败改 failed 等待补传，不在这里重试
  Future<bool> _uploadOne(DebtNoteImage image, S3CompatibleClient client) async {
    final file = File(image.localPath);
    if (!await file.exists()) {
      await (_db.delete(_db.debtNoteImages)..where((i) => i.id.equals(image.id)))
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
    return (_db.update(_db.debtNoteImages)..where((i) => i.id.equals(id)))
        .write(DebtNoteImagesCompanion(uploadState: Value(state)));
  }

  /// 本地缓存缺失时从云端拉回并落盘（读取永远本地优先，此为兜底）；
  /// 失败返回 null，UI 显示占位态
  Future<File?> ensureLocalFile(
    DebtNoteImage image,
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
}
