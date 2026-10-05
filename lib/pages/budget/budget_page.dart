import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../models/summaries.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/money_util.dart';
import '../../widgets/category_avatar.dart';
import '../../widgets/month_switcher.dart';
import '../../widgets/section_card.dart';

/// 预算页：月度总预算与分类预算的查看、设置
///
/// 支持切换月份查看历史预算；预算进度以"当月支出 / 预算"呈现，
/// 用量超过 80% 转橙色警示、超支转红色。页面结构：
/// 总预算头部卡（含日均可用）→ 沿用上月提示 → 分类预算卡 →
/// 状态说明条 → 近 6 个月预算历史。
class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  DateTime _month = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 开关开启时：进入页面静默沿用上月预算（仅当前月、当月未设时）
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCarry());
  }

  /// 是否正在查看当前月份（沿用逻辑只作用于当前月，历史月不自动改动）
  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// 预算历史行模型
  Future<void> _autoCarry() async {
    if (!mounted) return;
    if (!context.read<SettingsProvider>().autoBudgetCarryEnabled) return;
    if (!_isCurrentMonth) return;
    final provider = context.read<BudgetProvider>();
    final cur = await provider.getBudget(_month);
    if (cur != null || !mounted) return;
    final now = DateTime.now();
    final last =
        await provider.getBudget(DateTime(now.year, now.month - 1));
    if (last != null && mounted) {
      await provider.setBudget(_month, last.amountCents);
    }
  }

  /// 手动沿用上月预算（沿用提示卡按钮）
  Future<void> _carryLastMonth() async {
    final now = DateTime.now();
    final last = await context
        .read<BudgetProvider>()
        .getBudget(DateTime(now.year, now.month - 1));
    if (!mounted) return;
    if (last == null || last.amountCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('上月也未设置预算'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await context.read<BudgetProvider>().setBudget(_month, last.amountCents);
  }

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
                final hasBudget =
                    budget != null && budget.amountCents > 0;
                return StreamBuilder<MonthSummary>(
                  stream: provider.summaryStream(_month),
                  builder: (context, summarySnapshot) {
                    final summary =
                        summarySnapshot.data ?? MonthSummary.empty;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimens.pagePadding,
                        AppDimens.gapSection,
                        AppDimens.pagePadding,
                        24,
                      ),
                      children: [
                        _BudgetHeader(
                          month: _month,
                          budgetCents: hasBudget ? budget.amountCents : null,
                          spentCents: summary.expenseCents,
                          onEdit: () => _showEditSheet(
                            current: hasBudget ? budget.amountCents : null,
                          ),
                        ),
                        const SizedBox(height: AppDimens.gapSection),
                        if (!hasBudget && _isCurrentMonth) ...[
                          _buildCarryCard(),
                          const SizedBox(height: AppDimens.gapSection),
                        ],
                        _buildCategoryBudgetSection(
                          totalBudgetCents:
                              hasBudget ? budget.amountCents : null,
                        ),
                        const SizedBox(height: AppDimens.gapSection),
                        _buildStatusBar(hasBudget, summary.expenseCents,
                            budget?.amountCents ?? 0),
                        const SizedBox(height: AppDimens.gapSection),
                        _buildHistoryCard(),
                      ],
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

  /// 状态色：未设预算灰、<=80% 主色、80%~100% 橙、超支红
  Color _statusColor(bool hasBudget, int spent, int budget) {
    if (!hasBudget) return AppColors.textSecondary;
    final progress = budget > 0 ? spent / budget : 0.0;
    if (progress > 1) return AppColors.expense;
    if (progress > 0.8) return AppColors.warning;
    return AppColors.primary;
  }

  /// 状态说明条：与进度色呼应
  Widget _buildStatusBar(bool hasBudget, int spent, int budget) {
    final progress = hasBudget && budget > 0 ? spent / budget : 0.0;
    final color = _statusColor(hasBudget, spent, budget);
    return SectionCard(
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
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// 沿用上月预算提示卡（仅当前月且本月未设总预算时显示）
  Widget _buildCarryCard() {
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapSm,
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '上月已设预算，要不要直接沿用？',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: _carryLastMonth,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '沿用',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 分类预算卡：列出全部一级支出分类，点行设置/清除当月金额。
  /// [totalBudgetCents] 为当月总预算（未设为 null）：标题右侧显示
  /// "已分配"总和，超过总预算时整段转橙色警示
  Widget _buildCategoryBudgetSection({required int? totalBudgetCents}) {
    final provider = context.read<BudgetProvider>();
    return SectionCard(
      padding: const EdgeInsets.only(bottom: 4),
      child: StreamBuilder<List<Category>>(
        stream: context.read<CategoryProvider>().categoriesStream(
              BillType.expense,
            ),
        builder: (context, catSnapshot) {
          final parents = (catSnapshot.data ?? const <Category>[])
              .where((c) => c.parentId == null)
              .toList();
          return StreamBuilder<List<CategorySummary>>(
            stream: provider.categorySummaryStream(_month),
            builder: (context, spentSnapshot) {
              final spentMap = {
                for (final s in spentSnapshot.data ?? const <CategorySummary>[])
                  s.categoryId: s.totalCents,
              };
              return StreamBuilder<List<Budget>>(
                stream: provider.categoryBudgetsStream(_month),
                builder: (context, budgetSnapshot) {
                  final budgetMap = {
                    for (final b in budgetSnapshot.data ?? const <Budget>[])
                      b.categoryId: b.amountCents,
                  };
                  // 已分配 = 各分类预算之和（只累加正数，忽略清除残留）
                  final allocated = budgetMap.values
                      .fold<int>(0, (sum, v) => sum + (v > 0 ? v : 0));
                  final anySet = allocated > 0;
                  final over = totalBudgetCents != null &&
                      allocated > totalBudgetCents;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimens.pagePadding,
                          AppDimens.gapMd,
                          AppDimens.pagePadding,
                          8,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '分类预算',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            // 详情弹窗同款结构：label 后 Expanded 铺满剩余
                            // 宽度、右对齐，Spacer+Flexible 会平分剩余
                            // 空间把长文字拦腰截成"..."
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                anySet
                                    ? (totalBudgetCents != null
                                        ? '已分配 ¥${MoneyUtil.centsToYuanGroupedTrimmed(allocated)}'
                                            ' / ¥${MoneyUtil.centsToYuanGroupedTrimmed(totalBudgetCents)}'
                                        : '已分配 ¥${MoneyUtil.centsToYuanGroupedTrimmed(allocated)}')
                                    : '未分配',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: over
                                      ? AppColors.warning
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (parents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(AppDimens.pagePadding),
                          child: Text(
                            '暂无支出分类',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ...[
                          for (final c in parents)
                            _categoryRow(c, spentMap, budgetMap),
                        ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// 单个分类预算行：头像 + 名称 + 细进度条 + 已用/预算金额
  Widget _categoryRow(
    Category c,
    Map<int, int> spentMap,
    Map<int, int> budgetMap,
  ) {
    final budget = budgetMap[c.id];
    final hasBudget = budget != null && budget > 0;
    final spent = spentMap[c.id] ?? 0;
    final progress = hasBudget ? spent / budget : 0.0;
    final amountColor = !hasBudget
        ? AppColors.textSecondary
        : progress > 1
            ? AppColors.expense
            : progress > 0.8
                ? AppColors.warning
                : AppColors.textPrimary;
    return InkWell(
      onTap: () => _showCategoryBudgetSheet(c, hasBudget ? budget : null),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
          vertical: 10,
        ),
        child: Row(
          children: [
            CategoryAvatar(
              name: c.name,
              iconCode: c.iconCode,
              color: c.colorValue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        hasBudget
                            ? '¥${MoneyUtil.centsToYuanGroupedTrimmed(spent)}'
                                ' / ¥${MoneyUtil.centsToYuanGroupedTrimmed(budget)}'
                            : '未设置',
                        style: TextStyle(fontSize: 12, color: amountColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: hasBudget ? progress.clamp(0.0, 1.0) : 0,
                      minHeight: 4,
                      backgroundColor:
                          AppColors.textSecondary.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(
                        !hasBudget
                            ? AppColors.textSecondary.withValues(alpha: 0.3)
                            : progress > 1
                                ? AppColors.expense
                                : progress > 0.8
                                    ? AppColors.warning
                                    : Color(c.colorValue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 软提醒确认框：分类预算总和超过总预算时弹一次，允许强行保存
  /// （照顾"先设高分类、总预算回头再调"的操作顺序）
  Future<bool> _confirmOverTotal(int allocated, int total) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('分配超过总预算'),
        content: Text(
          '分类预算总和 ¥${MoneyUtil.centsToYuanGroupedTrimmed(allocated)} '
          '已超过总预算 ¥${MoneyUtil.centsToYuanGroupedTrimmed(total)}，'
          '仍要保存吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// 弹出分类预算编辑弹层（含清除入口）
  Future<void> _showCategoryBudgetSheet(Category c, int? current) async {
    final provider = context.read<BudgetProvider>();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BudgetSheet(
        title: '「${c.name}」${_month.year}年${_month.month}月预算',
        initialText:
            current == null ? '' : MoneyUtil.centsToYuanTrimmed(current),
        showClear: current != null,
      ),
    );
    if (result == null || !mounted) return;
    if (result == 'clear') {
      await provider.setCategoryBudget(_month, c.id, 0);
      return;
    }
    final cents = MoneyUtil.yuanToCents(result);
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入正确的预算金额'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 软提醒：本分类新值替换旧值后，全部分类预算之和超过总预算时确认
    final total = await provider.getBudget(_month);
    if (!mounted) return;
    if (total != null && total.amountCents > 0) {
      final budgets = await provider.categoryBudgetsStream(_month).first;
      if (!mounted) return;
      final others = budgets.fold<int>(
        0,
        (sum, b) => b.categoryId == c.id
            ? sum
            : sum + (b.amountCents > 0 ? b.amountCents : 0),
      );
      if (others + cents > total.amountCents) {
        final ok = await _confirmOverTotal(others + cents, total.amountCents);
        if (!ok || !mounted) return;
      }
    }
    await provider.setCategoryBudget(_month, c.id, cents);
  }

  /// 弹出总预算编辑底部弹层
  Future<void> _showEditSheet({int? current}) async {
    final provider = context.read<BudgetProvider>();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BudgetSheet(
        title: '设置${_month.year}年${_month.month}月预算',
        initialText:
            current == null ? '' : MoneyUtil.centsToYuanTrimmed(current),
        showClear: false,
      ),
    );
    if (result == null || !mounted) return;
    final cents = MoneyUtil.yuanToCents(result);
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入正确的预算金额'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 软提醒：新总预算小于现有分类预算总和时确认（与分类端对称）
    final budgets = await provider.categoryBudgetsStream(_month).first;
    if (!mounted) return;
    final allocated = budgets.fold<int>(
      0,
      (sum, b) => sum + (b.amountCents > 0 ? b.amountCents : 0),
    );
    if (allocated > cents) {
      final ok = await _confirmOverTotal(allocated, cents);
      if (!ok || !mounted) return;
    }
    await provider.setBudget(_month, cents);
  }

  /// 近 6 个月预算历史卡（含当前查看月，往前推 5 个月）
  Widget _buildHistoryCard() {
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.gapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              4,
              AppDimens.pagePadding,
              8,
            ),
            child: Text(
              '近 6 个月',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          FutureBuilder<List<_HistoryRow>>(
            // 月份切换时重新加载（key 变化避免 FutureBuilder 缓存旧结果）
            key: ValueKey(_month),
            future: _loadHistory(),
            builder: (context, snapshot) {
              final rows = snapshot.data;
              if (rows == null) {
                return const Padding(
                  padding: EdgeInsets.all(AppDimens.pagePadding),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _historyRow(rows[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 加载近 6 个月的预算与实际支出
  Future<List<_HistoryRow>> _loadHistory() async {
    final provider = context.read<BudgetProvider>();
    final rows = <_HistoryRow>[];
    var m = DateTime(_month.year, _month.month);
    for (var i = 0; i < 6; i++) {
      final budget = await provider.getBudget(m);
      final summary = await provider.summaryStream(m).first;
      rows.add(_HistoryRow(
        month: m,
        budgetCents: budget?.amountCents,
        spentCents: summary.expenseCents,
      ));
      m = DateTime(m.year, m.month - 1);
    }
    return rows.reversed.toList();
  }

  /// 历史行：月份 + 预算额（未设灰"未设置"）+ 实际支出（超预算标红）
  Widget _historyRow(_HistoryRow row) {
    final cur = row.month;
    final label =
        cur.year == _month.year ? '${cur.month}月' : '${cur.year}年${cur.month}月';
    final hasBudget = row.budgetCents != null && row.budgetCents! > 0;
    final over = hasBudget && row.spentCents > row.budgetCents!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            child: Text(
              hasBudget
                  ? '预算 ¥${MoneyUtil.centsToYuanGroupedTrimmed(row.budgetCents!)}'
                  : '未设置预算',
              style: TextStyle(
                fontSize: 12,
                color: hasBudget
                    ? AppColors.textSecondary
                    : AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
          ),
          Text(
            '支出 ¥${MoneyUtil.centsToYuanGroupedTrimmed(row.spentCents)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: over ? AppColors.expense : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 预算历史行数据
class _HistoryRow {
  const _HistoryRow({
    required this.month,
    required this.budgetCents,
    required this.spentCents,
  });

  final DateTime month;

  /// 当月总预算（null/0 = 未设置）
  final int? budgetCents;

  /// 当月实际支出
  final int spentCents;
}

/// 预算头部卡（渐变底）：总额 + 进度 + 已用/剩余 + 日均可用
class _BudgetHeader extends StatelessWidget {
  const _BudgetHeader({
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

    // 日均可用：仅当前月且有预算且未超支时有意义
    final now = DateTime.now();
    final isCurrentMonth =
        month.year == now.year && month.month == now.month;
    final remainingCents = hasBudget ? budgetCents! - spentCents : 0;
    // 剩余天数含今天（今天还能花）
    final remainingDays =
        isCurrentMonth ? DateTime(now.year, now.month + 1).day - now.day + 1 : 0;
    final showDaily =
        hasBudget && isCurrentMonth && progress <= 1 && remainingDays > 0;
    final dailyCents =
        showDaily ? (remainingCents / remainingDays).round() : 0;

    return Container(
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
                style: TextStyle(
                    fontSize: 14, color: AppColors.onHeader(0.85)),
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
            hasBudget
                ? '¥${MoneyUtil.centsToYuanGroupedTrimmed(budgetCents!)}'
                : '尚未设置预算',
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
            // 日均可用：按本月剩余天数均摊剩余预算
            if (showDaily) ...[
              const SizedBox(height: 6),
              Text(
                '本月还剩 $remainingDays 天，日均可用 ¥${MoneyUtil.centsToYuanTrimmed(dailyCents)}',
                style: TextStyle(fontSize: 12, color: AppColors.onHeader(0.75)),
              ),
            ],
          ] else ...[
            const SizedBox(height: 4),
            Text(
              '设置月度预算，掌控每一笔开销',
              style: TextStyle(fontSize: 13, color: AppColors.onHeader(0.75)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 预算编辑弹层（总预算与分类预算共用）
///
/// 提交时 pop 输入文本；[showClear] 为真时附"清除预算"按钮（pop 'clear'），
/// 供分类预算清除使用。
class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({
    required this.title,
    required this.initialText,
    required this.showClear,
  });

  final String title;
  final String initialText;
  final bool showClear;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘弹出时避免遮挡输入框
      padding: EdgeInsets.only(
        left: AppDimens.pagePadding,
        right: AppDimens.pagePadding,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimens.pagePadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.gapLg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('¥',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  )),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  maxLength: 12,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusControl),
                ),
              ),
              onPressed: () => Navigator.pop(context, _controller.text),
              child: const Text('保存', style: TextStyle(fontSize: 16)),
            ),
          ),
          if (widget.showClear) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, 'clear'),
                child: const Text(
                  '清除预算',
                  style: TextStyle(fontSize: 14, color: AppColors.expense),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
