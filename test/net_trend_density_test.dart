import 'package:chestnut/pages/asset/net_trend_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// 走势图密度规则：点间距固定 20dp，窗口点数由宽度反推；
/// 刻度先算能写下几个，写不下才按整数个点抽稀。
void main() {
  group('可视窗口点数（点间距 20dp）', () {
    test('400dp 宽放得下 20 个点，800dp 放得下 40 个点', () {
      expect(netTrendWindowPoints(plotWidth: 400, totalPoints: 365), 20);
      expect(netTrendWindowPoints(plotWidth: 800, totalPoints: 365), 40);
    });

    test('历史点不足一屏时全部显示（季档 9 个点）', () {
      expect(netTrendWindowPoints(plotWidth: 800, totalPoints: 9), 9);
    });

    test('极窄屏也至少给 2 个点，避免单点除零', () {
      expect(netTrendWindowPoints(plotWidth: 10, totalPoints: 100), 2);
    });
  });

  group('刻度步长（整数个点）', () {
    test('40 个点只能写下 20 个刻度 → 每 2 个点标一个', () {
      // 标签占位 40dp：800 / 40 + 1 = 21 个容量，40 点 → 步长 2
      expect(
        netTrendLabelStep(windowPoints: 40, plotWidth: 800, labelWidth: 32),
        2,
      );
    });

    test('季档点少，刻度全部显示（步长 1）', () {
      expect(
        netTrendLabelStep(windowPoints: 9, plotWidth: 800, labelWidth: 34),
        1,
      );
    });

    test('日档小屏：19 个点、380dp 宽 → 步长 2', () {
      // 380 / 40 + 1 = 10 个容量，19 点 → 步长 2，共 10 个刻度
      expect(
        netTrendLabelStep(windowPoints: 19, plotWidth: 380, labelWidth: 32),
        2,
      );
    });

    test('标签更宽时按实际占位算容量，而不是死守 40dp', () {
      // 标签 72dp + 8 = 80dp：800 / 80 + 1 = 11 个容量，40 点 → 步长 4
      expect(
        netTrendLabelStep(windowPoints: 40, plotWidth: 800, labelWidth: 72),
        4,
      );
    });

    test('只有一个点时步长为 1，不做抽稀', () {
      expect(
        netTrendLabelStep(windowPoints: 1, plotWidth: 400, labelWidth: 32),
        1,
      );
    });

    test('年档标签窄：20 个点、720dp 宽时全部写上', () {
      expect(
        netTrendLabelStep(windowPoints: 20, plotWidth: 720, labelWidth: 22),
        1,
      );
    });
  });

  group('卡片查询起点：窗口点数 N 反推 from', () {
    final now = DateTime(2026, 11, 9);

    test('日档取 N-1 天前，连同今天正好 N 个点', () {
      expect(
        netTrendWindowFrom(range: NetTrendRange.day, points: 12, now: now),
        DateTime(2026, 10, 29),
      );
    });

    test('月档取 N-1 个月前的月初', () {
      expect(
        netTrendWindowFrom(range: NetTrendRange.month, points: 12, now: now),
        DateTime(2025, 12, 1),
      );
    });

    test('季档从本季首往前推 N-1 个季度', () {
      // 2026Q4 往前 11 个季度 = 2024Q1
      expect(
        netTrendWindowFrom(range: NetTrendRange.quarter, points: 12, now: now),
        DateTime(2024, 1, 1),
      );
    });

    test('年档取 N-1 年前的元旦', () {
      expect(
        netTrendWindowFrom(range: NetTrendRange.year, points: 12, now: now),
        DateTime(2015, 1, 1),
      );
    });

    test('只要一个点时，起点就是当前期的开始', () {
      expect(
        netTrendWindowFrom(range: NetTrendRange.day, points: 1, now: now),
        DateTime(2026, 11, 9),
      );
      expect(
        netTrendWindowFrom(range: NetTrendRange.month, points: 1, now: now),
        DateTime(2026, 11, 1),
      );
      expect(
        netTrendWindowFrom(range: NetTrendRange.quarter, points: 1, now: now),
        DateTime(2026, 10, 1),
      );
      expect(
        netTrendWindowFrom(range: NetTrendRange.year, points: 1, now: now),
        DateTime(2026, 1, 1),
      );
    });
  });
}
