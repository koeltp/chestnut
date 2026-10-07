import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// 柱状图卡片：年范围 12 月柱（柱顶两行标注今年/去年）；
/// 月范围当月每日柱（标签抽稀：仅显著柱标注较大值，日期标签每 2 天显示一次）。
/// [prevBills]（去年同期）与彩柱同宽同位叠画成长短分段柱辅助同比对比
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
          // 184 = 标注区 54（今年+去年两行）+ 柱区 112 + 底部标签 18
          height: 184,
          child: CustomPaint(
            size: const Size(double.infinity, 184),
            painter: StatsBarChartPainter(
              bars: bars,
              labels: labels,
              maxCents: maxCents,
              color: color,
              labelFmt: _fmtShort,
              period: period,
              prevBars: hasPrev ? prevBars : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// 柱状图绘制：柱体 + 顶部金额（年模式）+ 底部标签（空串不画）；
/// [prevBars]（去年同期）与彩柱同宽同位叠画：长柱垫底、短柱前景，
/// 重叠段显示短柱颜色、长柱露出差值段
class StatsBarChartPainter extends CustomPainter {
  StatsBarChartPainter({
    required this.bars,
    required this.labels,
    required this.maxCents,
    required this.color,
    required this.labelFmt,
    required this.period,
    this.prevBars,
  });

  final List<int> bars;

  /// 去年同期柱（null = 无对比数据，不画灰柱与图例）
  final List<int>? prevBars;
  final List<String> labels;
  final int maxCents;
  final Color color;
  final String Function(int cents) labelFmt;

  /// 年模式两行堆叠标注；月模式单值标注（较大值）
  final HomePeriod period;

  @override
  void paint(Canvas canvas, Size size) {
    // 顶部金额标注留白：54 = 两行标注（今年红粗上行/去年灰下行，
    // 合占约 31px）+ 与右上角图例的间距，最高柱时两行不撞图例
    const chartTop = 54.0;
    const labelHeight = 18.0; // 底部标签高度
    final chartHeight = size.height - chartTop - labelHeight;
    final slot = size.width / bars.length;
    final barWidth = slot * 0.5;
    final paint = Paint()..color = color;
    // 去年同期灰：25% 透明度浅灰，与彩柱同宽同位叠画
    final prevPaint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.25);
    // 灰段垫底白：半透明灰直接叠在红上会透出红色导致两段难区分，
    // 先垫卡片白再叠灰，灰段观感与白底上的独立灰柱完全一致
    final cardPaint = Paint()..color = AppColors.card;
    // 去年同期无任何数据时跳过灰柱与图例（去年还没开始记账的场景）
    final hasPrev = prevBars != null && prevBars!.any((c) => c > 0);
    final baselineY = chartTop + chartHeight;

    // 月模式标签抽稀：31 根日柱挤在一屏，每槽仅约 12px，连续有账时
    // 相邻标签必然横向叠字。只标"显著柱"——金额达到共同最大值 35%
    // （最高柱必然入选）；间距再兜底：两根待标柱槽位差 <3 时只留高者。
    // 小柱不标数字，柱体本身仍在，高度节奏不受影响
    final monthLabeled = <int>{};
    if (period == HomePeriod.month) {
      final threshold = maxCents * 0.35;
      // 该槽位今年/去年两段中的较大值，作为显著性与冲突取舍依据
      int valueOf(int i) => math.max(bars[i], hasPrev ? prevBars![i] : 0);
      for (var i = 0; i < bars.length; i++) {
        final v = valueOf(i);
        if (v <= 0 || v < threshold) continue;
        // 与已入选柱距离过近时，矮的让给高的
        final conflict = monthLabeled
            .where((j) => (j - i).abs() < 3)
            .toList();
        if (conflict.isEmpty) {
          monthLabeled.add(i);
        } else if (v > valueOf(conflict.first)) {
          monthLabeled
            ..remove(conflict.first)
            ..add(i);
        }
      }
    }

    for (var i = 0; i < bars.length; i++) {
      final cents = bars[i];
      final prevCents = hasPrev ? prevBars![i] : 0;
      final cx = slot * i + slot / 2;
      final h = maxCents == 0 || cents == 0
          ? 0.0
          : chartHeight * cents / maxCents;
      final hPrev = maxCents == 0 || prevCents == 0
          ? 0.0
          : chartHeight * prevCents / maxCents;

      // 叠柱分段：长柱垫底先画、短柱前景后画——重叠段显示短柱颜色，
      // 长柱只露出高出的差值段；等长时红柱后画显示今年色；
      // 单边为 0 时另一根整柱独画（h<=0 的 _bar 自动跳过）
      final x = cx - barWidth / 2;
      if (hPrev > h) {
        _bar(canvas, x, baselineY - hPrev, barWidth, hPrev, prevPaint);
        _bar(canvas, x, baselineY - h, barWidth, h, paint);
      } else {
        _bar(canvas, x, baselineY - h, barWidth, h, paint);
        // 红长灰短：垫白后再叠灰，让灰段与独立灰柱同观感；
        // 等长时不垫不叠（重叠段显示今年红色）
        if (hPrev > 0 && hPrev < h) {
          _bar(canvas, x, baselineY - hPrev, barWidth, hPrev, cardPaint);
          _bar(canvas, x, baselineY - hPrev, barWidth, hPrev, prevPaint);
        }
      }

      // 柱顶金额标注：年模式今年红粗在上、去年灰字在下两行堆叠，
      // 均锚定柱总高顶部，等长值相同只标一行、单边为零也只标一行；
      // 月模式柱顶标今年/去年中较大的值（颜色跟随大的段），与上一根
      // 有标注的柱相邻时上下交错 14px，避免相邻数字横向压字
      if (period == HomePeriod.year) {
        if (h > 0 && hPrev > 0 && hPrev != h) {
          final topY = baselineY - math.max(h, hPrev);
          _text(
            canvas,
            labelFmt(cents),
            Offset(cx, topY - 24),
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          );
          _text(
            canvas,
            labelFmt(prevCents),
            Offset(cx, topY - 11),
            fontSize: 10,
          );
        } else if (h > 0) {
          _text(
            canvas,
            labelFmt(cents),
            Offset(cx, baselineY - h - 16),
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          );
        } else if (hPrev > 0) {
          _text(
            canvas,
            labelFmt(prevCents),
            Offset(cx, baselineY - hPrev - 16),
            fontSize: 10,
          );
        }
      } else if (monthLabeled.contains(i)) {
        final bool nowLarger = cents >= prevCents;
        final hMax = math.max(h, hPrev);
        _text(
          canvas,
          labelFmt(nowLarger ? cents : prevCents),
          Offset(cx, baselineY - hMax - 10),
          fontSize: 9,
          color: nowLarger ? color : AppColors.textSecondary,
          fontWeight: nowLarger ? FontWeight.w600 : FontWeight.w400,
        );
      }

      // 底部标签（空串跳过）：中心落在 labelHeight 区中央，
      // 避免文字上半截侵入柱体区域造成遮挡
      if (labels[i].isNotEmpty) {
        _text(
          canvas,
          labels[i],
          Offset(cx, baselineY + labelHeight / 2),
        );
      }
    }

    // 图例：右上角灰方块 + "去年同期"；
    // 月模式日柱只标单日较大值，图例补上去年当月合计
    if (hasPrev) {
      _legend(
        canvas,
        size,
        sumText: period == HomePeriod.year
            ? null
            : labelFmt(prevBars!.fold<int>(0, (sum, c) => sum + c)),
      );
    }
  }

  /// 画单根圆角柱（高度 <= 0 跳过）
  void _bar(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    Paint paint,
  ) {
    if (height <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        const Radius.circular(3),
      ),
      paint,
    );
  }

  /// 图例：右上角"灰方块 + 去年同期"，[sumText] 非空时追加在文字后
  void _legend(Canvas canvas, Size size, {String? sumText}) {
    final text = sumText == null ? '去年同期' : '去年同期 $sumText';
    final tp = TextPainter(
      text: TextSpan(
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
