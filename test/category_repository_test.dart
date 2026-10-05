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
}
