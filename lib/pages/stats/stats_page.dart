import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/summaries.dart';
import '../../providers/stats_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/month_switcher.dart';
import '../../widgets/pie_chart_card.dart';
import '../../widgets/section_card.dart';
import '../home/period_picker_dialog.dart';

/// 统计页：分类占比环形图 + 近 6 月收支趋势 + 分类排行
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  /// 打开"显示方式"弹窗并应用选择结果（模式 + 基准月份），与首页同款
  Future<void> _pickPeriod(BuildContext context) async {
    final provider = context.read<StatsProvider>();
    final result = await PeriodPickerDialog.show(
      context,
      initialMode: provider.period,
      initialMonth: provider.selectedMonth,
    );
    if (result == null || !context.mounted) return;
    final (mode, month) = result;
    if (month != null) provider.changeMonth(month);
    provider.changePeriod(mode);
  }

  @override
  Widget build(BuildContext context) {
    // watch：模式/月份/类型切换（notifyListeners）时重建，StreamBuilder 随之换流
    final provider = context.watch<StatsProvider>();
    // 自带 Scaffold：本页除底部 Tab 外还会被分类管理页独立 push，
    // 内部的 InkWell 类组件（月份切换/分段器）需要 Material 祖先才能渲染
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部：显示方式 + 收支类型切换
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pagePadding,
                AppDimens.gapSm,
                AppDimens.pagePadding,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MonthSwitcher(
                    month: provider.selectedMonth,
                    onChanged: provider.changeMonth,
                    foregroundColor: AppColors.textPrimary,
                    // 弹窗内已可选年月，左右箭头不再需要
                    showArrows: false,
                    text: switch (provider.period) {
                      HomePeriod.month => null,
                      HomePeriod.year => '${provider.selectedMonth.year}年',
                      HomePeriod.all => '全部',
                    },
                    onTapText: () => _pickPeriod(context),
                  ),
                  AppSegmented<BillType>(
                    options: [for (final t in BillType.values) (t, t.label)],
                    colors: const [AppColors.expense, AppColors.income],
                    selected: provider.type,
                    onChanged: provider.changeType,
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<CategorySummary>>(
                stream: provider.categorySummaryStream(
                  provider.period,
                  provider.selectedMonth,
                  provider.type,
                ),
                builder: (context, snapshot) {
                  final summaries = snapshot.data ?? const <CategorySummary>[];
                  return _StatsBody(
                    provider: provider,
                    summaries: summaries,
                    period: provider.period,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统计主体：饼图 / 趋势图 / 分类排行
class _StatsBody extends StatelessWidget {
  const _StatsBody({
    required this.provider,
    required this.summaries,
    required this.period,
  });

  final StatsProvider provider;
  final List<CategorySummary> summaries;
  final HomePeriod period;

  @override
  Widget build(BuildContext context) {
    final total = summaries.fold(0, (s, e) => s + e.totalCents);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        AppDimens.gapSection,
        AppDimens.pagePadding,
        24,
      ),
      children: [
        PieChartCard(
          title: '${provider.type.label}分类占比',
          items: [
            for (final s in summaries) (s.name, s.totalCents),
          ],
          centerLabel: '${provider.type.label}合计',
          centerValue: MoneyUtil.centsToYuanGroupedTrimmed(total),
          centerValueColor:
              provider.type == BillType.expense
                  ? AppColors.expense
                  : AppColors.income,
          emptyText:
              '${switch (period) {
                HomePeriod.month => '本月',
                HomePeriod.year => '今年',
                HomePeriod.all => '',
              }}暂无${provider.type.label}记录',
        ),
        const SizedBox(height: AppDimens.gapSection),
        const _TrendCard(),
        const SizedBox(height: AppDimens.gapSection),
        _RankingCard(summaries: summaries, total: total),
      ],
    );
  }
}

/// 近 6 个月收支趋势卡片（双折线）
class _TrendCard extends StatelessWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '近6个月趋势',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _legend(AppColors.expense, '支出'),
              const SizedBox(width: 10),
              _legend(AppColors.income, '收入'),
            ],
          ),
          const SizedBox(height: AppDimens.gapMd),
          StreamBuilder<List<MonthlyTrend>>(
            stream: context.read<StatsProvider>().trendStream(),
            builder: (context, snapshot) {
              final trends = snapshot.data ?? const <MonthlyTrend>[];
              if (trends.isEmpty) {
                return const SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      '暂无数据',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }
              return SizedBox(height: 180, child: _buildLineChart(trends));
            },
          ),
        ],
      ),
    );
  }

  /// 图例项
  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 折线图：金额以"元"为单位展示，保留两位小数
  Widget _buildLineChart(List<MonthlyTrend> trends) {
    final expenseSpots = <FlSpot>[];
    final incomeSpots = <FlSpot>[];
    for (var i = 0; i < trends.length; i++) {
      expenseSpots.add(FlSpot(i.toDouble(), trends[i].expenseCents / 100));
      incomeSpots.add(FlSpot(i.toDouble(), trends[i].incomeCents / 100));
    }
    // 纵轴最大值：取两线峰值向上取整到整千
    final maxY =
        trends.fold(0, (m, t) {
          final maxOfTrend = t.expenseCents > t.incomeCents
              ? t.expenseCents
              : t.incomeCents;
          return maxOfTrend > m ? maxOfTrend : m;
        }) /
        100;
    final axisMax = (maxY <= 0 ? 100 : (maxY / 100).ceil() * 100).toDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (trends.length - 1).toDouble(),
        minY: 0,
        maxY: axisMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: axisMax / 4,
          getDrawingHorizontalLine: (v) =>
              const FlLine(color: AppColors.divider, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= trends.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    trends[index].label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: expenseSpots,
            isCurved: true,
            color: AppColors.expense,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.expense.withValues(alpha: 0.08),
            ),
          ),
          LineChartBarData(
            spots: incomeSpots,
            isCurved: true,
            color: AppColors.income,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.income.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类排行卡片：金额降序，附占比进度条
class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.summaries, required this.total});

  final List<CategorySummary> summaries;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '分类排行',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.gapSm),
          if (summaries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无数据',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            ...summaries.map((s) {
              final color = Color(s.colorValue);
              final percent = total > 0 ? s.totalCents / total : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDimens.gapSm),
                child: Row(
                  children: [
                    // 排行图标底：与全应用分类图标统一规格（40）
                    Container(
                      width: AppDimens.iconTile,
                      height: AppDimens.iconTile,
                      decoration: BoxDecoration(
                        color: AppColors.tint(color),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        // ignore: non_const_argument_for_const_parameter
                        IconData(s.iconCode, fontFamily: 'MaterialIcons'),
                        color: color,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: AppDimens.gapMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                s.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '¥${MoneyUtil.centsToYuanTrimmed(s.totalCents)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: AppDimens.gapSm),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '${(percent * 100).toStringAsFixed(1)}%',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 占比进度条
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: percent,
                              minHeight: 4,
                              backgroundColor: AppColors.divider,
                              valueColor: AlwaysStoppedAnimation(color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
