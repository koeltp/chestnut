import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database.dart';
import '../../models/enums.dart';
import '../../services/photo_staging_service.dart';
import '../../services/s3_compatible_client.dart';
import 'asset_repository.dart';

/// 借条仓储：借出/借入台账的增删改与借据照片管理
///
/// 照片与账单图片同架构的"暂存-转正-双写"（一借条可挂多图），
/// 选图/压缩等暂存逻辑统一走 [photos] 服务：
/// · 表单选图 → [photos].stage 压缩后进 debt_photos/.staging/；
/// · 借条保存 → [attachStagedPhotos] 把暂存文件转正到
///   debt_photos/{借款年月}/ 并落 debt_note_images 行（uploadState = pending）；
/// · 上传 → [uploadPhotos] / [uploadPending]，失败改 failed 等启动补传；
/// · 读取 → 永远本地优先，缓存缺失时 [ensureLocalFile] 按 objectKey
///   从云端拉回；删除 → 记录与本地文件同步清，云端对象异步删
///   （失败留孤儿对象可接受，与账单图片同口径）。
///
/// 还款金额超过借条剩余欠款（本金口径），拒绝落库
class RepaymentExceedsException implements Exception {
  @override
  String toString() => '还款金额超过借条剩余欠款';
}

/// 余额联动：关联账户的借条保存时同步增减账户余额
/// （借出 = 从账户扣钱，借入 = 钱进账户），改/删做差值修正。
class DebtNoteRepository {
  DebtNoteRepository(this._db);

  final AppDatabase _db;

  /// 记账联动引擎（AssetRepository 无状态仅持 _db，就地构造零成本）
  late final _assetRepo = AssetRepository(_db);

  /// 还款金额超过借条剩余欠款（本金口径），拒绝落库
  static const repaymentExceedsMessage = '还款金额超过借条剩余欠款';

  /// 借据照片暂存服务（debt_photos 目录）：选图/压缩/转正路径共用
  final PhotoStagingService photos = PhotoStagingService(
    dirName: 'debt_photos',
  );

  /// 把一批暂存照片按借款日期转正到月份目录并落 debt_note_images 行
  /// （uploadState = pending，由调用方触发上传）；
  /// 单张失败（暂存文件丢失）跳过不阻塞其余，与账单图片同口径
  Future<List<DebtNoteImage>> attachStagedPhotos(
    int noteId,
    DateTime occurredOn,
    List<String> stagedPaths,
  ) async {
    final result = <DebtNoteImage>[];
    var sort = await countPhotosByNoteId(noteId);
    for (final stagedPath in stagedPaths) {
      final src = File(stagedPath);
      if (!await src.exists()) continue;
      final name = photos.finalFileName(occurredOn, noteId);
      final dest = p.join((await photos.monthDir(occurredOn)).path, name);
      try {
        // 同一分区内 rename 是原子操作，比 copy+delete 快且不留中间态
        await src.rename(dest);
      } on FileSystemException {
        // 跨分区 rename 失败（极罕见）退回复制
        await src.copy(dest);
        await src.delete();
      }
      final id = await _db
          .into(_db.debtNoteImages)
          .insert(
            DebtNoteImagesCompanion.insert(
              noteId: noteId,
              objectKey: photos.objectKeyFor(occurredOn, name),
              localPath: dest,
              uploadState: BillImageUploadState.pending,
              sort: Value(sort++),
            ),
          );
      result.add(
        await (_db.select(
          _db.debtNoteImages,
        )..where((i) => i.id.equals(id))).getSingle(),
      );
    }
    return result;
  }

  // ---------- 查询 ----------

  /// 监听全部借条（借款日期倒序，最近记录在前）
  Stream<List<DebtNote>> watchAll() {
    return (_db.select(_db.debtNotes)..orderBy([
          (n) => OrderingTerm.desc(n.borrowedAt),
          (n) => OrderingTerm.desc(n.id),
        ]))
        .watch();
  }

