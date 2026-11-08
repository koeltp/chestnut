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

  /// 所属机构（见 institutions.dart）：银行卡/信用卡=所属银行，
  /// 投资理财组=券商/平台等。与名称独立存储——账户可起名"工资卡"
  /// 而机构仍是"招商银行"。null = 未填写；其余分类恒为 null
  TextColumn get institution => text().nullable()();

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

/// 每日净值表（净值曲线唯一数据源）
///
/// 一行一天、按日稠密存储：空白天也落一行，值是前向填充后的水位
/// （"没录 = 还是上次那个数"）。曲线读取退化成一次按日期范围的有序
/// 扫表，不再 join 快照表 + 在 Dart 侧逐日铺点——那张表历史量上来后
/// 每次重建都要重算上千天，是资产页卡死/ANR 的主因。
///
/// 只写昨天及以前：今天的净值随资产表实时变化，由 UI 用汇总快照净值
/// 补末点，保证曲线末点与卡片数字始终一致。写入口径见
/// AppDatabase.rebuildNetValueDays。
class NetValueDays extends Table {
  /// 日期 `yyyy-MM-dd`，天然唯一（主键即幂等键）
  TextColumn get day => text()();

  /// 当日净值，单位：分（可为负）
  IntColumn get netCents => integer()();

  /// 最近一次重算时间（毫秒时间戳，排查脏数据用）
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {day};
}
