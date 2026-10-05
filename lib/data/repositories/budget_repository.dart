import 'package:drift/drift.dart';

import '../database.dart';

/// 预算仓储：月度总预算与分类预算的查询、设置
///
/// 预算行按 categoryId 区分：0 = 月度总预算，> 0 = 该一级分类预算。
class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  /// 监听某月总预算（categoryId = 0；无记录则返回 null）
  Stream<Budget?> watchBudget(String month) {
    return (_db.select(_db.budgets)
          ..where((b) => b.month.equals(month) & b.categoryId.equals(0)))
        .watchSingleOrNull();
  }

  /// 一次性读取某月总预算（"沿用上月"按钮读取上月预算用）
  Future<Budget?> getBudget(String month) {
    return (_db.select(_db.budgets)
          ..where((b) => b.month.equals(month) & b.categoryId.equals(0)))
        .getSingleOrNull();
  }

  /// 监听某月全部分类预算（categoryId > 0，按分类 id 升序）
  Stream<List<Budget>> watchCategoryBudgets(String month) {
    return (_db.select(_db.budgets)
          ..where(
            (tbl) =>
                tbl.month.equals(month) & tbl.categoryId.isBiggerThanValue(0),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.categoryId)]))
        .watch();
  }

  /// 一次性读取多个月份的总预算（预算历史用），key 为 `yyyy-MM`
  Future<Map<String, int>> getBudgetsOfMonths(List<String> months) async {
    final rows = await (_db.select(
      _db.budgets,
    )..where((b) => b.month.isIn(months) & b.categoryId.equals(0))).get();
    return {for (final r in rows) r.month: r.amountCents};
  }

  /// 设置某月总预算：按 (month, categoryId) 唯一键 upsert
  ///
  /// 不能用 insertOnConflictUpdate——它默认只按主键 id 处理冲突，
  /// 修改已有预算会撞唯一约束抛 UNIQUE 异常（表现为保存没反应），
  /// 因此显式指定冲突目标为组合键。
  Future<void> setBudget(String month, int amountCents) {
    return _db
        .into(_db.budgets)
        .insert(
          BudgetsCompanion.insert(
            month: month,
            amountCents: amountCents,
            categoryId: const Value(0),
          ),
          onConflict: DoUpdate(
            (old) => BudgetsCompanion(amountCents: Value(amountCents)),
            target: [_db.budgets.month, _db.budgets.categoryId],
          ),
        );
  }

  /// 设置某分类当月预算；[amountCents] <= 0 时删除该行（清除预算）
  Future<void> setCategoryBudget(
    String month,
    int categoryId,
    int amountCents,
  ) async {
    if (amountCents <= 0) {
      await (_db.delete(_db.budgets)..where(
            (b) => b.month.equals(month) & b.categoryId.equals(categoryId),
          ))
          .go();
      return;
    }
    await _db
        .into(_db.budgets)
        .insert(
          BudgetsCompanion.insert(
            month: month,
            amountCents: amountCents,
            categoryId: Value(categoryId),
          ),
          onConflict: DoUpdate(
            (old) => BudgetsCompanion(amountCents: Value(amountCents)),
            target: [_db.budgets.month, _db.budgets.categoryId],
          ),
        );
  }
}
