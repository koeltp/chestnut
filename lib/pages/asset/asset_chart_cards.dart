import 'dart:math' show ln10, log, pow;

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
/// 四档粒度切换（日/月/年/全部），点数不足 2 时的空态提示用户更新市值积累曲线。
class NetTrendCard extends StatefulWidget {
  const NetTrendCard({super.key, required this.currentNetCents});

  final int currentNetCents;

  @override
  State<NetTrendCard> createState() => _NetTrendCardState();
}

/// 走势档位：日/月/年对应时间窗口，全部按年聚合铺满历史
enum _TrendRange { day, month, year, all }

class _NetTrendCardState extends State<NetTrendCard> {
  /// 默认"日"档：首屏看最近 7 天，其余档位用户主动切换
  _TrendRange _range = _TrendRange.day;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return StreamBuilder<List<NetValuePoint>>(
      stream: context.read<AssetProvider>().netHistoryStream(),
      builder: (context, snapshot) {
        final history = snapshot.data ?? const <NetValuePoint>[];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '净值走势',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppDimens.gapSm),
              // 口径说明居左、档位切换居右，一行两用不额外占卡片高度
              Row(
                children: [
                  const Text(
                    '资产快照口径',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  _rangeSwitch(),
                ],
              ),
              const SizedBox(height: AppDimens.gapSm),
              SizedBox(height: 180, child: _chart(history, masked)),
            ],
          ),
        );
      },
    );
  }

  /// 档位切换：文字胶囊，选中高亮
  Widget _rangeSwitch() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in _TrendRange.values)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _range = r),
            child: Padding(
              padding: EdgeInsets.only(left: r == _TrendRange.values.first ? 0 : 14),
              child: Text(
                switch (r) {
                  _TrendRange.day => '日',
                  _TrendRange.month => '月',
                  _TrendRange.year => '年',
                  _TrendRange.all => '全部',
                },
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _range == r ? FontWeight.w600 : FontWeight.w400,
                  color: _range == r
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 聚合出当前档位的显示点：
  /// 日 = 最近 7 天的日级快照；月/年 = 每段（自然月/自然年）最后一条快照
  /// 取"月末/年末水位"；全部 = 每年一个点铺满历史。末点统一用今天的实时
  /// 净值兜底，任何档位曲线都画到"现在"
  List<NetValuePoint> _displayPoints(List<NetValuePoint> history) {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    // 与实时同日的历史点让位：实时值总是更新
    final fresh =
        history.where((p) => p.$1 != today).toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    final end = <NetValuePoint>[(today, widget.currentNetCents)];
    switch (_range) {
      case _TrendRange.day:
        // 含今天共 7 个自然日
        final cutoff = DateFormat(
          'yyyy-MM-dd',
        ).format(now.subtract(const Duration(days: 6)));
        return [
          ...fresh.where((p) => p.$1.compareTo(cutoff) >= 0),
          ...end,
        ];
      case _TrendRange.month:
        // 最近 12 个自然月（以当前月为末点往前数 11 个月）
        final cutoff = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime(now.year, now.month - 11, 1));
        return [
          ..._lastPerPeriod(fresh.where((p) => p.$1.compareTo(cutoff) >= 0), 7),
          ...end,
        ];
      case _TrendRange.year:
        // 最近 12 个自然年
        final cutoff = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime(now.year - 11, 1, 1));
        return [
          ..._lastPerPeriod(fresh.where((p) => p.$1.compareTo(cutoff) >= 0), 4),
          ...end,
        ];
      case _TrendRange.all:
        return [..._lastPerPeriod(fresh, 4), ...end];
    }
  }

  /// 每个时段（key = 日期前 [prefixLen] 位：yyyy-MM 或 yyyy）保留最后一条
  /// 快照；入参须已按日期升序，后到者覆盖即为段末水位
  List<NetValuePoint> _lastPerPeriod(
    Iterable<NetValuePoint> pts,
    int prefixLen,
  ) {
    final map = <String, NetValuePoint>{};
    for (final p in pts) {
      map[p.$1.substring(0, prefixLen)] = p;
    }
    final keys = map.keys.toList()..sort();
    return [for (final k in keys) map[k]!];
  }

  /// 横轴标签随档换格式：日 MM-dd / 月 yy-MM / 年 yyyy
  String _dateLabel(String date) {
    switch (_range) {
      case _TrendRange.day:
        return date.substring(5);
      case _TrendRange.month:
        return '${date.substring(2, 4)}-${date.substring(5, 7)}';
      case _TrendRange.year:
      case _TrendRange.all:
        return date.substring(0, 4);
    }
  }

  /// 纵轴金额缩写（分）：≥1 亿显示"亿"、≥1 万元显示"万"，其余按元。
  /// 1 万元 = 100 万分，除数是 1e6——刻度值已对齐整间隔，
  /// 1 位小数去尾零就能保持干净（8万 / 8.6万 / 160万）
  String _axisLabel(double cents) {
    final v = cents.abs();
    if (v >= 1e10) return '${_trim1(cents / 1e10)}亿';
    if (v >= 1e6) return '${_trim1(cents / 1e6)}万';
    return _trim1(cents / 100);
  }

  /// 保留 1 位小数、去掉尾零（12.0 -> 12）
  String _trim1(double x) =>
      x.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

  /// 把 [raw] 归整到 1/2/5×10^n 的整间隔：刻度值全是它的整数倍，
  /// 左轴才会出现整齐数字而不是 85831 这类碎值
  double _niceInterval(double raw) {
    final mag = pow(10, (log(raw) / ln10).floorToDouble()).toDouble();
    final f = raw / mag;
    final nice = f >= 5 ? 5 : (f >= 2 ? 2 : 1);
    return nice * mag;
  }

  /// 单点无法画趋势：给一个引导性空态而不是孤零零一个点
  Widget _chart(List<NetValuePoint> history, bool masked) {
    final points = _displayPoints(history);
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
    // 纵轴范围对齐到整刻度间隔：净值走平（min==max）时先垫出可视区间，
    // 再把上下界外扩到间隔整数倍——所有刻度都落在整数倍上，干净整齐
    final values = points.map((p) => p.$2).toList();
    var minY = values.reduce((a, b) => a < b ? a : b).toDouble();
    var maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    if (maxY - minY < 2000) {
      final mid = (maxY + minY) / 2;
      minY = mid - 1000;
      maxY = mid + 1000;
    }
    final interval = _niceInterval(maxY - minY);
    minY = (minY / interval).floorToDouble() * interval;
    maxY = (maxY / interval).ceilToDouble() * interval;
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
          rightTitles: const AxisTitles(),
          // 左轴自动整刻度给绝对水位参照；模糊模式下隐藏数值，
          // 防止刻度泄露具体资产规模
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: !masked,
              reservedSize: 38,
              interval: interval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  _axisLabel(value),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
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
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dateLabel(points[idx].$1),
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
            // 实心小圆点标出数据点位置，提示曲线可按住查看金额
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                    radius: 2.5,
                    color: AppColors.primary,
                    strokeWidth: 1.2,
                    strokeColor: Colors.white,
                  ),
            ),
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
