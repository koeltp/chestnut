import 'package:drift/drift.dart';

/// 月度预算表
///
/// [month] 使用 `yyyy-MM` 格式；[categoryId] 为 0 表示该月**总预算**，
/// 大于 0 表示该一级分类当月的分类预算。
/// 唯一约束为 (month, categoryId) 组合——同月内总预算与各分类预算
/// 各一条，互不冲突。注意不能用 NULL 表示总预算：SQLite 的 UNIQUE
/// 对含 NULL 的行视为互不相同，会导致总预算可重复插入。
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 预算月份，格式 `yyyy-MM`
  TextColumn get month => text()();

  /// 预算金额，单位：分
  IntColumn get amountCents => integer()();

  /// 预算归属：0 = 月度总预算；> 0 = 该分类（一级）当月预算
  IntColumn get categoryId => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [{month, categoryId}];
}
