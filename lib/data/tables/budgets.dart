import 'package:drift/drift.dart';

/// 月度预算表
///
/// 每月一条总预算记录，[month] 使用 `yyyy-MM` 格式并建立唯一约束，
/// 便于直接按月查询与设置。
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 预算月份，格式 `yyyy-MM`
  TextColumn get month => text().unique()();

  /// 预算金额，单位：分
  IntColumn get amountCents => integer()();
}
