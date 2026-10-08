import 'package:chestnut/data/database.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/pages/stats/stats_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计页纯逻辑测试：关键词过滤与分类聚合
///
/// 覆盖拆分自 stats_page 的三个纯函数（applyKeyword /
/// aggregateByCategory / pieEntries），聚合口径：已删除分类账单
/// 归"未知分类"或"未细分"，金额降序。
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

  group('applyKeyword', () {
    test('命中备注（英文大小写不敏感）', () {
      final bills = [bill(1, 1, 100, note: 'Milk Tea')];
      expect(applyKeyword(bills, categories, 'milk'), hasLength(1));
    });

    test('命中定位完整信息', () {
      final bills = [bill(1, 1, 100, locationFull: '广东省 深圳市 南山 某店')];
      expect(applyKeyword(bills, categories, '南山'), hasLength(1));
    });

    test('命中分类名', () {
      final bills = [bill(1, 1, 100)];
      expect(applyKeyword(bills, categories, '餐'), hasLength(1));
    });

    test('未命中与关键词空白返回原列表', () {
      final bills = [bill(1, 1, 100, note: '午餐')];
      expect(applyKeyword(bills, categories, '打车'), isEmpty);
      // trim 后为空 → 原样返回（同一实例，不过滤）
      expect(identical(applyKeyword(bills, categories, '  '), bills), isTrue);
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

    test('分类已删除的账单归"未知分类"且不可钻取', () {
      final bills = [bill(1, 99, 300)];
      final entries = aggregateByCategory(bills, categories);
      expect(entries.single.name, '未知分类');
      expect(entries.single.category, isNull);
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
