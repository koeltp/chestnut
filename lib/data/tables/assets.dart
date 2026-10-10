import 'package:drift/drift.dart';

import '../../models/enums.dart';

/// 资产表（净资产盘点）
///
/// 与账单体系相互独立：账单记"钱的流动"，资产记"钱的存量"。
/// 市值全部手动维护，[valueCents] 恒为正数——负债也存正数，
/// 资产/负债由 [kind] 区分，净值 = Σ资产 − Σ负债。
/// 每次市值变动都会在 [AssetSnapshots] 落一条快照，作为净值曲线的数据源。
/// [archived] 为软删除：归档后不参与净值/占比/曲线，历史快照保留。
class Assets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 资产名称，如"招行储蓄卡"、"婚房"
  TextColumn get name => text()();

  /// 类型：资产 / 负债
  IntColumn get kind => intEnum<AssetKind>()();

  /// 分类名（预设固定集，见 AssetGroups），如"现金"、"信用卡"
  TextColumn get category => text()();

  /// 当前市值，单位：分（恒为正数，负债由 kind 区分）
  IntColumn get valueCents => integer()();

  /// 备注，可为空
  TextColumn get note => text().nullable()();

  /// 排序权重（越小越靠前），新建时追加到同类型末尾
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 归档标记：true = 已归档，不参与净值统计
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// 是否计入总资产：false = 只在列表展示，不参与净值/占比统计
  BoolColumn get includeInNet => boolean().withDefault(const Constant(true))();

  /// 信用卡总额度，单位：分；null = 非信用卡分类或未填写
  IntColumn get creditLimitCents => integer().nullable()();

  /// 信用卡出账日（1~31）；null = 非信用卡分类或未填写
  IntColumn get billDay => integer().nullable()();

  /// 信用卡还款日（1~31）；null = 非信用卡分类或未填写
  IntColumn get repayDay => integer().nullable()();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 最近一次市值或信息更新时间
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 资产市值快照表（净值曲线数据源）
///
/// 只增不删：一次市值更新落一条快照，同一天多次更新都保留，
/// 聚合净值曲线时每日取当天最后一条。
@TableIndex(name: 'asset_snapshots_asset_day', columns: {#assetId, #day})
class AssetSnapshots extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属资产
  IntColumn get assetId => integer().references(Assets, #id)();

  /// 快照日期，格式 `yyyy-MM-dd`
  TextColumn get day => text()();

  /// 快照时刻的市值，单位：分（恒为正数，负债由资产 kind 区分）
  IntColumn get valueCents => integer()();

  /// 快照时间：同一天多次更新时用于取"当天最后一条"
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
