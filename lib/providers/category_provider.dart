import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositories/category_repository.dart';
import '../models/enums.dart';

/// 分类状态管理
///
/// 提供按类型查看分类的数据流，以及分类的增删改入口。
class CategoryProvider extends ChangeNotifier {
  CategoryProvider(this._repo);

  final CategoryRepository _repo;

  /// 指定类型的分类流（记一笔页 / 分类管理页共用）
  Stream<List<Category>> categoriesStream(BillType type) =>
      _repo.watchCategories(type);

  /// 全部分类的 id 映射流（首页账单条目渲染用）
  Stream<Map<int, Category>> categoriesMapStream() =>
      _repo.watchAllCategories().map((list) => {for (final c in list) c.id: c});

  /// 兄弟重名检查：同层下是否已有同名分类（0 级 = 收/支，
  /// 一级查同 type 全部一级，二级查同一父下的全部二级）
  Future<bool> siblingNameExists({
    required String name,
    required BillType type,
    required int? parentId,
    int? excludeId,
  }) => _repo.siblingNameExists(
    name: name,
    type: type,
    parentId: parentId,
    excludeId: excludeId,
  );

  /// 新增分类
  Future<void> addCategory(CategoriesCompanion entry) =>
      _repo.addCategory(entry);

  /// 更新分类
  Future<void> updateCategory(Category category) =>
      _repo.updateCategory(category);

  /// 更新分类并返回受影响行数（0 行 = 未匹配到记录，便于 UI 诊断）
  Future<int> updateCategoryCounted(Category category) =>
      _repo.updateCategory(category);

  /// 删除分类（含子分类级联，UI 层保证其下无账单/预算）
  Future<void> deleteCategory(int categoryId) =>
      _repo.deleteCategory(categoryId);

  /// 迁移删除分类：账单与预算改挂到承接分类后删除（承接候选恒非空：
  /// 兜底「其他」禁删；UI 层负责确认与承接选择）
  Future<void> migrateAndDeleteCategory(int categoryId, int targetId) =>
      _repo.migrateAndDeleteCategory(categoryId, targetId);

  /// 当前类型的兜底分类「其他」（删除迁移的默认承接；理论恒非空）
  Future<Category?> findFallbackCategory(BillType type) =>
      _repo.findFallbackCategory(type);

  /// 统计一组分类 id（自身+子分类）下的账单总数（删除确认弹窗用）
  Future<int> countBillsInCategories(List<int> categoryIds) =>
      _repo.countBillsInCategories(categoryIds);

  /// 统计一组分类 id 下的预算条数（删除确认弹窗用）
  Future<int> countBudgetsInCategories(List<int> categoryIds) =>
      _repo.countBudgetsInCategories(categoryIds);

  /// 拖动排序：按同层新顺序批量写入
  Future<void> reorderCategories(List<int> orderedIds) =>
      _repo.reorderCategories(orderedIds);
}
