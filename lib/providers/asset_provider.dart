import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/repositories/asset_repository.dart';
import '../models/enums.dart';

/// 资产状态管理
///
/// 仓储流的薄封装 + 金额模糊开关：净资产属敏感数字，"我的"页入口卡
/// 与资产页共享同一 [masked] 状态，点击切换后两处同步明文/模糊。
class AssetProvider extends ChangeNotifier {
  AssetProvider(this._repo, this._prefs);

  final AssetRepository _repo;
  final SharedPreferences _prefs;

  /// 金额模糊开关的持久化键：用户选择跨重启/更新保留
  static const _kMasked = 'asset_amount_masked';

  /// 金额是否模糊显示。未存过（首次安装）默认模糊；
  /// 用户切换后写入，重启 App / 覆盖更新均保持上次选择
  bool get masked => _prefs.getBool(_kMasked) ?? true;

  Future<void> toggleMasked() async {
    await _prefs.setBool(_kMasked, !masked);
    notifyListeners();
  }

  /// 未归档资产流（资产区/负债区列表）
  Stream<List<Asset>> activeStream() => _repo.watchActive();

  /// 已归档资产流（列表底部折叠区）
  Stream<List<Asset>> archivedStream() => _repo.watchArchived();

  /// id → 资产映射（含已归档）：账单条目"金额下方账户小字"按 id 查名
  Stream<Map<int, Asset>> assetsMapStream() =>
      _repo.watchAll().map((list) => {for (final a in list) a.id: a});

  /// 汇总流：资产/负债合计、净值、分类构成
  Stream<AssetSummary> summaryStream() => _repo.watchSummary();

  /// 历史净值序列（不含今天的快照聚合点）
  Stream<List<NetValuePoint>> netHistoryStream() => _repo.watchNetHistory();

  /// 新增资产（同时落初始快照）
  Future<void> addAsset({
    required String name,
    required AssetKind kind,
    required String category,
    required int valueCents,
    String? note,
    bool includeInNet = true,
    int? creditLimitCents,
    int? billDay,
    int? repayDay,
  }) => _repo.insertAsset(
    name: name,
    kind: kind,
    category: category,
    valueCents: valueCents,
    note: note,
    includeInNet: includeInNet,
    creditLimitCents: creditLimitCents,
    billDay: billDay,
    repayDay: repayDay,
  );

  /// 更新资产信息（名称/分类/备注/开关/信用卡字段）
  Future<void> updateInfo(
    Asset asset, {
    required String name,
    required String category,
    String? note,
    bool? includeInNet,
    int? creditLimitCents,
    int? billDay,
    int? repayDay,
  }) => _repo.updateInfo(
    asset,
    name: name,
    category: category,
    note: note,
    includeInNet: includeInNet,
    creditLimitCents: creditLimitCents,
    billDay: billDay,
    repayDay: repayDay,
  );

  /// 更新市值（落快照）
  Future<void> updateValue(Asset asset, int valueCents) =>
      _repo.updateValue(asset, valueCents);

  /// 归档 / 取消归档
  Future<void> setArchived(Asset asset, {required bool archived}) =>
      _repo.setArchived(asset, archived: archived);
}
