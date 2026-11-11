import 'package:chestnut/pages/asset/net_trend_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// 日期文本（yyyy-MM-dd），与库里存储格式一致
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 当前自然季度首月 1 号
DateTime _quarterStart(DateTime d) =>
    DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 1, 1);

void main() {
  final now = DateTime.now();
  final today = _ymd(now);

  group('月档聚合：每自然月取月末水位', () {
    test('同月多条只留最后一条，跨月按时间升序', () {
      final prev = DateTime(now.year, now.month - 1, 10);
      final prevLater = DateTime(now.year, now.month - 1, 25);
      final prev2 = DateTime(now.year, now.month - 2, 20);
      final points = netTrendPoints(
        range: NetTrendRange.month,
        history: [
          (_ymd(prev2), 100),
          (_ymd(prev), 200),
          (_ymd(prevLater), 250),
        ],
        currentNetCents: 900,
      );
      expect(points.length, 3);
      expect(points[0], (_ymd(prev2), 100));
      // 同月后到者覆盖：10 号被 25 号顶掉
      expect(points[1], (_ymd(prevLater), 250));
      expect(points[2], (today, 900));
    });

    test('历史里已有今天：实时净值覆盖同日记录，不重复', () {
      final points = netTrendPoints(
        range: NetTrendRange.month,
        history: [(today, 111)],
        currentNetCents: 222,
      );
      expect(points, [(today, 222)]);
    });
  });

  group('季档聚合：每自然季度取季末水位', () {
    test('同季多条只留最后一条，跨季按时间升序', () {
      final qStart = _quarterStart(now);
      final prevQEnd = qStart.subtract(const Duration(days: 1));
      final prevQStart = _quarterStart(prevQEnd);
      final prevQ2End = prevQStart.subtract(const Duration(days: 1));
      final points = netTrendPoints(
        range: NetTrendRange.quarter,
        history: [
          (_ymd(prevQ2End), 50),
          (_ymd(prevQStart), 100),
          (_ymd(prevQEnd), 200),
        ],
        currentNetCents: 900,
      );
      expect(points.length, 3);
      expect(points[0], (_ymd(prevQ2End), 50));
      // 前一个季度内的两条合并成一条，取更晚的
      expect(points[1], (_ymd(prevQEnd), 200));
      expect(points[2], (today, 900));
    });

    test('跨季度边界：3 月 31 与 4 月 1 分属不同季度', () {
      final year = now.year - 3;
      final points = netTrendPoints(
        range: NetTrendRange.quarter,
        history: [('$year-03-31', 100), ('$year-04-01', 200)],
        currentNetCents: 900,
      );
      expect(points.length, 3);
      expect(points[0], ('$year-03-31', 100));
      expect(points[1], ('$year-04-01', 200));
    });

    test('历史里已有今天：实时净值覆盖当季最后一条', () {
      final points = netTrendPoints(
        range: NetTrendRange.quarter,
        history: [(today, 111)],
        currentNetCents: 222,
      );
      expect(points, [(today, 222)]);
    });
  });

  group('年档聚合：每自然年取年末水位', () {
    test('同一年多条只留最后一条，跨年升序', () {
      final lastYear = now.year - 1;
      final before = now.year - 2;
      final points = netTrendPoints(
        range: NetTrendRange.year,
        history: [
          ('$before-06-06', 50),
          ('$lastYear-01-05', 100),
          ('$lastYear-12-20', 200),
        ],
        currentNetCents: 900,
      );
      expect(points.length, 3);
      expect(points[0], ('$before-06-06', 50));
      expect(points[1], ('$lastYear-12-20', 200));
      expect(points[2], (today, 900));
    });
  });

  group('日档与空数据', () {
    test('日档保留全部历史日点，升序，今天被实时值覆盖', () {
      final y1 = now.subtract(const Duration(days: 1));
      final d3 = now.subtract(const Duration(days: 3));
      final points = netTrendPoints(
        range: NetTrendRange.day,
        history: [(_ymd(y1), 2), (_ymd(d3), 3), (today, 1)],
        currentNetCents: 9,
      );
      expect(points, [(_ymd(d3), 3), (_ymd(y1), 2), (today, 9)]);
    });

    test('没有任何历史时，各档都至少有今天的实时点', () {
      for (final range in NetTrendRange.values) {
        final points = netTrendPoints(
          range: range,
          history: const [],
          currentNetCents: 900,
        );
        expect(points, [(today, 900)], reason: '档位 $range');
      }
    });
  });
}
