import 'dart:math';

import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/asset_repository.dart';
import 'package:chestnut/data/repositories/tag_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/pages/asset/net_trend_data.dart';
import 'package:chestnut/pages/stats/stats_logic.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// 性能基线测试：5 万笔账单量级下"全部"模式数据链路各环节耗时
///
/// 打印数字 + 宽松上限断言：阈值故意留 10 倍以上余量，只拦
/// "数量级回退"（例如把 O(n) 写成 O(n²) 或逐行 DateTime.parse），
/// 不因机器负载抖动随机挂。跑法：
/// `flutter test test/perf_baseline_test.dart`
///
/// 环节口径与统计页 _buildBody 一致：全量流首帧 → filterBills →
/// 聚合/按日分组 → getTagsByBillIds。
void main() {
  late AppDatabase db;
  late TagRepository tagRepo;

  /// 计时并打印同步计算耗时（毫秒）
  int bench(String name, void Function() body) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    final ms = sw.elapsedMicroseconds / 1000;
    // ignore: avoid_print
    print('  [perf] $name: ${ms.toStringAsFixed(1)} ms');
    return sw.elapsedMicroseconds;
  }

  setUpAll(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tagRepo = TagRepository(db);
    // 触发建库（预置分类随之可用）
    await db.customSelect('SELECT 1').get();
    await _seed(db);
  });

  tearDownAll(() => db.close());

  test('5 万笔基线：全量链路各环节耗时', () async {
    final total = await db.select(db.bills).get();
    // ignore: avoid_print
    print('[perf] 账单总量: ${total.length} 笔');

    // 环节 0：全量流首帧（统计页全部模式的数据源）
    final swAll = Stopwatch()..start();
    final bills = await db.select(db.bills).get();
    swAll.stop();
    // ignore: avoid_print
    print(
      '  [perf] 全量流首帧（select bills 全表）: '
      '${swAll.elapsedMicroseconds / 1000} ms',
    );

    final categoriesMap = {
      for (final c in await db.select(db.categories).get()) c.id: c,
    };

    // 环节 1：filterBills——全部模式无筛选（最常见状态）
    bench('filterBills 全部模式·无筛选', () {
      filterBills(bills, categories: categoriesMap, range: (null, null));
    });

    // 环节 2：filterBills——单选一个一级分类 + 关键词（重口径）
    final rootIds = [
      for (final c in categoriesMap.values)
        if (c.parentId == null && c.type == BillType.expense) c.id,
    ];
    bench('filterBills 全部模式·分类多选+关键词', () {
      filterBills(
        bills,
        categories: categoriesMap,
        range: (null, null),
        keyword: '备注关键词',
        filterCategoryIds: {rootIds.first},
      );
    });

    // 环节 3：aggregateByCategory（环图/排行）
    final typeBills = bills.where((b) => b.type == BillType.expense).toList();
    bench('aggregateByCategory（支出全量）', () {
      aggregateByCategory(typeBills, categoriesMap);
    });

    // 环节 4：按日分组（明细列表数据结构）
    bench('按日分组 dayMap', () {
      final dayKeys = <String>[];
      final dayMap = <String, List<Bill>>{};
      for (final b in typeBills) {
        final key = '${b.date.year}-${b.date.month}-${b.date.day}';
        dayMap
            .putIfAbsent(key, () {
              dayKeys.add(key);
              return [];
            })
            .add(b);
      }
    });

    // 环节 5：getTagsByBillIds——5 万 id 拼 IN 查询（重点怀疑对象）
    // SQLite 变量数上限 32766（3.32+），5 万 id 可能直接抛异常：
    // 抛了就如实记录——这正是"全部模式不分页"时的真实行为
    final allIds = bills.map((b) => b.id).toList();
    try {
      final sw = Stopwatch()..start();
      final tagsByBill = await tagRepo.getTagsByBillIds(allIds);
      sw.stop();
      // ignore: avoid_print
      print(
        '  [perf] getTagsByBillIds(${allIds.length} ids): '
        '${sw.elapsedMicroseconds / 1000} ms，命中 ${tagsByBill.length} 笔',
      );
    } catch (e) {
      // ignore: avoid_print
      print('  [perf] getTagsByBillIds(${allIds.length} ids): ❌ 抛异常 → $e');
    }
  });

  test('对照：单月视图链路（月模式天然数据量小）', () async {
    final bills = await db.select(db.bills).get();
    final categoriesMap = {
      for (final c in await db.select(db.categories).get()) c.id: c,
    };
    // 取数据量最大的一个月（种子覆盖的中间月）
    final monthBills = bills
        .where((b) => b.date.year == 2024 && b.date.month == 6)
        .toList();
    // ignore: avoid_print
    print('[perf] 单月账单量: ${monthBills.length} 笔');

    bench('filterBills 单月·无筛选', () {
      filterBills(monthBills, categories: categoriesMap, range: (null, null));
    });
    bench('aggregateByCategory 单月', () {
      aggregateByCategory(monthBills, categoriesMap);
    });
  });

  test('净值走势基线：20 年（约 7300 行）全量取数', () async {
    // 独立内存库：不能复用上面那份（会把 3 年基线污染成 20 年）
    final big = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(big.close);
    await big.customSelect('SELECT 1').get();
    await _seedNetDays(big, years: 20);
    final repo = AssetRepository(big);

    // 环节 0：全量流首帧（四档都 from=null 时的数据源）
    final sw = Stopwatch()..start();
    final history = await repo.watchNetHistory().first;
    sw.stop();
    // ignore: avoid_print
    print(
      '  [perf] watchNetHistory 全量首帧（${history.length} 行）: '
      '${sw.elapsedMicroseconds / 1000} ms',
    );
    expect(
      sw.elapsedMicroseconds,
      lessThan(1500 * 1000),
      reason: '20 年全量首帧超过 1.5s，疑似查询/组装逻辑回退',
    );

    // 环节 1：Dart 侧四档聚合（全屏全量口径）
    const currentNet = 6400000;
    for (final range in NetTrendRange.values) {
      final us = bench(
        'netTrendPoints ${netTrendRangeLabel(range)}·全屏全量+纵轴',
        () {
          final pts = netTrendPoints(
            range: range,
            history: history,
            currentNetCents: currentNet,
          );
          netTrendYRange(pts);
        },
      );
      // 季档曾因逐行 DateTime.parse 飙到 280ms；这里用 250ms 兜住同类回退
      expect(
        us,
        lessThan(250 * 1000),
        reason: '${netTrendRangeLabel(range)} 档聚合超过 250ms，疑似逐行解析/重复遍历',
      );
    }

    // 环节 2：对照——把"每期最后一条"下推到 SQL 的成本
    for (final (label, key) in [
      ('月', "substr(day, 1, 7)"),
      (
        '季',
        "substr(day, 1, 4) || '-' || ((CAST(substr(day, 6, 2) AS INTEGER) - 1) / 3)",
      ),
      ('年', "substr(day, 1, 4)"),
    ]) {
      final q = Stopwatch()..start();
      final rows = await big
          .customSelect(
            'SELECT day, net_cents FROM net_value_days '
            'WHERE day IN (SELECT MAX(day) FROM net_value_days GROUP BY $key) '
            'ORDER BY day',
          )
          .get();
      q.stop();
      // ignore: avoid_print
      print(
        '  [perf] SQL 下推·$label（${rows.length} 行）: '
        '${q.elapsedMicroseconds / 1000} ms',
      );
    }
  });

  test('净值卡片：全量 vs 按窗口点数 N 查（N=12/20）', () async {
    final big = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(big.close);
    await big.customSelect('SELECT 1').get();
    await _seedNetDays(big, years: 20);
    final repo = AssetRepository(big);
    const currentNet = 6400000;

    // A：卡片走全量流，再聚合、由窗口裁
    final aq = Stopwatch()..start();
    final all = await repo.watchNetHistory().first;
    aq.stop();
    final aa = Stopwatch()..start();
    for (final range in NetTrendRange.values) {
      final pts = netTrendPoints(
        range: range,
        history: all,
        currentNetCents: currentNet,
      );
      netTrendYRange(pts);
    }
    aa.stop();
    // ignore: avoid_print
    print(
      '  [perf] A 卡片全量：查询 ${all.length} 行 ${aq.elapsedMicroseconds / 1000} ms'
      ' + 四档聚合 ${aa.elapsedMicroseconds / 1000} ms',
    );

    // B：先算窗口点数 N，再按 N 反推每档查询起点
    for (final n in [12, 20]) {
      for (final range in NetTrendRange.values) {
        final from = netTrendWindowFrom(range: range, points: n);
        final q = Stopwatch()..start();
        final rows = await repo.watchNetHistory(from: from).first;
        q.stop();
        final a = Stopwatch()..start();
        final pts = netTrendPoints(
          range: range,
          history: rows,
          currentNetCents: currentNet,
        );
        netTrendYRange(pts);
        a.stop();
        // ignore: avoid_print
        print(
          '  [perf] B N=$n ${netTrendRangeLabel(range)}：'
          '查询 ${rows.length} 行 ${q.elapsedMicroseconds / 1000} ms'
          ' + 聚合 ${a.elapsedMicroseconds / 1000} ms（${pts.length} 点）',
        );
      }
    }
  });
}

