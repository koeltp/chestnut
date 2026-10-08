import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../theme/app_colors.dart';
import '../../widgets/category_tree_selector.dart';

/// 记一笔页的分类选择区：从 add_bill_page 拆出的独立组件
///
/// 仅负责分类数据加载与选择展示；默认值兜底与选中变更通过回调交回父组件。
/// 拆分目的：分类选择逻辑自洽（仅依赖 type/categories/selectedId），
/// 独立出来减轻 add_bill_page 的单文件负担。
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.stream,
    required this.type,
    required this.selectedId,
    required this.onSelectedChanged,
    required this.onEnsureSelected,
  });

  /// 当前类型（支出/收入）的分类流
  final Stream<List<Category>> stream;

  /// 当前账单类型：决定切类型时整树重建的 key
  final BillType type;

  /// 当前选中的分类 id
  final int? selectedId;

  /// 选中变更回调
  final ValueChanged<int> onSelectedChanged;

  /// 选中分类不存在（如类型切换后）时的兜底回调：传回第一个一级 id
  ///
  /// 副作用必须留在父组件（避免在 build 期间直接改自身状态），
  /// 由父组件赋值后触发重建。
  final ValueChanged<int> onEnsureSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Category>>(
      stream: stream,
      builder: (context, snapshot) {
        // 切换收/支类型换流后的空窗显示转圈，不能把空窗当成空列表，
        // 否则会闪现"暂无分类"误导用户
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final categories = snapshot.data!;
        if (categories.isEmpty) {
          return const Center(
            child: Text(
              '暂无分类，请在"我的-分类管理"中添加',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        final parents = categories.where((c) => c.parentId == null).toList();
        if (parents.isEmpty) {
          return const Center(
            child: Text(
              '暂无一级分类，请在"我的-分类管理"中添加',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        // 选中分类不存在时（如类型切换后）回传兜底 id 给父级持久化；
        // 本帧渲染须直接用本地生效值，否则 null 传给 selector 会断言失败
        final exists = categories.any((c) => c.id == selectedId);
        if (!exists) {
          onEnsureSelected(parents.first.id);
        }
        final effectiveId = exists ? selectedId : parents.first.id;
        // 初始展开：新建/切类型展开第一个一级的二级供直接选择，省一次点击；
        // 编辑回显挂二级展开其所属组，挂一级展开自身面板
        final selectedCat = categories.firstWhere(
          (c) => c.id == effectiveId,
          orElse: () => parents.first,
        );
        final initialExpandedId = exists
            ? (selectedCat.parentId ?? selectedCat.id)
            : parents.first.id;
        return CategoryTreeSelector(
          // 切收/支类型后整树重建：展开状态随类型重置，避免残留上一类型面板
          key: ValueKey(type),
          mode: CategoryTreeMode.single,
          categories: categories,
          selectedId: effectiveId,
          initialExpandedId: initialExpandedId,
          onSingleChanged: onSelectedChanged,
        );
      },
    );
  }
}
