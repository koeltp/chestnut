import 'package:flutter/material.dart';

import '../data/repositories/bill_repository.dart';
import '../models/enums.dart';
import '../models/summaries.dart';

/// 统计页状态管理
///
/// 维护统计页的月份与收支类型筛选，暴露分类占比、月度趋势两条数据流。
class StatsProvider extends ChangeNotifier {
  StatsProvider(this._repo);

  final BillRepository _repo;

  /// 当前统计的月份
  DateTime _selectedMonth = DateTime.now();
  DateTime get selectedMonth => _selectedMonth;

  /// 当前查看模式（按月 / 按年 / 全部），与首页"显示方式"弹窗同款
  HomePeriod _period = HomePeriod.month;
  HomePeriod get period => _period;

  /// 当前统计的收支类型（支出 / 收入）
  BillType _type = BillType.expense;
  BillType get type => _type;

  /// 分类占比流（按金额降序）
  ///
  /// 模式与月份由 UI 传入：StreamBuilder 持有旧流引用，内部读 _selectedMonth
  /// 会导致切月后仍订阅旧月份（与首页同款问题），故参数化。
  Stream<List<CategorySummary>> categorySummaryStream(
    HomePeriod period,
    DateTime month,
    BillType type,
  ) => switch (period) {
    HomePeriod.month => _repo.watchCategorySummary(type, month),
    // 年与全部复用区间版本：年传全年左闭右开，全部传双 null 不限
    HomePeriod.year => _repo.watchCategorySummaryBetween(
      type,
      DateTime(month.year),
      DateTime(month.year + 1),
    ),
    HomePeriod.all => _repo.watchCategorySummaryBetween(type, null, null),
  };

  /// 近 6 个月收支趋势流
  Stream<List<MonthlyTrend>> trendStream() => _repo.watchMonthlyTrend();

  /// 切换收支类型
  void changeType(BillType type) {
    if (type == _type) return;
    _type = type;
    notifyListeners();
  }

  /// 切换统计月份
  void changeMonth(DateTime month) {
    if (month.year == _selectedMonth.year &&
        month.month == _selectedMonth.month) {
      return;
    }
    _selectedMonth = month;
    notifyListeners();
  }

  /// 切换查看模式（按月 / 按年 / 全部）
  void changePeriod(HomePeriod period) {
    if (period == _period) return;
    _period = period;
    notifyListeners();
  }
}
