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

  /// 新增分类
  Future<void> addCategory(CategoriesCompanion entry) =>
      _repo.addCategory(entry);

  /// 更新分类
  Future<void> updateCategory(Category category) =>
      _repo.updateCategory(category);

  /// 删除分类（其下账单一并删除，UI 层负责确认）
  Future<void> deleteCategoryWithBills(int categoryId) =>
      _repo.deleteCategoryWithBills(categoryId);

  /// 拖动排序：按同层新顺序批量写入
  Future<void> reorderCategories(List<int> orderedIds) =>
      _repo.reorderCategories(orderedIds);
}
