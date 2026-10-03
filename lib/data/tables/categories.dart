import 'package:drift/drift.dart';

import '../../models/enums.dart';

/// 账单分类表
///
/// 分类由用户可编辑（内置分类在首次建库时预置），图标与颜色以
/// codePoint / ARGB 整数存储，避免引入额外依赖。
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 分类名称，如"餐饮"
  TextColumn get name => text().withLength(min: 1, max: 20)();

  /// Material Icons 图标的 codePoint
  IntColumn get iconCode => integer()();

  /// 分类颜色（ARGB 整数），用于饼图与列表图标配色
  IntColumn get colorValue => integer()();

  /// 分类归属的账单类型（支出 / 收入）
  IntColumn get type => intEnum<BillType>()();

  /// 父分类 id：null 表示一级分类，非空表示挂在某一级分类下的子分类
  /// （仅支持两级，避免层级过深影响选择效率）
  IntColumn get parentId => integer().nullable()();

  /// 排序权重，越小越靠前
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
