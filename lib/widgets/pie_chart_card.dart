import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'section_card.dart';

/// 环形占比图卡片（共享组件，支持手指拖动旋转，钱迹式）
///
/// 统计页（分类占比）与分类统计详情页（子分类构成）共用同一实现，
/// 保证两处环形图的视觉与交互完全一致。
/// 扇区颜色由内置多彩色板按序自动分配（循环取色），保证相邻扇区
/// 颜色差异明显；[items] 为 (名称, 金额分)，金额为 0 的项不绘制。
class PieChartCard extends StatefulWidget {
  const PieChartCard({
    super.key,
    required this.title,
    required this.items,
    required this.centerLabel,
    required this.centerValue,
    required this.centerValueColor,
    required this.emptyText,
  });

  final String title;

  /// 扇区数据：(名称, 金额分)
  final List<(String, int)> items;

  /// 内置多彩色板：相邻扇区色相拉开，循环使用
  static const List<Color> palette = [
    Color(0xFFF45B69), // 红
    Color(0xFFFF9F43), // 橙
    Color(0xFF2ECC71), // 绿
    Color(0xFF3498DB), // 蓝
    Color(0xFF9B59B6), // 紫
    Color(0xFFFDCB6E), // 黄
    Color(0xFF1ABC9C), // 青
    Color(0xFFFD79A8), // 粉
    Color(0xFFE17055), // 棕
    Color(0xFF636E72), // 灰
  ];

  /// 环心上方小字（如"支出合计"/"合计"）
  final String centerLabel;

  /// 环心金额文本（不含 ¥ 符号，由内部统一加前缀）
  final String centerValue;

  /// 环心金额颜色（支出红 / 收入绿 / 分类色）
  final Color centerValueColor;

  /// 无数据时的空态文案
  final String emptyText;

  @override
  State<PieChartCard> createState() => _PieChartCardState();
}

class _PieChartCardState extends State<PieChartCard> {
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

  void _onDragStart(DragStartDetails d) =>
      _lastAngle = _angleOf(d.localPosition);

  void _onDragUpdate(DragUpdateDetails d) {
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
    final total = widget.items.fold<int>(0, (sum, item) => sum + item.$2);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          if (total == 0)
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
                      widget.emptyText,
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
              // 水平拖动旋转：与外层列表的竖直滚动手势各管一个方向，
              // 竞技不冲突，旋转始终灵敏（pan 全向会与列表滚动抢手势）
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
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
                        sections: [
                          for (var i = 0; i < widget.items.length; i++)
                            if (widget.items[i].$2 > 0)
                              PieChartSectionData(
                                value: widget.items[i].$2.toDouble(),
                                color: PieChartCard.palette[i % 10],
                                radius: 40,
                                showTitle: false,
                              ),
                        ],
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
                            for (var i = 0; i < widget.items.length; i++)
                              if (widget.items[i].$2 > 0)
                                (
                                  widget.items[i].$1,
                                  PieChartCard.palette[i % 10],
                                  widget.items[i].$2 / total,
                                ),
                          ],
                        ),
                      ),
                    ),
                    // 环心汇总：标签 + 总金额
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.centerLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '¥${widget.centerValue}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: widget.centerValueColor,
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
