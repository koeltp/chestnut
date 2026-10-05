// 聚合统计模型
//
// 由仓储层聚合查询产生，供首页/统计/预算页展示使用。
import '../models/enums.dart';

/// 月度收支汇总
class MonthSummary {
  const MonthSummary({required this.expenseCents, required this.incomeCents});

  /// 当月支出总额（分）
  final int expenseCents;

  /// 当月收入总额（分）
  final int incomeCents;

  /// 结余 = 收入 - 支出
  int get balanceCents => incomeCents - expenseCents;

  static const empty = MonthSummary(expenseCents: 0, incomeCents: 0);
}

/// 按分类聚合的金额汇总（统计页占比与排行）
class CategorySummary {
  const CategorySummary({
    required this.categoryId,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    required this.type,
    required this.totalCents,
  });

  final int categoryId;
  final String name;
  final int iconCode;
  final int colorValue;
  final BillType type;

  /// 该分类当月总额（分）
  final int totalCents;
}

/// 单月收支趋势数据（统计页折线图）
class MonthlyTrend {
  const MonthlyTrend({
    required this.year,
    required this.month,
    required this.expenseCents,
    required this.incomeCents,
  });

  final int year;
  final int month;

  final int expenseCents;
  final int incomeCents;

  /// 月份标签，如 "4月"
  String get label => '$month月';
}

/// 单日汇总（首页按日分组的日期头）
class DaySummary {
  const DaySummary({required this.expenseCents, required this.incomeCents});

  final int expenseCents;
  final int incomeCents;
}
