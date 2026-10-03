import 'package:drift/drift.dart' show DoUpdate, Value;

import '../database.dart';

/// 预算仓储：月度预算的查询与设置
class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  /// 监听某月预算（无记录则返回 null）
  Stream<Budget?> watchBudget(String month) {
    return (_db.select(_db.budgets)..where((b) => b.month.equals(month)))
        .watchSingleOrNull();
  }

  /// 设置某月预算：按 month 唯一键 upsert
  ///
  /// 不能用 insertOnConflictUpdate——它默认只按主键 id 处理冲突，
  /// 修改已有预算会撞 month 唯一约束抛 UNIQUE 异常（表现为保存没反应），
  /// 因此显式指定冲突目标为 month 列。
  Future<void> setBudget(String month, int amountCents) {
    return _db.into(_db.budgets).insert(
          BudgetsCompanion.insert(month: month, amountCents: amountCents),
          onConflict: DoUpdate(
            (old) => BudgetsCompanion(amountCents: Value(amountCents)),
            target: [_db.budgets.month],
          ),
        );
  }
}
