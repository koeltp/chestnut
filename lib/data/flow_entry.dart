import 'database.dart';

/// 流水条目：账单（收支/转账）与借条的统一展示载体
///
/// 首页明细与账户流水页共用——两类异构记录经本类归一后，
/// 按业务日期组织日分组、按创建时间稳定排序。
class FlowEntry {
  const FlowEntry({
    required this.date,
    required this.createdAt,
    this.bill,
    this.debt,
  }) : assert(bill != null || debt != null);

  /// 业务日期：账单发生时间 / 借条借款日期（决定日分组与显示）
  final DateTime date;

  /// 创建时间：同一业务日期内的稳定排序依据
  final DateTime createdAt;

  final Bill? bill;
  final DebtNote? debt;
}

/// 合并账单与借条为流水条目，按业务日期倒序；
/// 同一业务日期内按创建时间倒序（后建的记录在前）。
///
/// 不做去重——账单与借条各自独立，同一笔现实业务可能同时产生
/// 一条账单和一条借条，两条都应呈现
List<FlowEntry> buildFlowEntries(List<Bill> bills, List<DebtNote> debts) {
  return [
    for (final bill in bills)
      FlowEntry(date: bill.date, createdAt: bill.createdAt, bill: bill),
    for (final debt in debts)
      FlowEntry(
        date: debt.borrowedAt,
        createdAt: debt.createdAt,
        debt: debt,
      ),
  ]..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return b.createdAt.compareTo(a.createdAt);
    });
}
