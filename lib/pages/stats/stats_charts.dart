import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// 柱状图卡片：年范围 12 月柱 + 顶部金额标注；月范围当月每日柱
/// （日柱密集不标金额，日期标签每 2 天显示一次）。
/// [prevBills]（去年同期）画成灰色背景柱辅助同比对比
class StatsRangeBarChart extends StatelessWidget {
  const StatsRangeBarChart({
    super.key,
    required this.period,
    required this.anchor,
    required this.bills,
    required this.color,
    this.prevBills = const [],
  });

  final HomePeriod period;

  /// 年模式取该年；月模式取该月
  final DateTime anchor;
  final List<Bill> bills;
  final List<Bill> prevBills;
  final Color color;

  /// 金额标注：1.4K / 800 等短格式
  static String _fmtShort(int cents) {
    final yuan = cents / 100;
    if (yuan >= 10000) return '${(yuan / 10000).toStringAsFixed(1)}万';
    if (yuan >= 1000) return '${(yuan / 1000).toStringAsFixed(1)}K';
    return yuan.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    List<int> bars;
    List<int> prevBars;
    List<String> labels;
    bool showValues;
    if (period == HomePeriod.year) {
      bars = List<int>.filled(12, 0);
      for (final b in bills) {
        if (b.date.year == anchor.year) bars[b.date.month - 1] += b.amountCents;
      }
      prevBars = List<int>.filled(12, 0);
      for (final b in prevBills) {
        if (b.date.year == anchor.year - 1) {
          prevBars[b.date.month - 1] += b.amountCents;
        }
      }
      labels = [for (var i = 1; i <= 12; i++) '$i月'];
      showValues = true;
    } else {
      final days = DateTime(anchor.year, anchor.month + 1, 0).day;
      bars = List<int>.filled(days, 0);
      for (final b in bills) {
        if (b.date.year == anchor.year && b.date.month == anchor.month) {
          bars[b.date.day - 1] += b.amountCents;
        }
      }
      prevBars = List<int>.filled(days, 0);
      for (final b in prevBills) {
        if (b.date.year == anchor.year - 1 && b.date.month == anchor.month) {
          prevBars[b.date.day - 1] += b.amountCents;
        }
      }
      // 每 2 天显示一次日期标签（2、4、6…），否则挤成一团
      labels = [for (var i = 1; i <= days; i++) i % 2 == 0 ? '$i' : ''];
      showValues = false;
    }
    // 高度比例基于两年数据的共同最大值，保证灰柱与彩柱同一比例尺
    final maxCents = math.max(
      bars.fold(0, math.max),
      prevBars.fold(0, math.max),
    );
    // 去年同期无任何数据时跳过灰柱与图例（去年还没开始记账的场景）
    final hasPrev = prevBars.any((c) => c > 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        AppDimens.gapSm,
        AppDimens.pagePadding,
        0,
      ),
      child: SectionCard(
        child: SizedBox(
          height: 170,
          child: CustomPaint(
            size: const Size(double.infinity, 170),
            painter: StatsBarChartPainter(
              bars: bars,
              labels: labels,
              maxCents: maxCents,
              color: color,
              labelFmt: _fmtShort,
              showValues: showValues,
              prevBars: hasPrev ? prevBars : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// 柱状图绘制：柱体 + 顶部金额（年模式）+ 底部标签（空串不画）；
/// [prevBars]（去年同期）以浅灰背景柱先画一层，今年彩柱叠于其前
class StatsBarChartPainter extends CustomPainter {
  StatsBarChartPainter({
    required this.bars,
    required this.labels,
    required this.maxCents,
    required this.color,
    required this.labelFmt,
    required this.showValues,
    this.prevBars,
  });

  final List<int> bars;

  /// 去年同期柱（null = 无对比数据，不画灰柱与图例）
  final List<int>? prevBars;
  final List<String> labels;
  final int maxCents;
  final Color color;
  final String Function(int cents) labelFmt;
  final bool showValues;

  @override
  void paint(Canvas canvas, Size size) {
    const chartTop = 30.0; // 顶部金额标注留白
    const labelHeight = 18.0; // 底部标签高度
    final chartHeight = size.height - chartTop - labelHeight;
    final slot = size.width / bars.length;
    final barWidth = slot * 0.5;

    // 灰色背景柱（去年同期）：无对比数据时跳过
    final hasPrev = prevBars != null && prevBars!.any((c) => c > 0);
    if (hasPrev) {
      final prevPaint = Paint()
        ..color = AppColors.textSecondary.withValues(alpha: 0.25);
      for (var i = 0; i < prevBars!.length; i++) {
        final cents = prevBars![i];
        if (cents == 0 || maxCents == 0) continue;
        final cx = slot * i + slot / 2;
        final h = chartHeight * cents / maxCents;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              cx - barWidth / 2,
              chartTop + chartHeight - h,
              barWidth,
              h,
            ),
            const Radius.circular(3),
          ),
          prevPaint,
        );
      }
      // 图例：右上角灰方块 + "去年同期"
      _legend(canvas, size);
    }

    final paint = Paint()..color = color;
    for (var i = 0; i < bars.length; i++) {
      final cents = bars[i];
      final cx = slot * i + slot / 2;
      final h = maxCents == 0 || cents == 0
          ? 0.0
          : chartHeight * cents / maxCents;
      // 柱体（无数据不画柱，仅画标签）
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              cx - barWidth / 2,
              chartTop + chartHeight - h,
              barWidth,
              h,
            ),
            const Radius.circular(3),
          ),
          paint,
        );
        // 柱顶金额标注
        if (showValues) {
          _text(
            canvas,
            labelFmt(cents),
            Offset(cx, chartTop + chartHeight - h - 16),
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          );
        }
      }
      // 底部标签（空串跳过）：中心落在 labelHeight 区中央，
      // 避免文字上半截侵入柱体区域造成遮挡
      if (labels[i].isNotEmpty) {
        _text(
          canvas,
          labels[i],
          Offset(cx, chartTop + chartHeight + labelHeight / 2),
        );
      }
    }
  }

  /// 图例：右上角"灰方块 + 去年同期"
  void _legend(Canvas canvas, Size size) {
    const text = '去年同期';
    final tp = TextPainter(
      text: const TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const swatch = 8.0;
    const gap = 4.0;
    const margin = 4.0;
    // 右对齐：文字右缘贴卡片内边距，方块在文字左侧
    final textX = size.width - margin - tp.width;
    final cy = margin + tp.height / 2;
    tp.paint(canvas, Offset(textX, margin));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(textX - gap - swatch, cy - swatch / 2, swatch, swatch),
        const Radius.circular(2),
      ),
      Paint()..color = AppColors.textSecondary.withValues(alpha: 0.25),
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center, {
    double fontSize = 10,
    Color color = AppColors.textSecondary,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(StatsBarChartPainter oldDelegate) =>
      oldDelegate.bars != bars ||
      oldDelegate.prevBars != prevBars ||
      oldDelegate.maxCents != maxCents ||
      oldDelegate.color != color;
}
