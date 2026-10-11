import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/asset_repository.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/pie_chart_card.dart';
import '../../widgets/section_card.dart';

/// 净值曲线卡：历史快照聚合点 + 今天实时净值点（纯资产快照口径）。
/// 点数不足 2 时的空态提示用户更新市值积累曲线。
class NetTrendCard extends StatelessWidget {
  const NetTrendCard({super.key, required this.currentNetCents});

  final int currentNetCents;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return StreamBuilder<List<NetValuePoint>>(
      stream: context.read<AssetProvider>().netHistoryStream(),
      builder: (context, snapshot) {
        final history = snapshot.data ?? const <NetValuePoint>[];
        // 末点 = 今天实时净值（不含借条的快照口径）：与历史点口径一致
        final points = [
          ...history,
          (
            DateFormat('yyyy-MM-dd').format(DateTime.now()),
            currentNetCents,
          ),
        ];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '净值走势',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '资产快照口径',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.gapMd),
              SizedBox(height: 180, child: _chart(points, masked)),
            ],
          ),
        );
      },
    );
  }

  /// 单点无法画趋势：给一个引导性空态而不是孤零零一个点
  Widget _chart(List<NetValuePoint> points, bool masked) {
    if (points.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 44,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: AppDimens.gapSm),
            const Text(
              '更新市值后，这里会记录净值走势',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].$2.toDouble()),
    ];
    // 纵轴范围：上下各留 12% 呼吸空间，净值走平（min==max）时垫出可视区间
    final values = points.map((p) => p.$2).toList();
    var minY = values.reduce((a, b) => a < b ? a : b).toDouble();
    var maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    final pad = (maxY - minY) * 0.12;
    minY -= pad == 0 ? 1000 : pad;
    maxY += pad == 0 ? 1000 : pad;
    // 横轴日期抽稀：最多显示 5 个刻度
    final labelStep = (points.length / 5).ceil();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.round();
                final show =
                    idx == 0 ||
                    idx == points.length - 1 ||
                    idx % labelStep == 0;
                if (!show || idx >= points.length) {
                  return const SizedBox.shrink();
                }
                // `yyyy-MM-dd` -> `MM-dd`
                final day = points[idx].$1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    day.length >= 10 ? day.substring(5) : day,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    masked
                        ? '${points[s.x.round()].$1}\n¥ ****'
                        : '${points[s.x.round()].$1}\n'
                            '¥${MoneyUtil.centsToYuanGroupedTrimmed(s.y.round())}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2,
            color: AppColors.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.14),
                  AppColors.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 资产构成卡：未归档且计入总资产的账户按分类求和（复用统计页环形图组件）
class StructureCard extends StatelessWidget {
  const StructureCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Asset>>(
      stream: context.read<AssetProvider>().activeStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final masked = context.watch<AssetProvider>().masked;
        final assets = snapshot.data!
            .where((a) => a.kind == AssetKind.asset && a.includeInNet)
            .toList();
        // 分类名 -> 市值合计
        final totals = <String, int>{};
        for (final a in assets) {
          totals[a.category] = (totals[a.category] ?? 0) + a.valueCents;
        }
        var total = 0;
        totals.forEach((_, v) => total += v);
        final items = totals.entries.map((e) => (e.key, e.value)).toList();
        return PieChartCard(
          title: '资产构成',
          items: items,
          centerLabel: '资产合计',
          centerValue: masked ? '****' : MoneyUtil.centsToYuanGroupedTrimmed(total),
          centerValueColor: AppColors.primary,
          emptyText: '添加资产后查看构成',
        );
      },
    );
  }
}
