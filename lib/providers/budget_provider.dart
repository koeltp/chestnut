import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositories/bill_repository.dart';
import '../data/repositories/budget_repository.dart';
import '../models/enums.dart';
import '../models/summaries.dart';
import '../utils/month_util.dart';

/// 预算状态管理
///
/// 面向预算页：提供某月总预算/分类预算与当月支出汇总数据流，
/// 以及总预算与分类预算的设置入口。
class BudgetProvider extends ChangeNotifier {
  BudgetProvider(this._repo, this._billRepo);

  final BudgetRepository _repo;
  final BillRepository _billRepo;

  /// 某月总预算流（未设置时发出 null）
  Stream<Budget?> budgetStream(DateTime month) =>
      _repo.watchBudget(MonthUtil.toKey(month));

  /// 某月全部分类预算流（categoryId > 0）
  Stream<List<Budget>> categoryBudgetsStream(DateTime month) =>
      _repo.watchCategoryBudgets(MonthUtil.toKey(month));

  /// 某月支出汇总流（预算进度依赖当月已支出金额）
  Stream<MonthSummary> summaryStream(DateTime month) =>
      _billRepo.watchMonthSummary(month);

  /// 按一级分类聚合的某月支出流（分类预算的"已用"数据源，
  /// 子分类账单已归并到父分类，与分类预算的维度一致）
  Stream<List<CategorySummary>> categorySummaryStream(DateTime month) =>
      _billRepo.watchCategorySummary(BillType.expense, month);

  /// 读取某月总预算（一次性）
  Future<Budget?> getBudget(DateTime month) =>
      _repo.getBudget(MonthUtil.toKey(month));

  /// 一次性读取多个月份的总预算，key 为 `yyyy-MM`（预算历史用）
  Future<Map<String, int>> getBudgetsOfMonths(List<String> months) =>
      _repo.getBudgetsOfMonths(months);

  /// 设置某月总预算金额（分）
  Future<void> setBudget(DateTime month, int amountCents) =>
      _repo.setBudget(MonthUtil.toKey(month), amountCents);

  /// 设置/清除某分类当月预算（金额 <= 0 为清除）
  Future<void> setCategoryBudget(
    DateTime month,
    int categoryId,
    int amountCents,
  ) =>
      _repo.setCategoryBudget(MonthUtil.toKey(month), categoryId, amountCents);
}
