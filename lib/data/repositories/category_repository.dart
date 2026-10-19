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

  /// 删除分类（含全部子分类，级联）。仅当其下无账单/预算时调用；
  /// 有关联数据走 [migrateAndDeleteCategory] 迁移
  Future<void> deleteCategory(int categoryId) {
    return _db.transaction(() async {
      final subs = await (_db.select(
        _db.categories,
      )..where((c) => c.parentId.equals(categoryId))).get();
      await (_db.delete(
        _db.categories,
      )..where((c) => c.id.isIn([categoryId, ...subs.map((s) => s.id)]))).go();
    });
  }

  /// 迁移删除分类：把 [categoryId] 及其全部子分类下的账单与预算改挂到
  /// [targetCategoryId] 后删除分类记录，整体在一个事务内完成。
  /// [targetCategoryId] 须与被删分类同类型、且不在删除集合内（UI 层
  /// 保证；兜底「其他」不可删，候选恒非空）。
  ///
  /// 账单备注追加"原分类:xx"（挂二级写"父/子"，与钱迹导入口径一致），
  /// 便于迁移后追溯原归属。预算按月迁移，目标同月已有预算时金额并入
  /// 目标行（(month, categoryId) 唯一约束，直接改挂会撞 UNIQUE 异常）
  Future<void> migrateAndDeleteCategory(
    int categoryId,
    int targetCategoryId,
  ) {
    return _db.transaction(() async {
      final subs = await (_db.select(
        _db.categories,
      )..where((c) => c.parentId.equals(categoryId))).get();
      final ids = [categoryId, ...subs.map((s) => s.id)];

      // 原分类名映射（含父名，供备注追溯）：先记名再删除
      final all = await _db.select(_db.categories).get();
      final byId = {for (final c in all) c.id: c};
      for (final id in ids) {
        final c = byId[id];
        if (c == null) continue;
        final label = c.parentId == null
            ? c.name
            : '${byId[c.parentId]?.name ?? ''}/${c.name}';
        // 原备注按"｜"段拼接：空则直接写，非空追加（与导入 _buildNote 同格式）
        await _db.customUpdate(
          'UPDATE bills SET note = CASE '
          'WHEN note IS NULL OR note = \'\' THEN ? '
          'ELSE note || \'｜\' || ? END '
          'WHERE category_id = ?',
          variables: [
            Variable('原分类:$label'),
            Variable('原分类:$label'),
            Variable(id),
          ],
        );
      }

      // 账单整体改挂目标分类（删一级时其二级账单变为目标下的直挂）
      await (_db.update(_db.bills)..where((b) => b.categoryId.isIn(ids)))
          .write(BillsCompanion(categoryId: Value(targetCategoryId)));

      // 预算按月迁移：同月已有目标预算则金额并入目标行并删源行，
      // 规避 (month, categoryId) 唯一约束
      final movedBudgets = await (_db.select(
        _db.budgets,
      )..where((b) => b.categoryId.isIn(ids))).get();
      final targetBudgets = await (_db.select(_db.budgets)
            ..where((b) => b.categoryId.equals(targetCategoryId)))
          .get();
      final targetByMonth = {for (final b in targetBudgets) b.month: b};
      for (final budget in movedBudgets) {
        final existing = targetByMonth[budget.month];
        if (existing == null) {
          await (_db.update(_db.budgets)..where((b) => b.id.equals(budget.id)))
              .write(BudgetsCompanion(categoryId: Value(targetCategoryId)));
        } else {
          await (_db.update(_db.budgets)..where((b) => b.id.equals(existing.id)))
              .write(
                BudgetsCompanion(
                  amountCents: Value(existing.amountCents + budget.amountCents),
                ),
              );
          await (_db.delete(_db.budgets)..where((b) => b.id.equals(budget.id)))
              .go();
        }
      }

      await (_db.delete(_db.categories)..where((c) => c.id.isIn(ids))).go();
    });
  }

  /// 当前类型的兜底分类（收支各一条「其他」，isFallback 标记识别，
  /// 用户改名不失效）；理论恒非空——该分类禁删且 v13 迁移已补种
  Future<Category?> findFallbackCategory(BillType type) {
    return (_db.select(_db.categories)
          ..where((c) => c.type.equalsValue(type))
          ..where((c) => c.isFallback.equals(true))
          ..where((c) => c.parentId.isNull()))
        .getSingleOrNull();
  }

  /// 统计一组分类 id（自身+子分类集合）下的预算条数，
  /// 供删除分类的确认弹窗提示影响范围
  Future<int> countBudgetsInCategories(List<int> categoryIds) async {
    if (categoryIds.isEmpty) return 0;
    final count = _db.budgets.id.count();
    final query = _db.selectOnly(_db.budgets)
      ..addColumns([count])
      ..where(_db.budgets.categoryId.isIn(categoryIds));
    return query.map((r) => r.read(count) ?? 0).getSingle();
  }
}
