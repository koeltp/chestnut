import 'dart:math' as math;

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
    return SafeArea(
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
        _PieChartCard(
          summaries: summaries,
          total: total,
          type: provider.type,
          period: period,
        ),
        const SizedBox(height: AppDimens.gapSection),
        const _TrendCard(),
        const SizedBox(height: AppDimens.gapSection),
        _RankingCard(summaries: summaries, total: total),
      ],
    );
  }
}

/// 分类占比环形图卡片（支持手指拖动旋转，钱迹式）
class _PieChartCard extends StatefulWidget {
  const _PieChartCard({
    required this.summaries,
    required this.total,
    required this.type,
    required this.period,
  });

  final List<CategorySummary> summaries;
  final int total;
  final BillType type;
  final HomePeriod period;

  @override
  State<_PieChartCard> createState() => _PieChartCardState();
}

class _PieChartCardState extends State<_PieChartCard> {
  /// 饼图起始角（度）：跟随手指拖动旋转（fl_chart 默认 0 = 3 点钟方向顺时针）
  double _startAngle = 0;

  /// 上一次手指相对饼图中心的角度（度）
  double? _lastAngle;

  /// 手指相对饼图中心的角度：0 为 3 点钟方向，顺时针为正（与 fl_chart 一致）
  double _angleOf(Offset local) {
    final size = context.size!;
    final v = local - Offset(size.width / 2, size.height / 2);
    return math.atan2(v.dy, v.dx) * 180 / math.pi;
  }

  void _onPanStart(DragStartDetails d) =>
      _lastAngle = _angleOf(d.localPosition);

  void _onPanUpdate(DragUpdateDetails d) {
    if (_lastAngle == null) return;
    final a = _angleOf(d.localPosition);
    var delta = a - _lastAngle!;
    // 归一化到 (-180, 180]，防止跨越 ±180 界时突跳一整圈
    delta =
        math.atan2(
          math.sin(delta * math.pi / 180),
          math.cos(delta * math.pi / 180),
        ) *
        180 /
        math.pi;
    setState(() => _startAngle += delta);
    _lastAngle = a;
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = widget.type == BillType.expense
        ? AppColors.expense
        : AppColors.income;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.type.label}分类占比',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          if (widget.total == 0)
            SizedBox(
              height: 180,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.donut_large_outlined,
                      size: 48,
                      color: AppColors.textSecondary.withValues(alpha: 0.45),
                    ),
                    const SizedBox(height: AppDimens.gapSm),
                    Text(
                      // 空态文案随查看模式变化：本月 / 今年 / 全部
                      '${switch (widget.period) {
                        HomePeriod.month => '本月',
                        HomePeriod.year => '今年',
                        HomePeriod.all => '',
                      }}暂无${widget.type.label}记录',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  // 标签略超出饼图区域时允许画进卡片内边距，避免文字被裁
                  clipBehavior: Clip.none,
                  children: [
                    PieChart(
                      PieChartData(
                        startDegreeOffset: _startAngle,
                        sections: widget.summaries.map((s) {
                          return PieChartSectionData(
                            value: s.totalCents.toDouble(),
                            color: Color(s.colorValue),
                            radius: 40,
                            showTitle: false,
                          );
                        }).toList(),
                        centerSpaceRadius: 52,
                        sectionsSpace: 2,
                        pieTouchData: PieTouchData(enabled: false),
                      ),
                    ),
                    // 外部标签：引导线 + "名称 百分比"，小扇区也显示
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PieLabelPainter(
                          startAngle: _startAngle,
                          items: [
                            for (final s in widget.summaries)
                              if (s.totalCents > 0)
                                (
                                  s.name,
                                  Color(s.colorValue),
                                  s.totalCents / widget.total,
                                ),
                          ],
                        ),
                      ),
                    ),
                    // 环心汇总：总金额
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.type.label}合计',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '¥${MoneyUtil.centsToYuanGroupedTrimmed(widget.total)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 饼图外部标签绘制：引导线 + "名称 百分比"，文字颜色与扇区一致。
/// 小于 2% 的小扇区也显示；同一侧标签纵向重叠时自动下移错开。
class _PieLabelPainter extends CustomPainter {
  _PieLabelPainter({required this.startAngle, required this.items});

  /// 饼图起始角（度）：与 PieChartData.startAngle 保持一致，随旋转更新
  final double startAngle;

  /// (名称, 颜色, 占比)，顺序与 PieChart 扇区一致
  final List<(String, Color, double)> items;

  @override
  void paint(Canvas canvas, Size size) {
    const rOut = 96.0; // 引导线起点：扇区外缘（52+40）+ 4
    const lineLen = 10.0;
    const gap = 3.0;
    final center = Offset(size.width / 2, size.height / 2);
    final rightRects = <Rect>[];
    final leftRects = <Rect>[];

    var angle = startAngle;
    for (final (name, color, percent) in items) {
      final sweep = percent * 360;
      final mid = (angle + sweep / 2) * math.pi / 180;
      angle += sweep;

      final dir = Offset(math.cos(mid), math.sin(mid));
      final p1 = center + dir * rOut;
      final p2 = center + dir * (rOut + lineLen);
      // 右半圆标签向右延伸，左半圆向左
      final toRight = math.cos(mid) >= 0;

      final tp = TextPainter(
        text: TextSpan(
          text: '$name ${(percent * 100).toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 10.5, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // 文字锚点：引导线末端外侧，垂直居中；与同侧已放置标签交叠时下移错开
      var labelLeft = toRight ? p2.dx + gap : p2.dx - gap - tp.width;
      var labelTop = p2.dy - tp.height / 2;
      final placed = toRight ? rightRects : leftRects;
      for (final r in placed) {
        if (labelTop < r.bottom + 2 && labelTop + tp.height > r.top - 2) {
          labelTop = r.bottom + 2;
        }
      }
      placed.add(Rect.fromLTWH(labelLeft, labelTop, tp.width, tp.height));

      // 引导线：径向段 p1→p2 + 连接段 p2→文字边缘（错开后为斜线）
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 1;
      final elbow = Offset(
        toRight ? labelLeft - gap : labelLeft + tp.width + gap,
        labelTop + tp.height / 2,
      );
      canvas.drawLine(p1, p2, linePaint);
      canvas.drawLine(p2, elbow, linePaint);
      tp.paint(canvas, Offset(labelLeft, labelTop));
    }
  }

  @override
  bool shouldRepaint(covariant _PieLabelPainter old) =>
      old.items != items || old.startAngle != startAngle;
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
