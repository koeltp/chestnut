import 'database.dart';

/// 流水条目：账单（收支/转账）、借条与借条还款的统一展示载体
///
/// 首页明细与账户流水页共用——三类异构记录经本类归一后，
/// 按业务日期组织日分组、按发生时刻排序（无时刻回退录入时间）。
class FlowEntry {
  const FlowEntry({
    required this.date,
    required this.createdAt,
    this.bill,
    this.debt,
    this.repayment,
  }) : assert(bill != null || debt != null || repayment != null);

  /// 业务日期：账单发生时间 / 借条借款日期 / 还款时间（决定日分组与显示）
  ///
  /// 账单精确到日（0 点），借条与还款含时刻——日内比较一律用
  /// [dayMinute]，天序比较须先归一到自然日，不能直接比 DateTime
  final DateTime date;

  /// 创建时间：发生时刻缺失或相同时的排序依据
  final DateTime createdAt;

  final Bill? bill;
  final DebtNote? debt;

  /// 借条还款分笔（含借出方向的收款）：冲减借条余额的资金动作
  final DebtNoteRepayment? repayment;

  /// 发生时刻的日内分钟数（0..1439）：账单取 timeMinute，借条取借款
  /// 日期的时分，还款取还款时间时分；null = 账单未填时刻
  int? get dayMinute {
    final b = bill, d = debt, r = repayment;
    if (b != null) return b.timeMinute;
    if (d != null) return d.borrowedAt.hour * 60 + d.borrowedAt.minute;
    if (r != null) return r.repaidAt.hour * 60 + r.repaidAt.minute;
    return null;
  }
}

/// 合并账单、借条与还款分笔为流水条目，按业务日期倒序。
///
/// 同一自然日内按发生时刻倒序（如 9:30 在 9:20 上方）；未填时刻的
/// 账单沉底，与 SQL 层 `timeMinute DESC` 的 NULLS LAST 行为一致；
/// 时刻缺失或相同时再按创建时间倒序（后建的记录在前）。
///
/// 不做去重——账单、借条、还款各自独立，同一笔现实业务可能产生
/// 多条记录（如借条放款与其后续的每笔还款），都应呈现
List<FlowEntry> buildFlowEntries(
  List<Bill> bills,
  List<DebtNote> debts, {
  List<DebtNoteRepayment> repayments = const [],
}) {
  return [
    for (final bill in bills)
      FlowEntry(date: bill.date, createdAt: bill.createdAt, bill: bill),
    for (final debt in debts)
      FlowEntry(date: debt.borrowedAt, createdAt: debt.createdAt, debt: debt),
    for (final repayment in repayments)
      FlowEntry(
        date: repayment.repaidAt,
        createdAt: repayment.createdAt,
        repayment: repayment,
      ),
  ]..sort((a, b) {
    // 借条/还款 date 含时刻、账单 date 是当日 0 点，直接比较会让同日
    // 借条因时刻膨胀恒在账单上方——先归一到自然日
    final byDay = _dayKey(b.date).compareTo(_dayKey(a.date));
    if (byDay != 0) return byDay;
    final am = a.dayMinute, bm = b.dayMinute;
    if (am != bm) {
      if (am == null) return 1;
      if (bm == null) return -1;
      return bm.compareTo(am);
    }
    return b.createdAt.compareTo(a.createdAt);
  });
}

/// 自然日键：y*10000+m*100+d，消掉日内时刻
int _dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
