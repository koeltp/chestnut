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

  /// 兄弟重名检查：同层下是否已有同名分类
  ///
  /// 层级口径（0 级 = 收/支类型）：一级分类查"同 type 的全部一级"，
  /// 二级分类查"同一父分类下的全部二级"；不同 0 级/不同父下允许重名。
  /// [excludeId] 编辑改名时排除自身。名字 trim + 转小写比较（首尾空格
  /// 与英文大小写不算差异，与搜索关键词口径一致）。分类总量很小，
  /// 取兄弟集合内存过滤即可，无需 SQL lower()。
  Future<bool> siblingNameExists({
    required String name,
    required BillType type,
    required int? parentId,
    int? excludeId,
  }) async {
    final norm = name.trim().toLowerCase();
    if (norm.isEmpty) return false;
    final query = _db.select(_db.categories)
      ..where((c) => c.type.equalsValue(type));
    if (parentId == null) {
      query.where((c) => c.parentId.isNull());
    } else {
      query.where((c) => c.parentId.equals(parentId));
    }
    final siblings = await query.get();
    return siblings.any(
      (c) => c.id != excludeId && c.name.trim().toLowerCase() == norm,
    );
  }

  /// 新增分类
  Future<int> addCategory(CategoriesCompanion entry) =>
      _db.into(_db.categories).insert(entry);

  /// 更新分类（返回受影响行数）
  ///
  /// 必须用显式 Companion 而非直接 write(category)：drift 的
  /// DataClass.toCompanion(true) 会把 null 字段转为 absent（UPDATE SET
  /// 不含该列），导致"改为一级分类"（parent_id 置 NULL）静默失效
  Future<int> updateCategory(Category category) =>
      (_db.update(
        _db.categories,
      )..where((c) => c.id.equals(category.id))).write(
        CategoriesCompanion(
          name: Value(category.name),
          iconCode: Value(category.iconCode),
          colorValue: Value(category.colorValue),
          type: Value(category.type),
          parentId: Value(category.parentId),
          sortOrder: Value(category.sortOrder),
        ),
      );

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

  /// 统计一组分类 id（自身+子分类集合）下的账单总数，
  /// 供删除分类的确认弹窗提示影响范围
  Future<int> countBillsInCategories(List<int> categoryIds) async {
    if (categoryIds.isEmpty) return 0;
    final count = _db.bills.id.count();
    final query = _db.selectOnly(_db.bills)
      ..addColumns([count])
      ..where(_db.bills.categoryId.isIn(categoryIds));
    return query.map((r) => r.read(count) ?? 0).getSingle();
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
