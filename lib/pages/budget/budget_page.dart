import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/summaries.dart';
import '../../providers/budget_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/money_util.dart';
import '../../widgets/month_switcher.dart';
import '../../widgets/section_card.dart';

/// 预算页：月度总预算的查看与设置
///
/// 支持切换月份查看历史预算；预算进度以"当月支出 / 预算"呈现，
/// 用量超过 80% 转橙色警示、超支转红色。
class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  DateTime _month = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final provider = context.read<BudgetProvider>();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSm,
              AppDimens.pagePadding,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MonthSwitcher(
                month: _month,
                onChanged: (m) => setState(() => _month = m),
                foregroundColor: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<Budget?>(
              stream: provider.budgetStream(_month),
              builder: (context, budgetSnapshot) {
                final budget = budgetSnapshot.data;
                return StreamBuilder<MonthSummary>(
                  stream: provider.summaryStream(_month),
                  builder: (context, summarySnapshot) {
                    final summary = summarySnapshot.data ?? MonthSummary.empty;
                    return _BudgetCard(
                      month: _month,
                      budgetCents: budget?.amountCents,
                      spentCents: summary.expenseCents,
                      onEdit: () => _showEditSheet(
                        current: budget?.amountCents,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出预算编辑底部弹层
  Future<void> _showEditSheet({int? current}) async {
    final controller = TextEditingController(
      // 零头为 0 时省略小数，与全应用"输入多少显示多少"的习惯一致
      text: current == null ? '' : MoneyUtil.centsToYuanTrimmed(current),
    );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        // 键盘弹出时避免遮挡输入框
        padding: EdgeInsets.only(
          left: AppDimens.pagePadding,
          right: AppDimens.pagePadding,
          top: 4,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppDimens.pagePadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设置${_month.year}年${_month.month}月预算',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppDimens.gapLg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('¥', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.primary)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    maxLength: 12,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '0',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.gapLg),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusControl)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final cents = MoneyUtil.yuanToCents(controller.text);
    if (cents == null || cents <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入正确的预算金额'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    // 异步间隙后使用 context 前先检查 mounted
    if (!mounted) return;
    await context.read<BudgetProvider>().setBudget(_month, cents);
  }
}

/// 预算卡片
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.month,
    required this.budgetCents,
    required this.spentCents,
    required this.onEdit,
  });

  final DateTime month;
  final int? budgetCents;
  final int spentCents;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    // 进度与状态色：未设预算灰、<=80% 主色、80%~100% 橙、超支红
    final hasBudget = budgetCents != null && budgetCents! > 0;
    final progress = hasBudget ? spentCents / budgetCents! : 0.0;
    final color = !hasBudget
        ? AppColors.textSecondary
        : progress > 1
            ? AppColors.expense
            : progress > 0.8
                ? AppColors.warning
                : AppColors.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        AppDimens.gapSection,
        AppDimens.pagePadding,
        24,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.headerGradient,
            borderRadius: BorderRadius.circular(AppDimens.radiusHeader),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${month.year}年${month.month}月预算',
                    style: TextStyle(fontSize: 14, color: AppColors.onHeader(0.85)),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(hasBudget ? Icons.edit_outlined : Icons.add_circle_outline,
                              size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            hasBudget ? '修改' : '设置',
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                hasBudget ? '¥${MoneyUtil.centsToYuanGroupedTrimmed(budgetCents!)}' : '尚未设置预算',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (hasBudget) ...[
                const SizedBox(height: 16),
                // 预算用量进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.onHeader(0.25),
                    valueColor: AlwaysStoppedAnimation(
                      progress > 1 ? AppColors.expense : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '已用 ¥${MoneyUtil.centsToYuanGroupedTrimmed(spentCents)}（${(progress * 100).toStringAsFixed(0)}%）',
                      style: TextStyle(fontSize: 12, color: AppColors.onHeader(0.85)),
                    ),
                    const Spacer(),
                    Text(
                      progress > 1
                          ? '已超支 ¥${MoneyUtil.centsToYuanGroupedTrimmed(spentCents - budgetCents!)}'
                          : '剩余 ¥${MoneyUtil.centsToYuanGroupedTrimmed(budgetCents! - spentCents)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: progress > 1 ? const Color(0xFFFFD6D0) : Colors.white,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  '设置月度预算，掌控每一笔开销',
                  style: TextStyle(fontSize: 13, color: AppColors.onHeader(0.75)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimens.gapSection),
        // 状态说明条：与进度色呼应
        SectionCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.pagePadding,
            vertical: AppDimens.gapMd,
          ),
          child: Row(
            children: [
              Icon(
                hasBudget && progress > 1
                    ? Icons.error_outline
                    : hasBudget && progress > 0.8
                        ? Icons.warning_amber_outlined
                        : Icons.info_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !hasBudget
                      ? '本月还没设置预算，点击上方"设置"开始'
                      : progress > 1
                          ? '本月已超支，尽量管住手哦'
                          : progress > 0.8
                              ? '预算即将用尽，请理性消费'
                              : '预算使用状况良好，继续保持',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
