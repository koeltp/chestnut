import 'dart:math' show ln10, log, pow;

import 'package:intl/intl.dart';

import '../../data/repositories/asset_repository.dart';

/// 走势档位：日/月/年对应时间窗口，"全部"在卡片里抽稀到每年一个点
enum NetTrendRange { day, month, year, all }

/// 档位胶囊文案
String netTrendRangeLabel(NetTrendRange range) => switch (range) {
  NetTrendRange.day => '日',
  NetTrendRange.month => '月',
  NetTrendRange.year => '年',
  NetTrendRange.all => '全部',
};

/// 聚合出当前档位的显示点：
/// 日 = 最近 15 天的日级快照；月/年 = 每段（自然月/自然年）最后一条快照，
/// 取"月末/年末水位"；全部 = 每年最后一条（卡片不滚动，抽稀避免点过密）。
/// 末点统一用今天的实时净值兜底，任何档位曲线都画到"现在"。
///
/// [fullHistory] 为 true 时不再截断时间窗：日/月/年也取全部历史，
/// "全部"档也不再按年抽稀，由全屏页按档位窗口横滑逐段查看；
/// 卡片仍用截断的短窗口与每年一个点的抽稀结果。
List<NetValuePoint> netTrendPoints({
  required NetTrendRange range,
  required List<NetValuePoint> history,
  required int currentNetCents,
  bool fullHistory = false,
}) {
  final now = DateTime.now();
  final today = DateFormat('yyyy-MM-dd').format(now);
  // 与实时同日的历史点让位：实时值总是更新
  final fresh = history.where((p) => p.$1 != today).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final end = <NetValuePoint>[(today, currentNetCents)];
  switch (range) {
    case NetTrendRange.day:
      if (fullHistory) return [...fresh, ...end];
      // 含今天共 15 个自然日
      final cutoff = DateFormat('yyyy-MM-dd')
          .format(now.subtract(const Duration(days: 14)));
      return [...fresh.where((p) => p.$1.compareTo(cutoff) >= 0), ...end];
    case NetTrendRange.month:
      if (fullHistory) return [..._lastPerPeriod(fresh, 7), ...end];
      // 最近 12 个自然月（以当前月为末点往前数 11 个月）
      final cutoff = DateFormat('yyyy-MM-dd')
          .format(DateTime(now.year, now.month - 11, 1));
      return [
        ..._lastPerPeriod(fresh.where((p) => p.$1.compareTo(cutoff) >= 0), 7),
        ...end,
      ];
    case NetTrendRange.year:
      if (fullHistory) return [..._lastPerPeriod(fresh, 4), ...end];
      // 最近 12 个自然年
      final cutoff = DateFormat('yyyy-MM-dd')
          .format(DateTime(now.year - 11, 1, 1));
      return [
        ..._lastPerPeriod(fresh.where((p) => p.$1.compareTo(cutoff) >= 0), 4),
        ...end,
      ];
    case NetTrendRange.all:
      return [...(fullHistory ? fresh : _lastPerPeriod(fresh, 4)), ...end];
  }
}

/// 每个时段（key = 日期前 [prefixLen] 位：yyyy-MM 或 yyyy）保留最后一条
/// 快照；入参须已按日期升序，后到者覆盖即为段末水位
List<NetValuePoint> _lastPerPeriod(Iterable<NetValuePoint> pts, int prefixLen) {
  final map = <String, NetValuePoint>{};
  for (final p in pts) {
    map[p.$1.substring(0, prefixLen)] = p;
  }
  final keys = map.keys.toList()..sort();
  return [for (final k in keys) map[k]!];
}

/// 横轴标签随档换格式：日 MM-dd / 月 yy-MM / 年 yyyy；
/// "全部"档按可视点数密度在 年 / 年-月 / 月-日 之间切换
String netTrendDateLabel(NetTrendRange range, String date, int visibleCount) {
  switch (range) {
    case NetTrendRange.day:
      return date.substring(5);
    case NetTrendRange.month:
      return '${date.substring(2, 4)}-${date.substring(5, 7)}';
    case NetTrendRange.year:
      return date.substring(0, 4);
    case NetTrendRange.all:
      // 卡片里按年抽稀（点数少）显示年份；全屏窗口覆盖几个月则显示月-日
      return visibleCount > 30 ? date.substring(5) : date.substring(0, 4);
  }
}

/// 纵轴金额缩写（分）：≥1 亿显示"亿"、≥1 万元显示"万"，其余按元。
/// 1 万元 = 100 万分，除数是 1e6——刻度值已对齐整间隔，
/// 1 位小数去尾零就能保持干净（8万 / 8.6万 / 160万）
String netTrendAxisLabel(double cents) {
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
double netTrendNiceInterval(double raw) {
  final mag = pow(10, (log(raw) / ln10).floorToDouble()).toDouble();
  final f = raw / mag;
  final nice = f >= 5 ? 5 : (f >= 2 ? 2 : 1);
  return nice * mag;
}

/// 纵轴范围对齐到整刻度间隔：净值走平（min==max）时先垫出可视区间，
/// 再把上下界外扩到间隔整数倍——所有刻度都落在整数倍上，干净整齐
({double minY, double maxY, double interval}) netTrendYRange(
  List<NetValuePoint> points,
) {
  final values = points.map((p) => p.$2).toList();
  var minY = values.reduce((a, b) => a < b ? a : b).toDouble();
  var maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
  if (maxY - minY < 2000) {
    final mid = (maxY + minY) / 2;
    minY = mid - 1000;
    maxY = mid + 1000;
  }
  final interval = netTrendNiceInterval(maxY - minY);
  minY = (minY / interval).floorToDouble() * interval;
  maxY = (maxY / interval).ceilToDouble() * interval;
  return (minY: minY, maxY: maxY, interval: interval);
}
