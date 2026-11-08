import '../models/enums.dart';

/// 快照聚合的输入行
///
/// 调用方须按 day 升序、同日按 createdAt/id 升序传入：同日多条
/// 后到者覆盖先到者，即"该日最后一条"口径。
class NetSnapshotRow {
  const NetSnapshotRow({
    required this.day,
    required this.assetId,
    required this.valueCents,
    required this.kind,
  });

  /// 快照日期 `yyyy-MM-dd`
  final String day;

  /// 所属资产 id
  final int assetId;

  /// 当日市值（分，恒为正数，负债由 [kind] 区分）
  final int valueCents;

  /// 资产类型：负债在求和时取负
  final AssetKind kind;
}

/// 日期转 `yyyy-MM-dd`（快照 day 与每日净值表 day 同口径）
String netDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 由快照行前向填充出 [fromDay, toDay]（含两端）的每日净值
///
/// 口径与旧版 watchNetHistory 逐点一致：
/// · 每项资产取"最近一条 ≤ 当天"的快照，净值 = Σ资产 − Σ负债；
/// · 无快照的空白天沿用前值，不归零；
/// · 首条快照日之前没有点；
/// · 归档/未计入总资产的账户，其历史快照照常参与（避免归档造成回溯断层）。
///
/// 只依赖纯数据，数据库与仓储共用这一份算法，迁移回填与增量重算
/// 不会出现两套口径。
List<(String, int)> buildNetValueDays({
  required List<NetSnapshotRow> rows,
  required String fromDay,
  required String toDay,
}) {
  final lastValue = <int, int>{};
  final kinds = <int, AssetKind>{};

  // 起点之前的快照只用于确定各资产的前值，不产出点
  var index = 0;
  while (index < rows.length && rows[index].day.compareTo(fromDay) < 0) {
    final row = rows[index++];
    kinds[row.assetId] = row.kind;
    lastValue[row.assetId] = row.valueCents;
  }

  int signedSum() => lastValue.entries.fold<int>(
    0,
    (sum, e) =>
        sum + (kinds[e.key] == AssetKind.liability ? -e.value : e.value),
  );

  final stopExclusive = DateTime.parse(toDay).add(const Duration(days: 1));
  var cursor = DateTime.parse(fromDay);
  final points = <(String, int)>[];

  // 起点之前没有任何快照：曲线从"首条快照日"才开始，起点到首条快照日
  // 之间不产出点（与旧实现的 cursor 初始化口径一致）。典型场景是某日
  // 快照被删、该资产更早没有记录
  if (lastValue.isEmpty && index < rows.length) {
    cursor = DateTime.parse(rows[index].day);
  }

  // 把 [cursor, endExclusive) 的空白天用当前合计铺满
  void fillUntil(DateTime endExclusive) {
    while (cursor.isBefore(endExclusive) && cursor.isBefore(stopExclusive)) {
      points.add((netDayKey(cursor), signedSum()));
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  String? currentDay;
  for (; index < rows.length; index++) {
    final row = rows[index];
    if (row.day.compareTo(toDay) > 0) break;
    if (row.day != currentDay) {
      // 先补齐快照日之前的空白天，再应用当日快照
      fillUntil(DateTime.parse(row.day));
      currentDay = row.day;
    }
    kinds[row.assetId] = row.kind;
    lastValue[row.assetId] = row.valueCents;
  }
  // 末个快照日之后铺到 toDay 为止
  fillUntil(stopExclusive);
  return points;
}
