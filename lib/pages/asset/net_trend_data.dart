import 'dart:math' show ln10, log, max, min, pow;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/asset_repository.dart';

/// 走势档位：日/月/季/年 — 分别给日级波动、月级走势、季度级全历史、年级水位
/// 四个观察视角。枚举名与展示文案保持词义一致（quarter ↔ 季）。
enum NetTrendRange { day, month, quarter, year }

/// 档位胶囊文案
String netTrendRangeLabel(NetTrendRange range) => switch (range) {
  NetTrendRange.day => '日',
  NetTrendRange.month => '月',
  NetTrendRange.quarter => '季',
  NetTrendRange.year => '年',
};

/// 横轴点间距（逻辑像素）：一屏能显示多少个点由绘图区宽度 ÷ 它反推。
const double kTrendPointSpacing = 20;

/// 轴标签字号（逻辑像素）：标签宽高、间距、轴留白全部由它推导，
/// 不在各处分别写死；系统字号放大时它们同比放大。
const double kTrendAxisFontSize = 10;

/// 相邻刻度标签之间的最小空隙：跟字号走。
const double kTrendLabelGap = kTrendAxisFontSize * 0.8;

/// 轴标签与绘图区之间的留白：跟字号走。
const double kTrendAxisPadding = kTrendAxisFontSize * 0.6;

/// 按实际字体与系统缩放量一段轴文字的尺寸。
/// 左轴宽、底部预留高、刻度槽位都由它算出来，不再用 38/22/40 这类估值。
Size netTrendTextSize(String text, {required TextScaler textScaler}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: kTrendAxisFontSize),
    ),
    textDirection: ui.TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  return painter.size;
}

/// 绘图区一屏最多能放几个点：只由宽度决定，与数据量无关。
/// 卡片用它反推"该查多少点"，图表用它和总点数取小得到窗口。
int netTrendWindowCapacity(double plotWidth) =>
    max(2, (plotWidth / kTrendPointSpacing).floor());

/// 可视窗口点数：点间距固定 [kTrendPointSpacing]，由绘图区真实宽度反推。
/// 窗口内的点全部绘制、一个不抽——屏幕窄窗口就窄，更早的数据靠横滑平移。
int netTrendWindowPoints({
  required double plotWidth,
  required int totalPoints,
}) => min(totalPoints, netTrendWindowCapacity(plotWidth));

/// 刻度步长（单位=点）：先按标签实际占位算一屏能写下几个刻度，
/// 写不下才抽稀。步长只能取整数个点，刻度才始终落在数据点上：
/// 例如 40 个点、只能写下 20 个刻度 → 每 2 个点标一个。
int netTrendLabelStep({
  required int windowPoints,
  required double plotWidth,
  required double labelWidth,
  double labelGap = kTrendLabelGap,
}) {
  if (windowPoints <= 1) return 1;
  // 槽位只由"标签实际宽度 + 不重叠所需空隙"决定，没有额外下限：
  // 年档标签窄，就应当比日档多写几个，而不是被日档的舒适值挤掉
  final slot = labelWidth + labelGap;
  final capacity = max(2, (plotWidth / slot).floor() + 1);
  return max(1, (windowPoints / capacity).ceil());
}

/// 卡片窗口的查询起点：由"一屏能画几个点"反推该档位要回溯到哪一天。
/// [points] 含今天的实时点，所以历史只需 [points]-1 个聚合点。
/// 只服务"贴右端、不可滑"的卡片——全屏要能滑到最早，必须全量。
DateTime netTrendWindowFrom({
  required NetTrendRange range,
  required int points,
  DateTime? now,
}) {
  final n = max(0, points - 1);
  final t = now ?? DateTime.now();
  return switch (range) {
    NetTrendRange.day => DateTime(
      t.year,
      t.month,
      t.day,
    ).subtract(Duration(days: n)),
    NetTrendRange.month => DateTime(t.year, t.month - n, 1),
    // 本季首月 = (month-1)~/3*3+1，再往前挪 3n 个月
    NetTrendRange.quarter => DateTime(
      t.year,
      ((t.month - 1) ~/ 3) * 3 + 1 - 3 * n,
      1,
    ),
    NetTrendRange.year => DateTime(t.year - n, 1, 1),
  };
}