/// 造 [years] 年逐日净值（到昨天为止），用于 20 年量级的走势基线
Future<void> _seedNetDays(AppDatabase db, {required int years}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var day = DateTime(now.year - years + 1, 1, 1);
  final fmt = DateFormat('yyyy-MM-dd');
  final rows = <NetValueDaysCompanion>[];
  var i = 0;
  while (day.isBefore(today)) {
    rows.add(
      NetValueDaysCompanion.insert(
        day: fmt.format(day),
        netCents: 5000000 + (i % 200) * 1000,
        updatedAt: 0,
      ),
    );
    day = day.add(const Duration(days: 1));
    i++;
  }
  await db.batch((b) => b.insertAllOnConflictUpdate(db.netValueDays, rows));
}

/// 造 5 万笔账单：2023-01-01 起每天 40 笔（约 1250 天），分类在预置
/// 支出一级里轮转；每 10 笔挂 1 个标签（建 5 个标签）。
/// 固定随机种子保证可复现。
Future<void> _seed(AppDatabase db) async {
  const billCount = 50000;
  const perDay = 40;
  final rng = Random(42);

  // 预置支出一级分类（建库时已插入）
  final expenseRoots =
      await (db.select(db.categories)
            ..where((c) => c.type.equalsValue(BillType.expense))
            ..where((c) => c.parentId.isNull()))
          .get();
  final rootIds = [for (final c in expenseRoots) c.id];

  // 5 个标签
  final tagIds = <int>[];
  for (var i = 1; i <= 5; i++) {
    tagIds.add(
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(name: '标签$i', color: 0xFF888888)),
    );
  }

  // 批量插入 5 万笔（batch 一次事务，避免逐条 insert 拖慢测试本身）
  final start = DateTime(2023, 1, 1);
  await db.batch((batch) {
    for (var i = 0; i < billCount; i++) {
      final date = start.add(Duration(days: i ~/ perDay));
      batch.insert(
        db.bills,
        BillsCompanion.insert(
          type: BillType.expense,
          amountCents: 100 + rng.nextInt(10000),
          categoryId: Value(rootIds[i % rootIds.length]),
          note: Value(i % 50 == 0 ? '备注关键词$i' : null),
          date: date,
        ),
      );
    }
  });

  // 每 10 笔挂 1 个标签
  final bills = await db.select(db.bills).get();
  await db.batch((batch) {
    for (var i = 0; i < bills.length; i += 10) {
      batch.insert(
        db.billTags,
        BillTagsCompanion.insert(
          billId: bills[i].id,
          tagId: tagIds[i % tagIds.length],
        ),
      );
    }
  });

  // 3 年日级净值（1095 行）：净值走势图"全部"档的数据源
  final dayStart = DateTime(2023, 1, 1);
  final dayFmt = DateFormat('yyyy-MM-dd');
  await db.batch((batch) {
    for (var i = 0; i < 1095; i++) {
      batch.insert(
        db.netValueDays,
        NetValueDaysCompanion.insert(
          day: dayFmt.format(dayStart.add(Duration(days: i))),
          netCents: 5000000 + rng.nextInt(200000),
          updatedAt: 0,
        ),
      );
    }
  });
}
