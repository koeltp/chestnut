import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../providers/debt_note_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/repayment_detail_sheet.dart';
import '../../widgets/repayment_flow_row.dart';
import '../../widgets/section_card.dart';

/// 全屏页：单张借条的还款记录
///
/// 从借条详情弹窗进入，只展示该借条的还款分笔；顶部汇总卡显示
/// 剩余欠款、还款进度条与「已还本金 / 已还利息」两列（纯派生值，
/// 随流实时刷新）；列表按月分组，行点击弹还款详情（删除入口在
/// 详情内，余额联动自动撤销）。
class DebtRepaymentListPage extends StatefulWidget {
  const DebtRepaymentListPage({super.key, required this.note});

  /// 还款归属的借条（原始本金、对方名的数据源）
  final DebtNote note;

  @override
  State<DebtRepaymentListPage> createState() => _DebtRepaymentListPageState();
}

class _DebtRepaymentListPageState extends State<DebtRepaymentListPage> {
  /// 流在页面生命周期内恒定：只建一次，重建不重订阅
  late final Stream<List<DebtNoteRepayment>> _repaymentStream = context
      .read<DebtNoteProvider>()
      .repaymentsByNoteStream(widget.note.id);

  @override
  Widget build(BuildContext context) {
    final isLendOut = widget.note.direction == DebtDirection.lendOut;
    return Scaffold(
      appBar: AppBar(
        title: Text(isLendOut ? '收款记录' : '还款记录'),
      ),
      body: StreamBuilder<List<DebtNoteRepayment>>(
        stream: _repaymentStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final repayments = snapshot.data!;
          // 已还本金 = Σ(还款额 − 利息)；已还利息 = Σ利息
          final repaidPrincipal = repayments.fold<int>(
            0,
            (s, r) => s + r.amountCents - (r.interestCents ?? 0),
          );
          final repaidInterest = repayments.fold<int>(
            0,
            (s, r) => s + (r.interestCents ?? 0),
          );
          final remaining = widget.note.amountCents - repaidPrincipal;
          final settled = remaining <= 0;
          final progress = settled
              ? 1.0
              : (repaidPrincipal / widget.note.amountCents).clamp(0.0, 1.0);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSection,
              AppDimens.pagePadding,
              24,
            ),
            children: [
              _buildSummaryCard(
                isLendOut: isLendOut,
                remaining: remaining,
                settled: settled,
                progress: progress,
                repaidPrincipal: repaidPrincipal,
                repaidInterest: repaidInterest,
              ),
              const SizedBox(height: AppDimens.gapSection),
              if (repayments.isEmpty)
                const _EmptyHint()
              else
                ..._buildMonthGroups(repayments),
            ],
          );
        },
      ),
    );
  }

  /// 汇总卡：剩余欠款大字 + 进度条 + 已还本金/已还利息两列
  Widget _buildSummaryCard({
    required bool isLendOut,
    required int remaining,
    required bool settled,
    required double progress,
    required int repaidPrincipal,
    required int repaidInterest,
  }) {
    final amountColor = isLendOut ? AppColors.expense : AppColors.income;
    final interestColor = isLendOut ? AppColors.income : AppColors.expense;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settled ? '已结清' : '剩余欠款',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${isLendOut ? '-' : '+'}¥'
            '${MoneyUtil.centsToYuanGroupedTrimmed(
              settled ? 0 : remaining,
            )}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: settled ? AppColors.income : amountColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          // 进度条：细圆角条 + 右侧百分比；结清满条
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.fill,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      settled ? AppColors.income : AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.gapMd),
              Text(
                '已还 ${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapMd),
          // 两列：已还本金 / 已还利息（利息着色跟随方向：借入 = 成本红，
          // 借出 = 收益绿）
          Row(
            children: [
              Expanded(
                child: _SummaryCell(
                  label: '已还本金',
                  cents: repaidPrincipal,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(width: 1, height: 28, color: AppColors.divider),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: AppDimens.gapMd),
                  child: _SummaryCell(
                    label: '已还利息',
                    cents: repaidInterest,
                    color: repaidInterest > 0
                        ? interestColor
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 按月分组：组头「yyyy年M月」+ 该月记录卡片；还款流已按日期倒序，
  /// 分组按插入序迭代即保持跨月先后
  List<Widget> _buildMonthGroups(List<DebtNoteRepayment> repayments) {
    final groups = <String, List<DebtNoteRepayment>>{};
    final monthOrder = <String>[];
    for (final r in repayments) {
      final key = '${r.repaidAt.year}-${r.repaidAt.month}';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        monthOrder.add(key);
      }
      groups[key]!.add(r);
    }
    return [
      for (final key in monthOrder) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            _monthLabel(key),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < groups[key]!.length; i++) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                RepaymentFlowRow(
                  repayment: groups[key]![i],
                  debtNote: widget.note,
                  onTap: () => showRepaymentDetailSheet(
                    context,
                    repayment: groups[key]![i],
                    note: widget.note,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimens.gapMd),
      ],
    ];
  }

  String _monthLabel(String key) {
    final parts = key.split('-');
    return '${parts[0]}年${int.parse(parts[1])}月';
  }
}

/// 汇总单元：标签 + 金额（汇总卡两列用）
class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.cents,
    required this.color,
  });

  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '¥${MoneyUtil.centsToYuanGroupedTrimmed(cents)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 空态引导
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: AppDimens.gapSm),
            const Text(
              '还没有还款记录，点击详情里的记还款开始',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
