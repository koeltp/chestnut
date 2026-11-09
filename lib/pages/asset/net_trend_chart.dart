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
/// [pannable] 为 false 时窗口固定贴右端、不响应横滑（卡片，避免抢页面上下滚动）；
/// 为 true 时按单指横滑平移可视窗口（全屏页）。
/// 窗口大小由绘图区宽度反推（点间距固定 20dp），窗口内的点全部绘制、
/// 一个不抽——"放不下"只体现为窗口变窄、横滑看更早，而不是在窗口内抽点。
class NetTrendChart extends StatefulWidget {
  const NetTrendChart({
    super.key,
    required this.range,
    required this.history,
    required this.currentNetCents,
    required this.masked,
    this.pannable = false,
    this.leadingFadeColor,
  });

  final NetTrendRange range;
  final List<NetValuePoint> history;
  final int currentNetCents;
  final bool masked;
  final bool pannable;

  /// 是否在绘图区左边缘画渐隐：只在传入颜色（通常是卡片背景色）且
  /// 确实有更早数据被窗口裁掉时出现；全屏页不传，保持干净
  final Color? leadingFadeColor;

  @override
  State<NetTrendChart> createState() => _NetTrendChartState();
}

/// 数据点圆点的半径与描边：圆点可见阈值也由它们推出，不再单独写死
const double kTrendDotRadius = 2.5;
const double kTrendDotStroke = 1.2;

