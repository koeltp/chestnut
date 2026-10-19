import 'dart:math';

import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/tag_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/pages/stats/stats_logic.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 性能基线测试：5 万笔账单量级下"全部"模式数据链路各环节耗时
///
/// 只打印不硬断言（性能数字随机器/负载抖动，硬断言会随机挂），
/// 用于决策统计页全部模式是否需要分页。跑法：
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
    final typeBills = bills
        .where((b) => b.type == BillType.expense)
        .toList();
    bench('aggregateByCategory（支出全量）', () {
      aggregateByCategory(typeBills, categoriesMap);
    });

    // 环节 4：按日分组（明细列表数据结构）
    bench('按日分组 dayMap', () {
      final dayKeys = <String>[];
      final dayMap = <String, List<Bill>>{};
      for (final b in typeBills) {
        final key = '${b.date.year}-${b.date.month}-${b.date.day}';
        dayMap.putIfAbsent(key, () {
          dayKeys.add(key);
          return [];
        }).add(b);
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
}
