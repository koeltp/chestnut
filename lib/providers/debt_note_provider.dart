import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/repositories/debt_note_repository.dart';
import '../models/enums.dart';
import '../services/s3_compatible_client.dart';

/// 借条状态管理：仓储流的薄封装
class DebtNoteProvider extends ChangeNotifier {
  DebtNoteProvider(this._repo);

  final DebtNoteRepository _repo;

  /// 全部借条流（借条列表页 / 主页合计卡的间接数据源）
  Stream<List<DebtNote>> allStream() => _repo.watchAll();

  /// 监听哪些借条有照片（列表页附件角标用）
  Stream<Set<int>> photoNoteIdsStream() => _repo.watchNoteIdsWithPhotos();

  /// 压缩并暂存一张借据照片，返回暂存路径
  Future<String> stagePhoto(Uint8List raw) => _repo.photos.stage(raw);

  /// 丢弃一张暂存照片
  Future<void> discardStagedPhoto(String path) => _repo.photos.discard(path);

  /// 某借条的全部照片（编辑页初始化回显用）
  Future<List<DebtNoteImage>> photosByNoteId(int noteId) =>
      _repo.getPhotosByNoteId(noteId);

  /// 新增借条（返回落库后的实体，供调用方查询/上传照片）
  Future<DebtNote> addDebtNote({
    required DebtDirection direction,
    required String personName,
    required int amountCents,
    required DateTime borrowedAt,
    DateTime? repayDueAt,
    String? note,
    int? relatedAssetId,
    bool includeInTotal = true,
    List<String> stagedPhotoPaths = const [],
  }) => _repo.insertDebtNote(
    direction: direction,
    personName: personName,
    amountCents: amountCents,
    borrowedAt: borrowedAt,
    repayDueAt: repayDueAt,
    note: note,
    relatedAssetId: relatedAssetId,
    includeInTotal: includeInTotal,
    stagedPhotoPaths: stagedPhotoPaths,
  );

  /// 更新借条（照片参数：removedPhotoIds 删已有照片、stagedPhotoPaths
  /// 加新照片，可同时传；client 非空时同步清理被删照片的云端对象）
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
  }) => _repo.updateDebtNote(
    existing,
    personName: personName,
    amountCents: amountCents,
    borrowedAt: borrowedAt,
    repayDueAt: repayDueAt,
    note: note,
    relatedAssetId: relatedAssetId,
    includeInTotal: includeInTotal,
    removedPhotoIds: removedPhotoIds,
    stagedPhotoPaths: stagedPhotoPaths,
    client: client,
  );

  /// 删除借条（照片级联删除，client 非空时一并清云端对象）
  Future<void> deleteDebtNote(DebtNote note, {S3CompatibleClient? client}) =>
      _repo.deleteDebtNote(note, client: client);

  /// 记一笔还款/收款（同事务完成余额联动与利息账单生成）
  Future<DebtNoteRepayment> addRepayment({
    required DebtNote note,
    required int amountCents,
    required DateTime repaidAt,
    int? interestCents,
    int? categoryId,
    String? remark,
  }) => _repo.addRepayment(
    note: note,
    amountCents: amountCents,
    repaidAt: repaidAt,
    interestCents: interestCents,
    categoryId: categoryId,
    remark: remark,
  );

  /// 删除一笔还款（联动自动撤销）
  Future<void> deleteRepayment(DebtNoteRepayment repayment) =>
      _repo.deleteRepayment(repayment);

  /// 某借条的还款分笔流（详情弹窗：已还/剩余与记录列表）
  Stream<List<DebtNoteRepayment>> repaymentsByNoteStream(int noteId) =>
      _repo.watchRepaymentsByNote(noteId);

  /// 各借条已还本金总额流（noteId → 分）：列表页剩余口径
  Stream<Map<int, int>> repaidTotalsStream() =>
      _repo.watchRepaidPrincipalTotals();

  /// 全部还款流（还款记录页：跨借条聚合，日期倒序）
  Stream<List<DebtNoteRepayment>> repaymentsAllStream() =>
      _repo.watchRepaymentsAll();

  /// 该借条最近一次使用的利息分类 id（记还款分类记忆）
  Future<int?> latestRepaymentCategoryId(int noteId) =>
      _repo.latestRepaymentCategoryId(noteId);
}