/// 卡片左边缘渐隐的宽度：被窗口裁掉更早数据时，用来暗示左边还有
const double kTrendFadeWidth = 16;

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

  // 聚合结果缓存：拖动每帧都会重建，但数据没变时不该重算
  List<NetValuePoint>? _cachedPoints;
  List<NetValuePoint>? _cachedHistory;
  int _cachedEnd = -1;
  NetTrendRange? _cachedRange;

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

  /// 聚合点缓存：只有历史/末点/档位变化才重算
  List<NetValuePoint> _pointsFor() {
    final cached = _cachedPoints;
    if (cached != null &&
        _cachedHistory == widget.history &&
        _cachedEnd == widget.currentNetCents &&
        _cachedRange == widget.range) {
      return cached;
    }
    final points = netTrendPoints(
      range: widget.range,
      history: widget.history,
      currentNetCents: widget.currentNetCents,
    );
    _cachedPoints = points;
    _cachedHistory = widget.history;
    _cachedEnd = widget.currentNetCents;
    _cachedRange = widget.range;
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final points = _pointsFor();
    if (points.isEmpty) {
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

    // 可视窗口大小依赖真实绘图区宽度（点间距 20dp），必须在 LayoutBuilder
    // 里算；卡片不可平移，但窗口规则与全屏完全一致，只是固定贴右端
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);

        // 左轴宽按"整体纵轴范围"里最宽的刻度文字实测：拖动时保持不变，
        // 否则轴宽随窗口变化会让绘图区宽度来回抖
        final axesY = netTrendYRange(points);
        final leftPad = widget.masked
            ? 0.0
            : _widestAxisLabelWidth(axesY, scaler) + kTrendAxisPadding;
        final plotWidth = max(1.0, constraints.maxWidth - leftPad);

        // 底部预留高与刻度槽位，都取该档最宽样本的实测尺寸
        final labelSize = netTrendTextSize(
          _labelSample(widget.range),
          textScaler: scaler,
        );
        final bottomPad = labelSize.height + kTrendAxisPadding;
        final plotHeight = max(1.0, constraints.maxHeight - bottomPad);

        // 点数由宽度反推：点间距固定 20dp，能放多少点就显示多少点。
        // 屏幕窄窗口就窄，更早的数据靠横滑平移，而不是在窗口内按比例
        // 取整抽稀——比例取整会让相邻点间隔在 1~2 倍之间跳动，忽疏忽密。
        final windowSize = netTrendWindowPoints(
          plotWidth: plotWidth,
          totalPoints: points.length,
        );
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
        final pointPx = windowSize <= 1
            ? plotWidth
            : plotWidth / (windowSize - 1);
        _pointPx = pointPx;

        // 点：窗口内全部画上，间距恒为 plotWidth/(windowSize-1) ≈ 20dp
        final spots = <FlSpot>[
          for (var idx = startIdx; idx <= drawEnd; idx++)
            FlSpot((idx - startExact).toDouble(), points[idx].$2.toDouble()),
        ];
        // 点距固定 20dp，正常都能放下圆点；极窄屏按圆点直径兜底隐藏
        final showDots =
            windowSize <= 1 || pointPx >= 2 * kTrendDotRadius + kTrendDotStroke;

        // 纵轴只按当前窗口内的点算：全屏页取全部历史后，若还按整段算，
        // 20 年跨度会把最近 36 天的波动压成一条直线。窗口最多几十个点，
        // 拖动时逐帧重算的代价可以忽略。
        final y = netTrendYRange(
          points.sublist(startIdx, min(points.length, drawEnd + 1)),
        );

        // 刻度：先算一屏写不下几个标签（按实际文本占位），写不下才抽稀。
        // 步长只能取整数个点，刻度才始终落在数据点上；从右端（最新数据）
        // 往左对齐，保证"今天"永远有标签，余量落在最左侧。
        final labelStep = netTrendLabelStep(
          windowPoints: windowSize,
          plotWidth: plotWidth,
          labelWidth: labelSize.width,
        );
        final anchorIdx = (startExact + lastX).round();

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
                reservedSize: leftPad,
                interval: y.interval,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: kTrendAxisPadding),
                  child: Text(
                    netTrendAxisLabel(value),
                    style: const TextStyle(
                      fontSize: kTrendAxisFontSize,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: bottomPad,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  // x 是相对窗口起点的小数偏移，换回全局下标再取日期
                  final idx = (startExact + value).round();
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox.shrink();
                  }
                  // 刻度从最新数据往左按整数步长对齐：拖动时 idx 连续变化
                  // 也不会漏标，且间隔始终是 step 个点
                  if ((anchorIdx - idx) % labelStep != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: kTrendAxisPadding),
                    child: Text(
                      netTrendDateLabel(
                        widget.range,
                        points[idx].$1,
                        windowSize,
                      ),
                      style: const TextStyle(
                        fontSize: kTrendAxisFontSize,
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
                      radius: kTrendDotRadius,
                      color: AppColors.primary,
                      strokeWidth: kTrendDotStroke,
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
            if (!widget.pannable || _maxOffset <= 0) return;
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
              // 卡片被窗口裁掉更早数据时，左边缘渐隐暗示"左边还有"；
              // 只盖绘图区，不盖左轴刻度，也不吃点击
              if (widget.leadingFadeColor != null && points.length > windowSize)
                Positioned(
                  left: leftPad,
                  top: 0,
                  width: kTrendFadeWidth,
                  height: plotHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            widget.leadingFadeColor!,
                            widget.leadingFadeColor!.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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

  /// 整体纵轴范围里最宽的刻度文字宽度，用于预留左轴
  double _widestAxisLabelWidth(
    ({double minY, double maxY, double interval}) y,
    TextScaler scaler,
  ) {
    final count = ((y.maxY - y.minY) / y.interval).round();
    var widest = 0.0;
    for (var i = 0; i <= count; i++) {
      final width = netTrendTextSize(
        netTrendAxisLabel(y.minY + i * y.interval),
        textScaler: scaler,
      ).width;
      if (width > widest) widest = width;
    }
    return widest;
  }

  /// 测宽样本：取该档最宽的可能标签，避免用窄样本低估占位
  String _labelSample(NetTrendRange range) => switch (range) {
    NetTrendRange.day => '12/31',
    NetTrendRange.month => '26/12',
    NetTrendRange.quarter => '26/Q4',
    NetTrendRange.year => '2026',
  };

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
              // 上下各留 8dp：四个字挤在一行时，热区比文字本身大一圈，
              // 避免相邻档位误点
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              child: Text(
                netTrendRangeLabel(r),
                style: TextStyle(
                  fontSize: 14,
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