/// 聚合出当前档位的显示点：
/// 日 = 逐日快照；
/// 月 = 每自然月最后一条快照（月末水位）；
/// 年 = 每自然年最后一条快照（年末水位）；
/// 季 = 每自然季度最后一条快照（季末水位）。
/// 取多少历史由调用方决定：卡片按窗口点数反推查询起点，
/// 全屏页取全量（靠横滑到达更早），这里只负责聚合。
/// 末点统一用今天的实时净值兜底，任何档位曲线都画到"现在"。
List<NetValuePoint> netTrendPoints({
  required NetTrendRange range,
  required List<NetValuePoint> history,
  required int currentNetCents,
}) {
  final now = DateTime.now();
  final today = DateFormat('yyyy-MM-dd').format(now);
  // 与实时同日的历史点让位：实时值总是更新
  final fresh = history.where((p) => p.$1 != today).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final end = <NetValuePoint>[(today, currentNetCents)];
  switch (range) {
    case NetTrendRange.day:
      return [...fresh, ...end];
    case NetTrendRange.month:
      return _mergeEnd(_lastPerPeriod(fresh, 7), end.first, 7);
    case NetTrendRange.year:
      return _mergeEnd(_lastPerPeriod(fresh, 4), end.first, 4);
    case NetTrendRange.quarter:
      return _mergeEndQuarter(_lastPerQuarter(fresh), end.first);
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

/// 每个自然季度保留最后一条快照（季末水位）。
/// key 格式 "YYYY-Qn"（Q1=1-3月，Q2=4-6月…），同季度后到者覆盖。
/// 日期是 `yyyy-MM-dd` 定长文本，直接切子串算季度——逐行 DateTime.parse
/// 在 20 年（7000+ 行）量级上实测要 200ms+，是切档卡顿的主因。
List<NetValuePoint> _lastPerQuarter(Iterable<NetValuePoint> pts) {
  final map = <String, NetValuePoint>{};
  for (final p in pts) {
    final month = int.parse(p.$1.substring(5, 7));
    final q = ((month - 1) ~/ 3) + 1;
    map['${p.$1.substring(0, 4)}-Q$q'] = p;
  }
  final keys = map.keys.toList()..sort();
  return [for (final k in keys) map[k]!];
}

/// 把 [end] 实时净值合并到聚合结果末尾：
/// 如果 [end] 和聚合最后一个点同年/月/日（prefixLen 匹配），用 end 替换
/// 它（实时净值总是最新），否则追加到末尾。
List<NetValuePoint> _mergeEnd(
  List<NetValuePoint> aggregated,
  NetValuePoint end,
  int prefixLen,
) {
  if (aggregated.isEmpty) return [end];
  final last = aggregated.last;
  if (last.$1.substring(0, prefixLen) == end.$1.substring(0, prefixLen)) {
    return [...aggregated.sublist(0, aggregated.length - 1), end];
  }
  return [...aggregated, end];
}

/// 季度版 merge：end 和聚合最后一个点同季度就覆盖，否则追加。
List<NetValuePoint> _mergeEndQuarter(
  List<NetValuePoint> aggregated,
  NetValuePoint end,
) {
  if (aggregated.isEmpty) return [end];
  final dt = DateTime.parse(end.$1);
  final q = ((dt.month - 1) ~/ 3) + 1;
  final key = '${dt.year}-Q$q';
  final lastDt = DateTime.parse(aggregated.last.$1);
  final lastQ = ((lastDt.month - 1) ~/ 3) + 1;
  final lastKey = '${lastDt.year}-Q$lastQ';
  if (lastKey == key) {
    return [...aggregated.sublist(0, aggregated.length - 1), end];
  }
  return [...aggregated, end];
}

/// 横轴标签格式：日 MM/dd / 月 YY/MM / 年 yyyy / 季 YY/Qn（26/Q3 = 2026Q3）。
/// 季档用季度标识避免和月档 YY/MM 格式混淆。
String netTrendDateLabel(NetTrendRange range, String date, int visibleCount) {
  switch (range) {
    case NetTrendRange.day:
      return '${date.substring(5, 7)}/${date.substring(8)}'; // MM/dd
    case NetTrendRange.month:
      return '${date.substring(2, 4)}/${date.substring(5, 7)}'; // YY/MM
    case NetTrendRange.year:
      return date.substring(0, 4); // yyyy
    case NetTrendRange.quarter:
      // 同 _lastPerQuarter：切子串算季度，拖动时每帧都要算标签，不能解析日期
      final q = ((int.parse(date.substring(5, 7)) - 1) ~/ 3) + 1;
      return '${date.substring(2, 4)}/Q$q'; // YY/Qn
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
