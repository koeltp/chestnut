import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositories/bill_repository.dart';
import '../data/repositories/budget_repository.dart';
import '../models/summaries.dart';
import '../utils/month_util.dart';

/// 预算状态管理
///
/// 面向预算页：提供某月预算与该月支出汇总两条数据流，以及预算设置入口。
class BudgetProvider extends ChangeNotifier {
  BudgetProvider(this._repo, this._billRepo);

  final BudgetRepository _repo;
  final BillRepository _billRepo;

  /// 某月预算流（未设置时发出 null）
  Stream<Budget?> budgetStream(DateTime month) =>
      _repo.watchBudget(MonthUtil.toKey(month));

  /// 某月支出汇总流（预算进度依赖当月已支出金额）
  Stream<MonthSummary> summaryStream(DateTime month) =>
      _billRepo.watchMonthSummary(month);

  /// 设置某月预算金额（分）
  Future<void> setBudget(DateTime month, int amountCents) =>
      _repo.setBudget(MonthUtil.toKey(month), amountCents);
}