  /// 监听指定月份的借条（借款日期落在该月内）：首页"按月查看"专用，
  /// 避免全表 watch 后 Dart 层内存过滤导致范围外借条变动也触发重发射
  Stream<List<DebtNote>> watchDebtsInMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return (_db.select(_db.debtNotes)
          ..where(
            (n) =>
                n.borrowedAt.isBiggerOrEqualValue(start) &
                n.borrowedAt.isSmallerThanValue(end),
          )
          ..orderBy([
            (n) => OrderingTerm.desc(n.borrowedAt),
            (n) => OrderingTerm.desc(n.id),
          ]))
        .watch();
  }

  /// 监听指定年份的借条
  Stream<List<DebtNote>> watchDebtsInYear(int year) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    return (_db.select(_db.debtNotes)
          ..where(
            (n) =>
                n.borrowedAt.isBiggerOrEqualValue(start) &
                n.borrowedAt.isSmallerThanValue(end),
          )
          ..orderBy([
            (n) => OrderingTerm.desc(n.borrowedAt),
            (n) => OrderingTerm.desc(n.id),
          ]))
        .watch();
  }

  /// 监听关联某账户的借条（删除资产前检查引用用）
  Future<List<DebtNote>> getByRelatedAsset(int assetId) {
    return (_db.select(
      _db.debtNotes,
    )..where((n) => n.relatedAssetId.equals(assetId))).get();
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
    final row =
        await (_db.selectOnly(_db.debtNoteImages)
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
      await attachStagedPhotos(id, borrowedAt, stagedPhotoPaths);
      // 关联账户时同步增减余额（借出扣钱/借入进账）
      await _applyDebtNoteEffect(
        direction,
        relatedAssetId: relatedAssetId,
        amountCents: amountCents,
        revert: false,
      );
      return (_db.select(
        _db.debtNotes,
      )..where((n) => n.id.equals(id))).getSingle();
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
      // 已还本金不能超过新借款金额：借条余额 = 金额 − 已还本金，
      // 改小会让余额为负、剩余口径失真，直接拒绝
      final repaid = await repaidPrincipalTotal(existing.id);
      if (amountCents < repaid) {
        throw Exception('借款金额不能低于已还本金，请先删除部分还款记录');
      }
      // 余额联动差值修正：先撤销旧影响（旧账户/旧金额），落库后应用新影响。
      // 方向不可编辑，新旧方向一致，直接用 existing.direction
      await _applyDebtNoteEffect(
        existing.direction,
        relatedAssetId: existing.relatedAssetId,
        amountCents: existing.amountCents,
        revert: true,
      );
      for (final photoId in removedPhotoIds) {
        final rows = await (_db.select(
          _db.debtNoteImages,
        )..where((i) => i.id.equals(photoId))).get();
        for (final image in rows) {
          await deletePhoto(image, client: client);
        }
      }
      await attachStagedPhotos(existing.id, borrowedAt, stagedPhotoPaths);
      await (_db.update(
        _db.debtNotes,
      )..where((n) => n.id.equals(existing.id))).write(
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
    return (_db.select(
      _db.debtNotes,
    )..where((n) => n.id.equals(existing.id))).getSingle();
  }

  /// 删除借条：记录、照片、还款分笔与关联账户余额影响同步撤销；
  /// [client] 非空时异步清云端对象
  Future<void> deleteDebtNote(
    DebtNote note, {
    S3CompatibleClient? client,
  }) async {
    await _db.transaction(() async {
      // 先级联撤销全部还款分笔：本金部分撤销账户扣款/收款，利息账单
      // 删除时经 applyBillEffect 自动撤销其余额影响
      final repayments = await (_db.select(
        _db.debtNoteRepayments,
      )..where((r) => r.noteId.equals(note.id))).get();
      for (final r in repayments) {
        await _applyRepaymentEffect(
          note.direction,
          // 撤销按各笔落库的还款账户精确回加（迁移已回填历史记录）
          relatedAssetId: r.repayAssetId,
          principalCents: r.amountCents,
          revert: true,
        );
        await _deleteInterestBill(r);
        await (_db.delete(
          _db.debtNoteRepayments,
        )..where((x) => x.id.equals(r.id))).go();
      }
      await (_db.delete(
        _db.debtNotes,
      )..where((n) => n.id.equals(note.id))).go();
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

  // ---------- 还款分笔 ----------

  /// 应用/撤销一笔还款本金部分对关联账户的影响（必须在调用方事务内）：
  /// 借入还款 = 钱从关联账户出（资产减/信用卡欠款增），借出收款 = 钱回
  /// 关联账户；撤销取反。利息部分由利息支出账单的既有链路处理，
  /// 这里只管本金
  Future<void> _applyRepaymentEffect(
    DebtDirection direction, {
    required int? relatedAssetId,
    required int principalCents,
    required bool revert,
  }) async {
    if (relatedAssetId == null || principalCents <= 0) return;
    final isOutflow = direction == DebtDirection.borrowIn;
    await _assetRepo.applyAccountDelta(
      relatedAssetId,
      isOutflow: revert ? !isOutflow : isOutflow,
      amountCents: principalCents,
      // 应用新影响（扣款）校验余额不足；撤销旧影响不校验
      enforceBalance: !revert,
    );
  }

  /// 删除一笔还款关联的利息支出账单：账单行删除时经 applyBillEffect
  /// 自动撤销其账户余额影响（同事务调用）
  Future<void> _deleteInterestBill(DebtNoteRepayment repayment) async {
    final billId = repayment.interestBillId;
    if (billId == null) return;
    final bill = await (_db.select(
      _db.bills,
    )..where((b) => b.id.equals(billId))).getSingleOrNull();
    if (bill == null) return;
    await (_db.delete(_db.bills)..where((b) => b.id.equals(billId))).go();
    await _assetRepo.applyBillEffect(oldBill: bill);
  }

  /// 某借条的全部还款分笔流（详情弹窗订阅：已还/剩余与记录列表数据源）
  Stream<List<DebtNoteRepayment>> watchRepaymentsByNote(int noteId) {
    return (_db.select(_db.debtNoteRepayments)
          ..where((r) => r.noteId.equals(noteId))
          ..orderBy([
            (r) => OrderingTerm.desc(r.repaidAt),
            (r) => OrderingTerm.desc(r.id),
          ]))
        .watch();
  }

  /// 各借条已还本金总额流（noteId → 分）：借条列表/合计的"剩余"口径
  /// 数据源。amount_cents 即本金口径（v17 起落库），直接求和
  Stream<Map<int, int>> watchRepaidPrincipalTotals() {
    return _db
        .customSelect(
          'SELECT note_id, SUM(amount_cents) '
          'AS paid FROM debt_note_repayments GROUP BY note_id',
          readsFrom: {_db.debtNoteRepayments},
        )
        .watch()
        .map(
          (rows) => {
            for (final r in rows)
              r.data['note_id'] as int: r.data['paid'] as int,
          },
        );
  }

  /// 指定范围的还款流（首页明细混排）：与借条同口径下沉 SQL 过滤，
  /// 避免全表 watch 后 Dart 层过滤导致范围外变动也触发重发射
  Stream<List<DebtNoteRepayment>> watchRepaymentsInMonth(DateTime month) {
    return _watchRepaymentsBetween(
      DateTime(month.year, month.month, 1),
      DateTime(month.year, month.month + 1, 1),
    );
  }

  /// 指定年份的还款流
  Stream<List<DebtNoteRepayment>> watchRepaymentsInYear(int year) {
    return _watchRepaymentsBetween(DateTime(year, 1, 1), DateTime(year + 1, 1, 1));
  }

  /// 全部还款流（首页"全部"模式：还款记录量级小，全表参与混排）
  Stream<List<DebtNoteRepayment>> watchRepaymentsAll() {
    return (_db.select(_db.debtNoteRepayments)
          ..orderBy([
            (r) => OrderingTerm.desc(r.repaidAt),
            (r) => OrderingTerm.desc(r.id),
          ]))
        .watch();
  }

  Stream<List<DebtNoteRepayment>> _watchRepaymentsBetween(
    DateTime start,
    DateTime end,
  ) {
    return (_db.select(_db.debtNoteRepayments)
          ..where(
            (r) =>
                r.repaidAt.isBiggerOrEqualValue(start) &
                r.repaidAt.isSmallerThanValue(end),
          )
          ..orderBy([
            (r) => OrderingTerm.desc(r.repaidAt),
            (r) => OrderingTerm.desc(r.id),
          ]))
        .watch();
  }

  /// 关联某账户的还款流（账户流水页混排）：按还款落库的实际账户过滤
  /// （repayAssetId，与本金扣减/利息账单挂靠同口径），join 借条仅为
  /// 取对方名等展示信息
  Stream<List<DebtNoteRepayment>> watchRepaymentsOfAsset(int assetId) {
    final query =
        _db.select(_db.debtNoteRepayments).join([
            innerJoin(
              _db.debtNotes,
              _db.debtNotes.id.equalsExp(_db.debtNoteRepayments.noteId),
            ),
          ])
          ..where(_db.debtNoteRepayments.repayAssetId.equals(assetId))
          ..orderBy([
            OrderingTerm.desc(_db.debtNoteRepayments.repaidAt),
            OrderingTerm.desc(_db.debtNoteRepayments.id),
          ]);
    return query.watch().map(
      (rows) =>
          rows.map((r) => r.readTable(_db.debtNoteRepayments)).toList(),
    );
  }

  /// 该借条最近一次使用的利息分类 id（记还款时分类记忆带出）；
  /// 无历史还款分类返回 null（由用户选择）
  Future<int?> latestRepaymentCategoryId(int noteId) async {
    final row =
        await (_db.select(_db.debtNoteRepayments)
              ..where(
                (r) => r.noteId.equals(noteId) & r.categoryId.isNotNull(),
              )
              ..orderBy([
                (r) => OrderingTerm.desc(r.repaidAt),
                (r) => OrderingTerm.desc(r.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row?.categoryId;
  }

  /// 记一笔还款（同事务完成三条联动）：
  /// ① 利息部分（拆分时）生成支出账单——明细展示与余额影响全走
  ///    账单既有链路；② 本金部分直接增减关联账户余额；③ 落还款记录
  ///
  /// [interestCents] 非空时 [categoryId] 必传（利息账单要带分类）；
  /// 关联账户余额不足时抛 [InsufficientBalanceException] 整体回滚。
  /// 返回落库后的还款记录
  Future<DebtNoteRepayment> addRepayment({
    required DebtNote note,
    required int amountCents,
    required DateTime repaidAt,
    int? interestCents,
    int? categoryId,
    required int? repayAssetId,
    String? remark,
  }) async {
    assert(
      interestCents == null || interestCents > 0,
      '利息拆分必须为正数',
    );
    return _db.transaction(() async {
      // ⓪ 超额校验：还款本金不能超过借条剩余欠款（借入还款与借出
      // 收款同理），超额拒绝落库避免剩余变负
      if (amountCents >
          note.amountCents - await repaidPrincipalTotal(note.id)) {
        throw RepaymentExceedsException();
      }
      // ① 利息支出账单：先插账单拿 id，再落还款记录引用（删除时级联）
      int? billId;
      if (interestCents != null) {
        // 局部非空变量：drift equals 需要 int，类型提升只在局部生效
        final newBillId = await _db
            .into(_db.bills)
            .insert(
              BillsCompanion.insert(
                type: BillType.expense,
                amountCents: interestCents,
                categoryId: Value(categoryId),
                note: Value('利息·${note.personName}'),
                date: DateTime(repaidAt.year, repaidAt.month, repaidAt.day),
                timeMinute: Value(repaidAt.hour * 60 + repaidAt.minute),
                // 利息也是从还款账户扣的：挂还款账户（null = 纯台账）
                assetId: Value(repayAssetId),
              ),
            );
        final bill = await (_db.select(
          _db.bills,
        )..where((b) => b.id.equals(newBillId))).getSingle();
        await _assetRepo.applyBillEffect(newBill: bill);
        billId = newBillId;
      }
      // ② 本金部分联动还款账户（借入还款扣钱 / 借出收款回钱）；
      // amountCents 即纯本金（v17 起落库口径），直接联动
      await _applyRepaymentEffect(
        note.direction,
        relatedAssetId: repayAssetId,
        principalCents: amountCents,
        revert: false,
      );
      // ③ 落还款记录
      final id = await _db
          .into(_db.debtNoteRepayments)
          .insert(
            DebtNoteRepaymentsCompanion.insert(
              noteId: note.id,
              amountCents: amountCents,
              interestCents: Value(interestCents),
              categoryId: Value(categoryId),
              interestBillId: Value(billId),
              repayAssetId: Value(repayAssetId),
              note: Value(remark),
              repaidAt: repaidAt,
            ),
          );
      return (_db.select(
        _db.debtNoteRepayments,
      )..where((r) => r.id.equals(id))).getSingle();
    });
  }

  /// 删除一笔还款：撤销本金联动（账户余额加回/扣回）、级联删利息
  /// 账单（余额影响自动撤销）、删还款记录。借条归属信息内部自查，
  /// 不依赖调用方传参
  Future<void> deleteRepayment(DebtNoteRepayment repayment) async {
    await _db.transaction(() async {
      final note = await (_db.select(
        _db.debtNotes,
      )..where((n) => n.id.equals(repayment.noteId))).getSingleOrNull();
      if (note != null) {
        await _applyRepaymentEffect(
          note.direction,
          // 撤销按落库的还款账户精确回加（迁移已回填历史记录）
          relatedAssetId: repayment.repayAssetId,
          principalCents: repayment.amountCents,
          revert: true,
        );
      }
      await _deleteInterestBill(repayment);
      await (_db.delete(
        _db.debtNoteRepayments,
      )..where((r) => r.id.equals(repayment.id))).go();
    });
  }

  /// 某借条已还本金总额（编辑借条校验新金额时用）
  Future<int> repaidPrincipalTotal(int noteId) async {
    final row =
        await _db
            .customSelect(
              'SELECT COALESCE(SUM(amount_cents), 0) '
              'AS paid FROM debt_note_repayments WHERE note_id = ?',
              variables: [Variable(noteId)],
            )
            .getSingle();
    return row.data['paid'] as int;
  }

  // ---------- 照片删除 ----------

  /// 删除单张照片：记录与本地文件同步删；[client] 非空时异步删云端
  /// 对象（失败留孤儿可接受，静默不打扰）
  Future<void> deletePhoto(
    DebtNoteImage image, {
    S3CompatibleClient? client,
  }) async {
    await (_db.delete(
      _db.debtNoteImages,
    )..where((i) => i.id.equals(image.id))).go();
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

  /// 用编辑后的新照片替换一张已入库照片（图片编辑"删旧存新"）：
  /// 新图走压缩暂存 → 按借款日期转正 → 写新行（sort 继承原图），
  /// 旧行/旧本地文件/云端对象走 [deletePhoto] 统一清理。
  /// 返回新记录（pending，由调用方触发上传）；暂存失败返回 null
  Future<DebtNoteImage?> replacePhoto(
    DebtNoteImage old,
    Uint8List bytes, {
    S3CompatibleClient? client,
  }) async {
    final note = await (_db.select(
      _db.debtNotes,
    )..where((n) => n.id.equals(old.noteId))).getSingle();
    final stagedPath = await photos.stage(bytes);
    final src = File(stagedPath);
    if (!await src.exists()) return null;
    final name = photos.finalFileName(note.borrowedAt, old.noteId);
    final dest = p.join((await photos.monthDir(note.borrowedAt)).path, name);
    try {
      await src.rename(dest);
    } on FileSystemException {
      await src.copy(dest);
      await src.delete();
    }
    final id = await _db
        .into(_db.debtNoteImages)
        .insert(
          DebtNoteImagesCompanion.insert(
            noteId: old.noteId,
            objectKey: photos.objectKeyFor(note.borrowedAt, name),
            localPath: dest,
            uploadState: BillImageUploadState.pending,
            sort: Value(old.sort),
          ),
        );
    final created = await (_db.select(
      _db.debtNoteImages,
    )..where((i) => i.id.equals(id))).getSingle();
    await deletePhoto(old, client: client);
    return created;
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
  /// [onProgress] 每传完一张回调 (已完成张数, 总张数)，供手动补传的进度展示；
  /// 数据量为个人记账量级，全量取回后 Dart 端过滤足够
  Future<int> uploadPending(
    S3CompatibleClient client, {
    void Function(int done, int total)? onProgress,
  }) async {
    final rows = await _db.select(_db.debtNoteImages).get();
    final pending = rows
        .where((r) => r.uploadState != BillImageUploadState.done)
        .toList();
    var success = 0;
    var finished = 0;
    for (final image in pending) {
      if (await _uploadOne(image, client)) success++;
      onProgress?.call(++finished, pending.length);
    }
    return success;
  }

  /// 借据照片同步计数流（总数 + 未同步数）：同步页统计与红点角标的数据源
  Stream<({int total, int pending})> watchSyncCount() {
    return _db
        .select(_db.debtNoteImages)
        .watch()
        .map(
          (rows) => (
            total: rows.length,
            pending: rows
                .where((r) => r.uploadState != BillImageUploadState.done)
                .length,
          ),
        );
  }

  /// 手动重传单张（编辑页"未上传"角标点击触发），返回是否成功
  Future<bool> uploadOne(DebtNoteImage image, S3CompatibleClient client) =>
      _uploadOne(image, client);

  /// 上传单张：本地文件已丢的记录直接作废（图片本体没了，记录只剩
  /// 空壳；借条本体不受影响）；上传失败改 failed 等待补传，不在这里重试
  Future<bool> _uploadOne(
    DebtNoteImage image,
    S3CompatibleClient client,
  ) async {
    final file = File(image.localPath);
    if (!await file.exists()) {
      await (_db.delete(
        _db.debtNoteImages,
      )..where((i) => i.id.equals(image.id))).go();
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
