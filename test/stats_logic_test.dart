import 'package:chestnut/data/database.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/pages/stats/stats_logic.dart';
import 'package:chestnut/pages/stats/stats_query.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计页纯逻辑测试：主体过滤与分类聚合
///
/// 覆盖拆分自 stats_page 的纯函数（filterBills / aggregateByCategory /
/// pieEntries），聚合口径：二级上浮一级、金额降序；转账账单不参与
/// 任何统计。
void main() {
  final now = DateTime(2026, 10, 5);

  Category cat(int id, String name, {int? parentId}) => Category(
    id: id,
    name: name,
    iconCode: 0,
    colorValue: 0xFF000000,
    type: BillType.expense,
    parentId: parentId,
    sortOrder: 0,
    isFallback: false,
  );

  Bill bill(
    int id,
    int categoryId,
    int cents, {
    String? note,
    String? locationFull,
    BillType type = BillType.expense,
  }) => Bill(
    id: id,
    type: type,
    amountCents: cents,
    categoryId: categoryId,
    note: note,
    date: now,
    timeMinute: null,
    location: null,
    locationFull: locationFull,
    lat: null,
    lng: null,
    createdAt: now,
  );

  final categories = {
    1: cat(1, '餐饮'),
    2: cat(2, '打车', parentId: 3), // 一级"交通"的子分类
    3: cat(3, '交通'),
  };

  group('filterBills', () {
    test('关键词命中备注（英文大小写不敏感）与分类名', () {
      final bills = [bill(1, 1, 100, note: 'Milk Tea'), bill(2, 3, 200)];
      expect(
        filterBills(bills, categories: categories, range: (null, null), keyword: 'milk'),
        [bills[0]],
      );
      expect(
        filterBills(bills, categories: categories, range: (null, null), keyword: '交通'),
        [bills[1]],
      );
    });

    test('日期区间：start 含当天、end 排他', () {
      final bills = [bill(1, 1, 100)]; // date = 2026-10-05
      expect(
        filterBills(
          bills,
          categories: categories,
          range: (DateTime(2026, 10, 5), DateTime(2026, 10, 6)),
        ),
        hasLength(1),
      );
      expect(
        filterBills(
          bills,
          categories: categories,
          range: (DateTime(2026, 10, 6), DateTime(2026, 10, 7)),
        ),
        isEmpty,
      );
    });

    test('分类视图：视图分类及其全部子分类命中', () {
      final bills = [bill(1, 2, 100), bill(2, 3, 200), bill(3, 1, 300)];
      final out = filterBills(
        bills,
        categories: categories,
        range: (null, null),
        view: StatsViewType.category,
        viewCategoryId: 3,
      );
      expect(out.map((b) => b.id), [1, 2]);
    });

    test('未细分视图：只留直挂视图分类的账单', () {
      final bills = [bill(1, 3, 100), bill(2, 2, 200)];
      final out = filterBills(
        bills,
        categories: categories,
        range: (null, null),
        view: StatsViewType.uncategorized,
        viewCategoryId: 3,
      );
      expect(out.single.id, 1);
    });

    test('转账账单一律排除（转账不挂分类，不参与统计）', () {
      final bills = [
        bill(1, 1, 100),
        bill(2, 1, 200, type: BillType.transfer),
      ];
      expect(
        filterBills(bills, categories: categories, range: (null, null)),
        [bills[0]],
      );
    });

    test('全部视图多选：勾一级即含子分类账单（与聚合上浮口径一致）', () {
      final bills = [bill(1, 2, 100), bill(2, 3, 200), bill(3, 1, 300)];
      final out = filterBills(
        bills,
        categories: categories,
        range: (null, null),
        filterCategoryIds: {3},
      );
      expect(out.map((b) => b.id), [1, 2]);
    });

    test('全部视图多选：分类已被迁移删除的悬空账单不保留', () {
      final bills = [bill(1, 99, 100), bill(2, 3, 200)];
      expect(
        filterBills(
          bills,
          categories: categories,
          range: (null, null),
          filterCategoryIds: {3},
        ).map((b) => b.id),
        [2],
      );
    });
  });

  group('aggregateByCategory', () {
    test('同分类合并、金额降序', () {
      final bills = [bill(1, 1, 1000), bill(2, 3, 500), bill(3, 1, 700)];
      final entries = aggregateByCategory(bills, categories);
      expect(entries.map((e) => e.name).toList(), ['餐饮', '交通']);
      expect(entries.first.cents, 1700);
    });

    test('二级分类账单上浮归并到一级', () {
      final bills = [
        bill(1, 2, 500), // 二级"打车" → 归一级"交通"
        bill(2, 3, 200), // 直接挂一级"交通"
        bill(3, 1, 100), // 一级"餐饮"
      ];
      final entries = aggregateByCategory(bills, categories);
      expect(entries.map((e) => e.name).toList(), ['交通', '餐饮']);
      expect(entries.first.cents, 700);
      // 钻取目标为一级分类本身
      expect(entries.first.category!.id, 3);
    });

    test('分类已被迁移删除的账单（悬空 id）跳过不聚合', () {
      final bills = [bill(1, 99, 300)];
      expect(aggregateByCategory(bills, categories), isEmpty);
    });
  });

  group('pieEntries', () {
    test('按子分类聚合，直接挂一级归"未细分"', () {
      final bills = [
        bill(1, 2, 500), // 子分类"打车"
        bill(2, 3, 200), // 直接挂一级"交通"
      ];
      final entries = pieEntries(bills, categories, categories[3]!);
      expect(entries.map((e) => e.name).toList(), ['打车', '未细分']);
      expect(entries.last.category, isNull);
    });

    test('其他一级分类的账单不算本分类子项，归"未细分"', () {
      final bills = [bill(1, 1, 800)]; // "餐饮"的账单
      final entries = pieEntries(bills, categories, categories[3]!);
      expect(entries.single.name, '未细分');
      expect(entries.single.cents, 800);
    });
  });
}
