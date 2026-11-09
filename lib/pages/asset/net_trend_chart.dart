import 'dart:math' show max, min;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';

import '../../data/repositories/asset_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import 'net_trend_data.dart';

/// 净值走势图：卡片与全屏页共用同一套绘制与样式。
/// [panWindow] 为 null 时整段铺满、不挂任何手势（卡片，避免抢页面上下滚动）；
/// 传点数（如 90）时按单指横滑平移可视窗口（全屏页），窗口内只渲染这些点，
/// 不会把上百上千个点一次性画出来。
class NetTrendChart extends StatefulWidget {
  const NetTrendChart({
    super.key,
    required this.range,
    required this.history,
    required this.currentNetCents,
    required this.masked,
    this.panWindow,
  });

  final NetTrendRange range;
  final List<NetValuePoint> history;
  final int currentNetCents;
  final bool masked;
  final int? panWindow;

  @override
  State<NetTrendChart> createState() => _NetTrendChartState();
}

class _NetTrendChartState extends State<NetTrendChart>
    with SingleTickerProviderStateMixin {
  /// 窗口起点（单位=点，可为小数）：横滑按像素连续移动，不再整点跳动
  double? _offsetExact;

  /// 抬手惯性：按抬手速度衰减滑行，手感接近原生图表
  late final AnimationController _fling = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..addListener(_onFlingTick);
  double _flingStart = 0;
  double _flingDelta = 0;

  /// 当前窗口的点间距（像素）与可平移上限，拖动/惯性共用
  double _pointPx = 1;
  int _maxOffset = 0;

  /// 全屏页点击选中的点（全局下标），null 表示没选中
  int? _selected;

  /// 按下位置与累计位移，用于区分"点击看详情"和"拖动平移"
  double _downX = 0;
  double _moved = 0;
  VelocityTracker? _velocity;

  // 聚合结果与纵轴范围缓存：拖动每帧都会重建，但数据没变时不该重算
  List<NetValuePoint>? _cachedPoints;
  List<NetValuePoint>? _cachedHistory;
  int _cachedEnd = -1;
  NetTrendRange? _cachedRange;
  bool? _cachedFullHistory;
  ({double minY, double maxY, double interval})? _cachedY;

  @override
  void dispose() {
    _fling.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NetTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切档回到最新窗口，避免旧位置落在新档数据上只露一截
    if (oldWidget.range != widget.range) {
      _fling.stop();
      _offsetExact = null;
      _selected = null;
    }
  }

  void _onFlingTick() {
    if (!mounted) return;
    setState(() {
      _offsetExact =
          _flingStart + _flingDelta * Curves.decelerate.transform(_fling.value);
    });
  }

  /// 抬手惯性：手指速度越快滑得越远，撞到两端自然停住
  void _startFling(double velocityX) {
    if (_maxOffset <= 0) return;
    final from = _offsetExact ?? _maxOffset.toDouble();
    // 手指左滑（vx<0）看更新：位移取反；0.25s 作为等效滑行时长
    final to = (from - velocityX * 0.25 / _pointPx).clamp(
      0.0,
      _maxOffset.toDouble(),
    );
    if (velocityX.abs() < 40 || (to - from).abs() < 0.5) return;
    _flingStart = from;
    _flingDelta = to - from;
    _fling
      ..stop()
      ..value = 0
      ..forward();
  }

  /// 聚合点与纵轴范围的缓存：只有历史/末点/档位变化才重算
  List<NetValuePoint> _pointsFor(bool fullHistory) {
    final cached = _cachedPoints;
    if (cached != null &&
        _cachedHistory == widget.history &&
        _cachedEnd == widget.currentNetCents &&
        _cachedRange == widget.range &&
        _cachedFullHistory == fullHistory) {
      return cached;
    }
    final points = netTrendPoints(
      range: widget.range,
      history: widget.history,
      currentNetCents: widget.currentNetCents,
      // 全屏页每个档位都取全部历史，靠窗口横滑往回看更早的数据；
      // 卡片仍用截断的短窗口铺满
      fullHistory: fullHistory,
    );
    _cachedPoints = points;
    _cachedHistory = widget.history;
    _cachedEnd = widget.currentNetCents;
    _cachedRange = widget.range;
    _cachedFullHistory = fullHistory;
    _cachedY = points.isEmpty ? null : netTrendYRange(points);
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final panWindow = widget.panWindow;
    final fullHistory = panWindow != null;
    final points = _pointsFor(fullHistory);
    final y = _cachedY;
    if (points.isEmpty || y == null) {
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

    // 可视窗口：全屏页每档只铺 panWindow 个点，横滑查看更早的历史；
    // 历史不足一个窗口时整段铺满，此时没有可平移的余量
    final windowSize = (panWindow != null && points.length > panWindow)
        ? panWindow
        : points.length;
    final maxOffset = points.length - windowSize;
    _maxOffset = maxOffset;
    final startExact = (_offsetExact ?? maxOffset.toDouble()).clamp(
      0.0,
      maxOffset.toDouble(),
    );
    final startIdx = startExact.floor();
    // 多画窗口右侧一个点：窗口按小数平移时右边缘不会露出空白
    final drawEnd = min(points.length - 1, startIdx + windowSize);
    final lastX = (windowSize - 1).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 绘图区几何：左轴隐藏时不占宽度，底部横轴固定占 22；
        // fl_chart 把首末点贴住绘图区两端，所以点间距是 plotWidth/(点数-1)
        final leftPad = widget.masked ? 0.0 : 38.0;
        final plotWidth = max(1.0, constraints.maxWidth - leftPad);
        final plotHeight = max(1.0, constraints.maxHeight - 22);
        final pointPx = windowSize <= 1
            ? plotWidth
            : plotWidth / (windowSize - 1);
        _pointPx = pointPx;

        // 横轴刻度目标数：全屏按可用宽度自适应 10~12 个（每个标签约
        // 占 80dp 宽），卡片固定 6 个，避免挤成一片
        final labelTarget = fullHistory
            ? (plotWidth / 80).floor().clamp(10, 12)
            : 6;
        final labelStep = max(1, (windowSize / labelTarget).ceil());
        // 圆点按实际点间距显示：≥6dp 就画，更密时才隐藏，避免糊成粗线
        final showDots = windowSize <= 1 || pointPx >= 6;

        // 数据点全部绘制：不再对日/全部档抽稀，圆点是否显示交给 showDots
        // 按点间距统一判定
        final spots = <FlSpot>[
          for (var i = startIdx; i <= drawEnd; i++)
            FlSpot((i - startExact).toDouble(), points[i].$2.toDouble()),
        ];

        // 横轴刻度去重：首点 + 末点 + 每 labelStep 个为候选，但相邻两个
        // 候选若标签文本相同（如同一年内多个月都显示"2026"），只保留前者，
        // 避免横轴出现重复年份
        final candidates = <int>{startIdx, drawEnd};
        for (var i = startIdx + labelStep; i < drawEnd; i += labelStep) {
          candidates.add(i);
        }
        final sortedCandidates = candidates.toList()..sort();
        final shownIndices = <int>{};
        String? lastLabel;
        for (final idx in sortedCandidates) {
          final label = netTrendDateLabel(
            widget.range,
            points[idx].$1,
            windowSize,
          );
          if (label != lastLabel) {
            shownIndices.add(idx);
            lastLabel = label;
          }
        }

        final chartData = LineChartData(
          minY: y.minY,
          maxY: y.maxY,
          // 单点时垫出 x 轴左右各一格：孤点居中，也避免 minX==maxX 除零
          minX: windowSize == 1 ? -1.0 : 0,
          maxX: windowSize == 1 ? 1.0 : lastX,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            // 左轴自动整刻度给绝对水位参照；模糊模式下隐藏数值，
            // 防止刻度泄露具体资产规模
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: !widget.masked,
                reservedSize: 38,
                interval: y.interval,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    netTrendAxisLabel(value),
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
                  // x 是相对窗口起点的小数偏移，换回全局下标再取日期
                  final idx = (startExact + value).round();
                  if (!shownIndices.contains(idx)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      netTrendDateLabel(
                        widget.range,
                        points[idx].$1,
                        windowSize,
                      ),
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
          // 内置提示气泡带指示竖线，统一关掉，改用下方自绘的三角气泡
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 2,
              color: AppColors.primary,
              // 实心小圆点标出数据点位置，提示曲线可按住查看金额
              dotData: FlDotData(
                show: showDots,
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
        );

        // 1ms 等价于关掉插值动画：拖动时每帧数据都在变，默认 150ms 的
        // 隐式动画会一直被打断又追赶，手感像"慢半拍、粘手"
        final chart = LineChart(
          chartData,
          duration: const Duration(milliseconds: 1),
        );
        // 卡片与全屏页都挂监听：全屏页横滑平移窗口，卡片只处理点按。
        // Listener 不参与手势竞技场，不会抢页面的上下滚动

        // 选中点的像素位置，供高亮圆点/气泡/三角对齐到曲线上
        final selIndex =
            (_selected != null &&
                _selected! >= startIdx &&
                _selected! <= drawEnd)
            ? _selected
            : null;
        final selX = selIndex == null
            ? 0.0
            : leftPad + (selIndex - startExact) * pointPx;
        final selY = selIndex == null
            ? 0.0
            : plotHeight -
                  (points[selIndex].$2 - y.minY) /
                      (y.maxY - y.minY) *
                      plotHeight;

        // 气泡：先按文本量出宽度，再以选中点居中；贴边时整体挪回可见范围，
        // 三角尖单独在气泡内平移，保证始终指着选中点
        const pillH = 24.0;
        const triW = 10.0;
        const triH = 5.0;
        const gap = 7.0;
        final pillText = selIndex == null ? '' : _pillText(points[selIndex]);
        final pillW = selIndex == null ? 0.0 : _pillWidth(pillText);
        final pillLeft = (selX - pillW / 2)
            .clamp(4.0, max(4.0, constraints.maxWidth - pillW - 4))
            .toDouble();
        // 没用选中点时 pillW 为 0，上限会小于下限导致 clamp 抛参数错误，
        // 这里用 max 保证区间始终合法（此时三角也不渲染）
        final triLeft = (selX - triW / 2)
            .clamp(pillLeft + 8, max(pillLeft + 8, pillLeft + pillW - triW - 8))
            .toDouble();
        // 顶部放不下就改放点下方，三角相应翻转朝上
        final pillAbove = selY >= pillH + gap + triH;
        final pillTop = pillAbove
            ? selY - gap - triH - pillH
            : selY + gap + triH;
        final triTop = pillAbove ? selY - gap - triH : selY + gap;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            _fling.stop();
            _velocity = VelocityTracker.withKind(event.kind)
              ..addPosition(event.timeStamp, event.position);
            _moved = 0;
            _downX = event.localPosition.dx;
          },
          onPointerMove: (event) {
            _moved += event.delta.dx.abs() + event.delta.dy.abs();
            _velocity?.addPosition(event.timeStamp, event.position);
            if (_moved < 6) return;
            // 一旦拖动就取消选中，避免气泡跟着窗口漂移
            if (_selected != null) setState(() => _selected = null);
            if (_maxOffset <= 0) return;
            // 像素级累加：直接按"点间距"换算，手指走多少窗口走多少
            final next =
                ((_offsetExact ?? _maxOffset.toDouble()) -
                        event.delta.dx / _pointPx)
                    .clamp(0.0, _maxOffset.toDouble());
            if (next != _offsetExact) {
              setState(() => _offsetExact = next);
            }
          },
          onPointerCancel: (_) => _velocity = null,
          // 抬起：拖动过就按速度惯性滑行；没怎么动才当作点按看详情
          onPointerUp: (_) {
            if (_moved >= 10) {
              _startFling(_velocity?.getVelocity().pixelsPerSecond.dx ?? 0);
              return;
            }
            final idx = (startExact + (_downX - leftPad) / pointPx)
                .round()
                .clamp(startIdx, drawEnd);
            setState(() => _selected = _selected == idx ? null : idx);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              chart,
              if (selIndex != null) ...[
                // 高亮圆点：压在曲线数据点上，比普通圆点更醒目
                Positioned(
                  left: selX - 4.5,
                  top: selY - 4.5,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
                // 三角指示：尖对准选中点，贴在气泡朝点的那一侧
                Positioned(
                  left: triLeft,
                  top: triTop,
                  child: CustomPaint(
                    size: const Size(triW, triH),
                    painter: _PointTrianglePainter(up: !pillAbove),
                  ),
                ),
                // 气泡：日期 + 当日净值
                Positioned(
                  left: pillLeft,
                  top: pillTop,
                  child: Container(
                    width: pillW,
                    height: pillH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pillText,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 气泡文案：日期 + 当日净值（模糊模式下金额打码）
  String _pillText(NetValuePoint point) => widget.masked
      ? '${point.$1} · ¥ ****'
      : '${point.$1} · ¥${MoneyUtil.centsToYuanGroupedTrimmed(point.$2)}';

  /// 气泡宽度：用 TextPainter 按实际字号量文本，再加左右内边距，
  /// 三角才能精确落在气泡内部
  double _pillWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 11)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width + 20;
  }
}

/// 气泡下方（或上方）的小三角：朝下指选中点，气泡放到点下方时朝上
class _PointTrianglePainter extends CustomPainter {
  const _PointTrianglePainter({required this.up});

  /// true = 尖朝上（气泡在点下方时使用）
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.textPrimary;
    final path = Path();
    if (up) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointTrianglePainter oldDelegate) =>
      oldDelegate.up != up;
}

/// 档位切换：文字胶囊，选中高亮；卡片与全屏页共用
class NetTrendRangeSwitch extends StatelessWidget {
  const NetTrendRangeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final NetTrendRange value;
  final ValueChanged<NetTrendRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in NetTrendRange.values)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(r),
            child: Padding(
              padding: EdgeInsets.only(
                left: r == NetTrendRange.values.first ? 0 : 14,
              ),
              child: Text(
                netTrendRangeLabel(r),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: value == r ? FontWeight.w600 : FontWeight.w400,
                  color: value == r
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
