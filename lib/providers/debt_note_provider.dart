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

  /// 关联某账户的借条流（账户明细页流水混排用）
  Stream<List<DebtNote>> debtsOfAssetStream(int assetId) =>
      _repo.watchOfAsset(assetId);

  /// 监听哪些借条有照片（列表页附件角标用）
  Stream<Set<int>> photoNoteIdsStream() => _repo.watchNoteIdsWithPhotos();

  /// 压缩并暂存一张借据照片，返回暂存路径
  Future<String> stagePhoto(Uint8List raw) => _repo.stagePhoto(raw);

  /// 丢弃一张暂存照片
  Future<void> discardStagedPhoto(String path) =>
      _repo.discardStagedPhoto(path);

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
  }) =>
      _repo.insertDebtNote(
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
  }) =>
      _repo.updateDebtNote(
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
  Future<void> deleteDebtNote(
    DebtNote note, {
    S3CompatibleClient? client,
  }) =>
      _repo.deleteDebtNote(note, client: client);
}
