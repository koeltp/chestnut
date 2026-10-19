import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/category_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分类"兄弟不重名"查重回归测试
///
/// 层级口径：一级分类查"同收支类型的全部一级"，二级分类查"同一父分类
/// 下的全部二级"；跨收支类型、跨父分类允许重名。名称比较 trim + 小写。
void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoryRepository(db);
    // 触发建库（预置支出"餐饮/交通…"与收入"工资…"等分类）
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  /// 建一个一级分类，返回 id
  Future<int> addParent(String name, BillType type, {int sortOrder = 0}) =>
      repo.addCategory(
        CategoriesCompanion.insert(
          name: name,
          iconCode: 0,
          colorValue: 0,
          type: type,
          sortOrder: Value(sortOrder),
        ),
      );

  /// 建一个二级分类，返回 id
  Future<int> addChild(String name, int parentId) => repo.addCategory(
    CategoriesCompanion.insert(
      name: name,
      iconCode: 0,
      colorValue: 0,
      type: BillType.expense,
      parentId: Value(parentId),
      sortOrder: const Value(0),
    ),
  );

  /// 建一笔支出账单，返回 id
  Future<int> addBill(int categoryId, {String? note, int cents = 100}) =>
      db.into(db.bills).insert(
        BillsCompanion.insert(
          type: BillType.expense,
          amountCents: cents,
          date: DateTime(2026, 10, 5),
          categoryId: Value(categoryId),
          note: Value(note),
        ),
      );

  /// 建一条分类预算，返回 id
  Future<int> addBudget(String month, int categoryId, int cents) =>
      db.into(db.budgets).insert(
        BudgetsCompanion.insert(
          month: month,
          amountCents: cents,
          categoryId: Value(categoryId),
        ),
      );

  group('一级分类查重', () {
    test('同类型下已存在同名 → true', () async {
      final id = await addParent('餐饮', BillType.expense);
      final exists = await repo.siblingNameExists(
        name: '餐饮',
        type: BillType.expense,
        parentId: null,
        excludeId: id, // 模拟新增场景：排除自身意义不大，但不排除会命中预置分类
      );
      // 预置库里支出已有"餐饮"，新查重应命中
      expect(exists, isTrue);
    });

    test('名称差异仅为大小写/首尾空格 → true', () async {
      final exists = await repo.siblingNameExists(
        name: '  餐饮 ',
        type: BillType.expense,
        parentId: null,
      );
      expect(exists, isTrue);
    });

    test('跨收支类型允许重名（收入下没有"餐饮"）→ false', () async {
      final exists = await repo.siblingNameExists(
        name: '餐饮',
        type: BillType.income,
        parentId: null,
      );
      expect(exists, isFalse);
    });

    test('新增不重名分类 → false', () async {
      final exists = await repo.siblingNameExists(
        name: '宠物',
        type: BillType.expense,
        parentId: null,
      );
      expect(exists, isFalse);
    });

    test('改名场景：排除自身后不误判 → false', () async {
      // 新建一个支出一级"医疗充值"，改名"医疗充值"自身时排除自己
      final id = await addParent('医疗充值', BillType.expense);
      final exists = await repo.siblingNameExists(
        name: '医疗充值',
        type: BillType.expense,
        parentId: null,
        excludeId: id,
      );
      expect(exists, isFalse);
    });
  });

  group('二级分类查重', () {
    test('同父下重名（大小写变体）→ true', () async {
      final parent = await addParent('宠物', BillType.expense);
      await addChild('猫粮', parent);
      final exists = await repo.siblingNameExists(
        name: '猫粮',
        type: BillType.expense,
        parentId: parent,
      );
      expect(exists, isTrue);
    });

    test('不同父分类下允许重名 → false', () async {
      final parentA = await addParent('宠物', BillType.expense, sortOrder: 20);
      final parentB = await addParent('农场', BillType.expense, sortOrder: 21);
      await addChild('猫粮', parentA);
      final exists = await repo.siblingNameExists(
        name: '猫粮',
        type: BillType.expense,
        parentId: parentB,
      );
      expect(exists, isFalse);
    });

    test('空名不查重 → false', () async {
      final exists = await repo.siblingNameExists(
        name: '   ',
        type: BillType.expense,
        parentId: null,
      );
      expect(exists, isFalse);
    });
  });

  group('findFallbackCategory', () {
    test('预置库收支各有一条 isFallback「其他」一级分类', () async {
      final expense = await repo.findFallbackCategory(BillType.expense);
      final income = await repo.findFallbackCategory(BillType.income);
      expect(expense?.name, '其他');
      expect(expense?.parentId, isNull);
      expect(income?.name, '其他');
      expect(income?.parentId, isNull);
      // 收支互不串扰
      expect(expense?.id, isNot(income?.id));
    });

    test('用户改名后仍按 isFallback 识别（改名不失效）', () async {
      final fallback = await repo.findFallbackCategory(BillType.expense);
      final renamed = fallback!.copyWith(name: '杂项');
      await repo.updateCategory(renamed);
      final found = await repo.findFallbackCategory(BillType.expense);
      expect(found?.id, fallback.id);
    });
  });

  group('migrateAndDeleteCategory', () {
    test('账单整体改挂 + 备注追加原分类名（空备注直接写）', () async {
      final source = await addParent('奶茶', BillType.expense);
      final target = await addParent('饮品', BillType.expense);
      await addBill(source, note: '好喝');
      await addBill(source);

      await repo.migrateAndDeleteCategory(source, target);

      final bills = await (db.select(
        db.bills,
      )..where((b) => b.categoryId.equals(target))).get();
      expect(bills, hasLength(2));
      expect(
        bills.map((b) => b.note).toSet(),
        {'好喝｜原分类:奶茶', '原分类:奶茶'},
      );
      // 源分类已删除
      final cats = await db.select(db.categories).get();
      expect(cats.any((c) => c.id == source), isFalse);
    });

    test('二级分类迁移备注写"父/子"', () async {
      final parent = await addParent('水果', BillType.expense);
      final child = await addChild('苹果', parent);
      final target = await addParent('饮品', BillType.expense);
      await addBill(child, note: '红富士');

      await repo.migrateAndDeleteCategory(child, target);

      final bills = await (db.select(
        db.bills,
      )..where((b) => b.categoryId.equals(target))).get();
      expect(bills.single.note, '红富士｜原分类:水果/苹果');
    });

    test('预算按月迁移：同月并入目标行，无冲突直接改挂', () async {
      final source = await addParent('奶茶', BillType.expense);
      final target = await addParent('饮品', BillType.expense);
      await addBudget('2026-10', source, 500);
      await addBudget('2026-10', target, 300);
      await addBudget('2026-09', source, 700);

      await repo.migrateAndDeleteCategory(source, target);

      final budgets = await (db.select(
        db.budgets,
      )..where((b) => b.categoryId.equals(target))).get();
      final byMonth = {for (final b in budgets) b.month: b.amountCents};
      // 同月金额相加，规避 (month, categoryId) 唯一约束
      expect(byMonth['2026-10'], 800);
      // 无同月目标的预算直接改挂
      expect(byMonth['2026-09'], 700);
    });
  });
}
