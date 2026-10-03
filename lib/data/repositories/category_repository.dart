import 'package:drift/drift.dart';

import '../database.dart';
import '../../models/enums.dart';

/// 分类仓储：分类的增删改查
class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  /// 按账单类型监听分类列表（排序权重升序）
  Stream<List<Category>> watchCategories(BillType type) {
    return (_db.select(_db.categories)
          ..where((c) => c.type.equalsValue(type))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .watch();
  }

  /// 全部分类流（不分类型），首页账单条目据此渲染分类名与图标
  Stream<List<Category>> watchAllCategories() {
    return (_db.select(
      _db.categories,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).watch();
  }

  /// 新增分类
  Future<int> addCategory(CategoriesCompanion entry) =>
      _db.into(_db.categories).insert(entry);

  /// 更新分类（返回受影响行数）
  Future<int> updateCategory(Category category) => (_db.update(
    _db.categories,
  )..where((c) => c.id.equals(category.id))).write(category);

  /// 拖动排序：按 UI 传入的同层新顺序批量写入 sortOrder
  ///
  /// 传入的 id 列表必须是同一类型、同一父分类下的完整兄弟序列
  ///（一级分类父为 null），事务内按索引重排保证一致性。
  Future<void> reorderCategories(List<int> orderedIds) {
    return _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.categories)
              ..where((c) => c.id.equals(orderedIds[i])))
            .write(CategoriesCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// 删除分类
  ///
  /// 该分类及其全部子分类下的账单一并删除（调用方须在 UI 层向用户确认），
  /// 否则会留下"孤儿账单"导致统计异常。
  Future<void> deleteCategoryWithBills(int categoryId) {
    return _db.transaction(() async {
      // 先取子分类 id，构成"自身 + 子分类"的待删除集合
      final subs = await (_db.select(
        _db.categories,
      )..where((c) => c.parentId.equals(categoryId))).get();
      final ids = [categoryId, for (final s in subs) s.id];
      await (_db.delete(_db.bills)..where((b) => b.categoryId.isIn(ids))).go();
      await (_db.delete(_db.categories)..where((c) => c.id.isIn(ids))).go();
    });
  }
}
