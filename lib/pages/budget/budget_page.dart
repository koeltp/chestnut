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
import '../../utils/show_toast.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/category_avatar.dart';
import '../../widgets/month_switcher.dart';
import '../../widgets/section_card.dart';

/// 预算页：月度总预算与分类预算的查看、设置
///
/// 支持切换月份查看历史预算；预算进度以"当月支出 / 预算"呈现，
/// 用量超过 80% 转橙色警示、超支转红色。页面结构：
/// 总预算头部卡（含日均可用）→ 预算模式卡 → 沿用上月提示 →
/// 分类预算卡 → 状态说明条 → 近 6 个月预算历史。
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
    // 按当前预算模式自动填充（仅当前月）：沿用上月预算 / 按上月消费
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyBudgetMode());
  }

  /// 是否正在查看当前月份（沿用逻辑只作用于当前月，历史月不自动改动）
  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// 按当前预算模式自动填充（仅当前月，历史月不改动）：
  /// A 沿用上月预算——未设的总预算/分类预算写上月对应值；
  /// B 按上月消费——未设的分类预算写上月实际消费，总预算未设时写各分类之和。
  /// 模式为未选（null，清空预算后）时不做任何自动填充，等用户点选
  Future<void> _applyBudgetMode() async {
    if (!mounted || !_isCurrentMonth) return;
    final mode = context.read<SettingsProvider>().budgetMode;
    if (mode == null) return;
    if (mode == BudgetMode.carryLastMonth) {
      await _carryLastMonthBudgets();
    } else {
      await _fillFromLastMonthSpend();
    }
  }

  /// 把 [sourceById]（categoryId → 金额）写入本月未设的分类预算，
  /// 已设的不覆盖（手动值优先），金额 <= 0 的源跳过
  Future<void> _fillMissingCategoryBudgets(Map<int, int> sourceById) async {
    if (!mounted) return;
    final provider = context.read<BudgetProvider>();
    final existing = await provider.categoryBudgetsStream(_month).first;
    final existingIds = {for (final b in existing) b.categoryId};
    for (final entry in sourceById.entries) {
      if (entry.value <= 0 || existingIds.contains(entry.key)) continue;
      await provider.setCategoryBudget(_month, entry.key, entry.value);
    }
  }

  /// 模式A：未设的总预算沿用上月总预算，未设的分类预算沿用上月分类预算
  Future<void> _carryLastMonthBudgets() async {
    if (!mounted) return;
    final provider = context.read<BudgetProvider>();
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);
    // 分类预算：未设的沿用上月
    final lastCategories = await provider
        .categoryBudgetsStream(lastMonth)
        .first;
    await _fillMissingCategoryBudgets({
      for (final b in lastCategories) b.categoryId: b.amountCents,
    });
    // 总预算：未设的沿用上月
    if (!mounted) return;
    // 0 元残留行（清空留下的记录）等同未设，允许沿用值覆盖——
    // 否则自动沿用看到记录存在就跳过，页面却显示"尚未设置"
    final cur = await provider.getBudget(_month);
    if ((cur?.amountCents ?? 0) > 0 || !mounted) return;
    final last = await provider.getBudget(lastMonth);
    if (last != null && last.amountCents > 0 && mounted) {
      await provider.setBudget(_month, last.amountCents);
    }
  }

  /// 模式B：未设的分类预算自动写入上月实际消费（上月无消费的跳过），
  /// 手动已设的不覆盖；总预算未设时写全部分类预算之和
  Future<void> _fillFromLastMonthSpend() async {
    if (!mounted) return;
    final provider = context.read<BudgetProvider>();
    final now = DateTime.now();
    final summaries = await provider.categorySummaries(
      DateTime(now.year, now.month - 1),
    );
    await _fillMissingCategoryBudgets({
      for (final s in summaries) s.categoryId: s.totalCents,
    });
    // 总预算 = 各分类预算合计（未设时才写，手动已设不动）
    if (!mounted) return;
    final all = await provider.categoryBudgetsStream(_month).first;
    final sum = all.fold<int>(0, (total, b) => total + b.amountCents);
    if (sum <= 0 || !mounted) return;
    final total = await provider.getBudget(_month);
    // 0 元残留行等同未设，允许写入合计（与模式A同口径）
    if ((total?.amountCents ?? 0) <= 0 && mounted) {
      await provider.setBudget(_month, sum);
    }
  }

  /// 清空当月全部预算（头部卡"清空"入口）：二次确认后一次清掉
  /// 总预算与所有分类预算；预算模式同时置为未选——分段器两段都不
  /// 选中，之后进页面不再自动填充，直到用户重新点选某个模式
  Future<void> _clearAllBudgets() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空预算'),
        content: const Text('总预算和所有分类预算都会被清除，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final provider = context.read<BudgetProvider>();
    final settings = context.read<SettingsProvider>();
    // 只清已设置（正数）的分类预算，减少无效写入
    final budgets = await provider.categoryBudgetsStream(_month).first;
    for (final b in budgets) {
      if (b.amountCents > 0) {
        await provider.setCategoryBudget(_month, b.categoryId, 0);
      }
    }
    await provider.setBudget(_month, 0);
    // 模式一并回到未选：分段器两段都无选中，避免"选中却没执行"的矛盾
    await settings.setBudgetMode(null);
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
                final hasBudget = budget != null && budget.amountCents > 0;
                return StreamBuilder<MonthSummary>(
                  stream: provider.summaryStream(_month),
                  builder: (context, summarySnapshot) {
                    final summary = summarySnapshot.data ?? MonthSummary.empty;
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
                          onClear: _clearAllBudgets,
                        ),
                        const SizedBox(height: AppDimens.gapSection),
                        if (_isCurrentMonth) ...[
                          _buildModeCard(),
                          const SizedBox(height: AppDimens.gapSection),
                        ],
                        _buildCategoryBudgetSection(
                          totalBudgetCents: hasBudget
                              ? budget.amountCents
                              : null,
                        ),
                        const SizedBox(height: AppDimens.gapSection),
                        _buildStatusBar(
                          hasBudget,
                          summary.expenseCents,
                          budget?.amountCents ?? 0,
                        ),
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
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 预算模式卡（仅当前月显示，历史月切换无效所以不展示）。
  /// 三行结构：标题+随模式说明 / 分段开关铺满 / 条下固定"！"说明行——
  /// 行为规则（只补未设、不动已设）常驻展示而不是切换时弹提示。
  /// 模式可为未选（清空预算后）：说明显通用文案，分段器两段都无选中
  Widget _buildModeCard() {
    final mode = context.watch<SettingsProvider>().budgetMode;
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: '预算模式：',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              children: [
                TextSpan(
                  text: switch (mode) {
                    BudgetMode.carryLastMonth => '未设的总预算和分类预算自动沿用上月',
                    BudgetMode.lastMonthSpend =>
                      '未设分类预算取上月实际消费，总预算取各分类之和',
                    null => '选择模式后立即按其规则填充本月预算',
                  },
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          AppSegmented<BudgetMode>(
            options: const [
              (BudgetMode.carryLastMonth, '沿用上月预算'),
              (BudgetMode.lastMonthSpend, '按上月消费'),
            ],
            selected: mode,
            fit: AppSegmentedFit.stretch,
            onChanged: (m) async {
              await context.read<SettingsProvider>().setBudgetMode(m);
              // 点选即生效：当前月按新模式立即补全未设项
              if (mounted) await _applyBudgetMode();
            },
          ),
          const SizedBox(height: AppDimens.gapSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '切换后立即补全本月未设项，已设置的金额不会被自动改动',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
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
                  final allocated = budgetMap.values.fold<int>(
                    0,
                    (sum, v) => sum + (v > 0 ? v : 0),
                  );
                  final anySet = allocated > 0;
                  final over =
                      totalBudgetCents != null && allocated > totalBudgetCents;
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
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      else ...[
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
                      backgroundColor: AppColors.textSecondary.withValues(
                        alpha: 0.12,
                      ),
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
        initialText: current == null
            ? ''
            : MoneyUtil.centsToYuanTrimmed(current),
      ),
    );
    if (result == null || !mounted) return;
    // 金额删空后保存 = 清除该分类预算（未设时空保存为无操作，幂等）
    if (result.isEmpty) {
      await provider.setCategoryBudget(_month, c.id, 0);
      return;
    }
    final cents = MoneyUtil.yuanToCents(result);
    if (cents == null || cents <= 0) {
      showAppToast(context, '请输入正确的预算金额');
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
        initialText: current == null
            ? ''
            : MoneyUtil.centsToYuanTrimmed(current),
      ),
    );
    if (result == null || !mounted) return;
    final cents = MoneyUtil.yuanToCents(result);
    if (cents == null || cents <= 0) {
      showAppToast(context, '请输入正确的预算金额');
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
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
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
      rows.add(
        _HistoryRow(
          month: m,
          budgetCents: budget?.amountCents,
          spentCents: summary.expenseCents,
        ),
      );
      m = DateTime(m.year, m.month - 1);
    }
    return rows.reversed.toList();
  }

  /// 历史行：月份 + 预算额（未设灰"未设置"）+ 实际支出（超预算标红）
  Widget _historyRow(_HistoryRow row) {
    final cur = row.month;
    final label = cur.year == _month.year
        ? '${cur.month}月'
        : '${cur.year}年${cur.month}月';
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
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
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
    required this.onClear,
  });

  final DateTime month;
  final int? budgetCents;
  final int spentCents;
  final VoidCallback onEdit;

  /// 清空全部预算回调（仅有预算时入口可见）
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // 进度与状态色：未设预算灰、<=80% 主色、80%~100% 橙、超支红
    final hasBudget = budgetCents != null && budgetCents! > 0;
    final progress = hasBudget ? spentCents / budgetCents! : 0.0;

    // 日均可用：仅当前月且有预算且未超支时有意义
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final remainingCents = hasBudget ? budgetCents! - spentCents : 0;
    // 剩余天数含今天（今天还能花）
    final remainingDays = isCurrentMonth
        ? DateTime(now.year, now.month + 1).day - now.day + 1
        : 0;
    final showDaily =
        hasBudget && isCurrentMonth && progress <= 1 && remainingDays > 0;
    final dailyCents = showDaily ? (remainingCents / remainingDays).round() : 0;

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
              // 右上操作区靠右（年月信息由页面顶部选择器承担，不再重复）
              const Spacer(),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasBudget
                            ? Icons.edit_outlined
                            : Icons.add_circle_outline,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasBudget ? '修改' : '设置',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 清空入口仅有预算时出现：竖线与"修改"分组，红色字提示
              // 这是破坏性操作
              if (hasBudget) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 1,
                    height: 14,
                    color: AppColors.onHeader(0.35),
                  ),
                ),
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.expense,
                      ),
                    ),
                  ),
                ),
              ],
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
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onHeader(0.85),
                  ),
                ),
                const Spacer(),
                Text(
                  progress > 1
                      ? '已超支 ¥${MoneyUtil.centsToYuanGroupedTrimmed(spentCents - budgetCents!)}'
                      : '剩余 ¥${MoneyUtil.centsToYuanGroupedTrimmed(budgetCents! - spentCents)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: progress > 1
                        ? const Color(0xFFFFD6D0)
                        : Colors.white,
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

/// 预算编辑弹层（总预算与分类预算共用）：标题 + 金额输入 + 保存。
/// 提交时 pop 输入文本；清除不走本弹层的按钮——分类预算弹层
/// 退格删空金额后保存即清除（调用方按空字符串处理）。
class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({
    required this.title,
    required this.initialText,
  });

  final String title;
  final String initialText;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

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
        bottom:
            MediaQuery.of(context).viewInsets.bottom + AppDimens.pagePadding,
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
              const Text(
                '¥',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  maxLength: 12,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
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
        ],
      ),
    );
  }
}
