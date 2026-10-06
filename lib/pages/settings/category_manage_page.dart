import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/show_toast.dart';
import '../../widgets/category_avatar.dart';
import '../../widgets/help_sheet.dart';
import '../../widgets/section_card.dart';
import '../stats/stats_page.dart';
import 'category_edit_page.dart';

/// 分类管理页：钱迹式分组管理
///
/// 顶栏"支出/收入"Tab 切换类型；一级分类为白卡行（单击修改、箭头展开），
/// 展开后显示浅色面板，内为 5 列子分类网格与"添加子类"入口；
/// 右下角悬浮 + 新增一级分类。长按一级或二级分类拖动即可排序。
class CategoryManagePage extends StatefulWidget {
  const CategoryManagePage({super.key});

  @override
  State<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends State<CategoryManagePage> {
  BillType _type = BillType.expense;

  /// 当前展开子分类面板的一级分类 id
  final Set<int> _expanded = {};

  /// 二级分类本地显示顺序（父分类 id → 子分类 id 列表）。
  /// 拖动"挤占"时立即本地重排并刷新，不等数据库回流，
  /// 与一级 ReorderableListView 的实时让位手感一致
  final Map<int, List<int>> _subOrderIds = {};

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CategoryProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in BillType.values)
              _TopTab(
                label: t.label,
                selected: _type == t,
                onTap: () {
                  if (_type == t) return;
                  setState(() {
                    _type = t;
                    _expanded.clear();
                  });
                },
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 24),
            color: AppColors.textSecondary,
            onPressed: _showHelp,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, size: 28, color: Colors.white),
        // 右下角 +：新增一级分类（归属由入口决定，与钱迹一致）
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CategoryEditPage(type: _type),
          ),
        ),
      ),
      body: Column(
        children: [
          // 操作提示条
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '长按一级或者二级分类拖动可进行排序，单击可修改',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Category>>(
              stream: provider.categoriesStream(_type),
              builder: (context, snapshot) {
                final categories = snapshot.data ?? const <Category>[];
                final parents = categories
                    .where((c) => c.parentId == null)
                    .toList();
                final subsMap = <int, List<Category>>{};
                for (final c in categories) {
                  final pid = c.parentId;
                  if (pid != null) (subsMap[pid] ??= []).add(c);
                }
                if (parents.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.category_outlined,
                          size: 56,
                          color: AppColors.textSecondary.withValues(
                            alpha: 0.45,
                          ),
                        ),
                        const SizedBox(height: AppDimens.gapSm),
                        const Text(
                          '暂无分类，点击右下角 + 新增',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pagePadding,
                    AppDimens.gapSm,
                    AppDimens.pagePadding,
                    88,
                  ),
                  // 长按卡片直接拖动排序（钱迹式），拖起时加投影
                  proxyDecorator: (child, index, animation) => Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(AppDimens.radiusCard),
                    child: child,
                  ),
                  // onReorderItem 的 newIndex 已自动修正移除位偏移
                  onReorderItem: (oldIndex, newIndex) {
                    final ids = parents.map((c) => c.id).toList();
                    final id = ids.removeAt(oldIndex);
                    ids.insert(newIndex, id);
                    provider.reorderCategories(ids);
                  },
                  itemCount: parents.length,
                  itemBuilder: (context, index) {
                    final parent = parents[index];
                    final subs = _orderedSubs(
                      subsMap[parent.id] ?? const <Category>[],
                    );
                    final expanded = _expanded.contains(parent.id);
                    return Padding(
                      key: ValueKey(parent.id),
                      // 卡片行之间的间隔
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ParentCard(
                        category: parent,
                        expanded: expanded,
                        subs: subs,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                CategoryEditPage(type: _type, category: parent),
                          ),
                        ),
                        onToggle: () => setState(() {
                          expanded
                              ? _expanded.remove(parent.id)
                              : _expanded.add(parent.id);
                        }),
                        // 行内 ··· 操作菜单（修改/删除/改为二级/统计）
                        onMore: () => _showActionMenu(parent),
                        // 二级单击图标/名称直接弹操作菜单（钱迹式）
                        onSubTap: _showActionMenu,
                        // 二级分类拖动排序：松手后按最终顺序一次性写库
                        onSubReorder: (ids) {
                          setState(() => _subOrderIds[parent.id] = ids);
                          provider.reorderCategories(ids);
                        },
                        onAddSub: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                CategoryEditPage(type: _type, parent: parent),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 按本地拖动顺序排列子分类：
  /// 有本地顺序用本地，数据库新增的子分类追加在末尾兜底
  List<Category> _orderedSubs(List<Category> subs) {
    if (subs.isEmpty) return subs;
    final ids = _subOrderIds[subs.first.parentId];
    if (ids == null) return subs;
    final map = {for (final c in subs) c.id: c};
    return [
      for (final id in ids)
        if (map[id] != null) map[id]!,
      ...subs.where((c) => !ids.contains(c.id)),
    ];
  }

  /// 帮助说明：底部弹出面板（图标化要点，替代系统默认弹窗）
  void _showHelp() {
    HelpSheet.show(
      context,
      title: '分类管理说明',
      items: [
        HelpSheetItem(
          icon: Icons.touch_app_outlined,
          title: '单击修改',
          description: '单击一级分类或子分类，可修改名称与图标',
        ),
        HelpSheetItem(
          icon: Icons.drag_indicator,
          title: '长按排序',
          description: '长按一级或二级分类拖动，可直接调整排序',
        ),
        HelpSheetItem(
          icon: Icons.unfold_more,
          title: '展开/收起',
          description: '点击一级分类右侧箭头，展开或收起子分类',
        ),
        HelpSheetItem(
          icon: Icons.add_circle_outline,
          title: '新增分类',
          description: '面板内"添加子类"可为该一级分类新增子分类；右下角 + 新增一级分类，支持批量添加',
        ),
        HelpSheetItem(
          icon: Icons.delete_outline,
          title: '删除连带',
          description: '删除分类会连带删除其子分类下的账单',
        ),
      ],
    );
  }

  // ---------- 行内 ··· 操作菜单 ----------

  /// 打开编辑页：二级分类需同时传入所属一级分类
  ///（编辑页"一级分类"只读行显示用，否则空指针报错）
  Future<void> _openEdit(Category category) async {
    Category? parent;
    if (category.parentId != null) {
      final provider = context.read<CategoryProvider>();
      final all = await provider.categoriesStream(_type).first;
      for (final c in all) {
        if (c.id == category.parentId) {
          parent = c;
          break;
        }
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CategoryEditPage(type: _type, category: category, parent: parent),
      ),
    );
  }

  /// 分类操作菜单（钱迹式居中弹窗：修改/删除/改为二级分类/查看统计数据）
  void _showActionMenu(Category category) {
    final provider = context.read<CategoryProvider>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
        title: const Text(
          '操作',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _actionItem(ctx, '修改', () {
              Navigator.pop(ctx);
              _openEdit(category);
            }),
            _actionItem(ctx, '删除', () {
              Navigator.pop(ctx);
              _confirmDelete(provider, category);
            }),
            // 归属调整：一级可降级为二级；二级可升级或移动到其它一级
            if (category.parentId == null)
              _actionItem(ctx, '改为二级分类', () {
                Navigator.pop(ctx);
                _changeToSub(category);
              })
            else ...[
              _actionItem(ctx, '改为一级分类', () {
                Navigator.pop(ctx);
                _changeToParent(category);
              }),
              _actionItem(ctx, '移动到其它一级分类', () {
                Navigator.pop(ctx);
                _moveToOtherParent(category);
              }),
            ],
            _actionItem(ctx, '查看统计数据', () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StatsPage(initialCategory: category),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 操作菜单文字项（左对齐、大间距，钱迹样式）
  Widget _actionItem(BuildContext ctx, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// 弹窗选择一个所属一级分类（[excludeId] 从候选中排除）
  Future<Category?> _pickParent(CategoryProvider provider, {int? excludeId}) {
    return showDialog<Category>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择所属一级分类'),
        children: [
          // 候选为当前类型下的一级分类（Stream 快照足够新，选择后即校验写入）
          StreamBuilder<List<Category>>(
            stream: provider.categoriesStream(_type),
            builder: (context, snapshot) {
              final parents = (snapshot.data ?? const <Category>[])
                  .where((c) => c.parentId == null && c.id != excludeId)
                  .toList();
              return Column(
                children: [
                  for (final p in parents)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, p),
                      child: Text(p.name),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 将分类移动为某个一级分类的二级分类（排到目标子级末尾）
  ///
  /// 覆盖"改为二级分类"（一级降级）与"移动到其它一级分类"两个入口，
  /// 落位前查目标父下的兄弟重名，重名拒绝并提示
  Future<void> _moveToParentSub(
    CategoryProvider provider,
    Category category,
  ) async {
    final target = await _pickParent(provider, excludeId: category.id);
    if (target == null || !mounted) return;
    final dup = await provider.siblingNameExists(
      name: category.name,
      type: _type,
      parentId: target.id,
      excludeId: category.id,
    );
    if (!mounted) return;
    if (dup) {
      showAppToast(context, '"${target.name}"下已存在同名分类"${category.name}"');
      return;
    }
    final all = await provider.categoriesStream(_type).first;
    if (!mounted) return;
    final subCount = all.where((c) => c.parentId == target.id).length;
    await provider.updateCategory(
      category.copyWith(parentId: Value(target.id), sortOrder: subCount),
    );
  }

  /// 将一级分类降级为二级分类
  ///
  /// 已有子分类的一级不允许降级（否则其子分类将形成三级结构）。
  Future<void> _changeToSub(Category parent) async {
    final provider = context.read<CategoryProvider>();
    final all = await provider.categoriesStream(_type).first;
    if (!mounted) return;
    if (all.any((c) => c.parentId == parent.id)) {
      showAppToast(context, '该分类下存在子分类，请先处理子分类后再改为二级分类');
      return;
    }
    await _moveToParentSub(provider, parent);
  }

  /// 将二级分类升级为一级分类（排到一级末尾）
  Future<void> _changeToParent(Category sub) async {
    final provider = context.read<CategoryProvider>();
    try {
      debugPrint(
        '[分类] 升级开始: id=${sub.id} name=${sub.name} '
        'parentId=${sub.parentId} type=${sub.type}',
      );
      final all = await provider.categoriesStream(_type).first;
      if (!mounted) return;
      // 升级落位 0 级：查同 type 全部一级的兄弟重名（排除自己）
      final dup = await provider.siblingNameExists(
        name: sub.name,
        type: _type,
        parentId: null,
        excludeId: sub.id,
      );
      if (!mounted) return;
      if (dup) {
        showAppToast(context, '已存在同名一级分类"${sub.name}"');
        return;
      }
      final parentCount = all.where((c) => c.parentId == null).length;
      final updated = sub.copyWith(
        parentId: const Value(null),
        sortOrder: parentCount,
      );
      debugPrint(
        '[分类] 升级写入: parentId=${updated.parentId} '
        'sortOrder=${updated.sortOrder}',
      );
      final rows = await provider.updateCategoryCounted(updated);
      debugPrint('[分类] 升级完成，受影响行数: $rows');
      if (!mounted) return;
      showAppToast(
        context,
        rows > 0 ? '已将"${sub.name}"改为一级分类' : '未找到该分类（id=${sub.id}），写入 0 行',
      );
    } catch (e) {
      debugPrint('[分类] 升级失败: $e');
      if (mounted) {
        showAppToast(context, '操作失败: $e');
      }
    }
  }

  /// 将二级分类移动到其它一级分类下
  Future<void> _moveToOtherParent(Category sub) async {
    final provider = context.read<CategoryProvider>();
    await _moveToParentSub(provider, sub);
  }

  /// 删除分类（该分类及其子分类下的账单一并删除，需用户确认）
  Future<void> _confirmDelete(
    CategoryProvider provider,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('删除"${category.name}"后，该分类及其子分类下的账单也会一并删除，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await provider.deleteCategoryWithBills(category.id);
    }
  }
}

/// 顶栏类型 Tab：文字 + 选中态主色下划线（与记一笔页顶栏一致）
class _TopTab extends StatelessWidget {
  const _TopTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      // 去掉方形水波，反馈只靠下划线
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                height: 1.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            // 选中态主色下划线
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 2,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一级分类白卡行：方形圆角图标 + 名称 + ··· 操作 + 箭头展开
///
/// 无子分类时同样可展开面板，面板内提供"添加子类"入口。
/// 长按整行由 ReorderableListView 接管进行拖动排序。
class _ParentCard extends StatelessWidget {
  const _ParentCard({
    required this.category,
    required this.expanded,
    required this.subs,
    required this.onTap,
    required this.onToggle,
    required this.onMore,
    required this.onSubTap,
    required this.onSubReorder,
    required this.onAddSub,
  });

  final Category category;
  final bool expanded;

  /// 该一级分类下的子分类（展开时嵌在卡片内部显示）
  final List<Category> subs;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  /// 行内 ··· 操作菜单（修改/删除/改为二级/统计）
  final VoidCallback onMore;

  /// 子分类交互：单击弹菜单、拖入排序、添加子类
  final ValueChanged<Category> onSubTap;

  /// 二级拖动松手落位：传最终顺序的全量 id 序列
  final ValueChanged<List<int>> onSubReorder;
  final VoidCallback onAddSub;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    // 圆形彩色头像：与记一笔页分类格子一致，文字图标显首字
                    CategoryAvatar(
                      name: category.name,
                      iconCode: category.iconCode,
                      color: category.colorValue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // 行右侧：··· 操作 ｜ 展开/收起箭头（钱迹式 ··· >）
                    InkWell(
                      onTap: onMore,
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.more_horiz,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onToggle,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 24,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 展开的子分类面板：嵌在卡片内部（浅色圆角面板 + 5 列网格）
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _SubPanel(
                  subs: subs,
                  onSubTap: onSubTap,
                  onReorder: onSubReorder,
                  onAddSub: onAddSub,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 子分类面板：浅色圆角底 + 5 列网格（子分类 + 添加子类）
///
/// 排序手感与一级分类（ReorderableListView）对齐：长按拿起后原格
/// 消失，空隙跟随手指在格位间连续移动，其它格子 150ms 滑动让位，
/// 松手落位一次性写库。GridView 原生不支持位置动画，因此改用
/// Stack + AnimatedPositioned 显式布局实现。
class _SubPanel extends StatefulWidget {
  const _SubPanel({
    required this.subs,
    required this.onSubTap,
    required this.onReorder,
    required this.onAddSub,
  });

  /// 数据库当前顺序（页面已按本地排序兜底合并后的完整兄弟序列）
  final List<Category> subs;
  final ValueChanged<Category> onSubTap;

  /// 松手落位回调：传最终顺序的全量 id 序列
  final ValueChanged<List<int>> onReorder;
  final VoidCallback onAddSub;

  @override
  State<_SubPanel> createState() => _SubPanelState();
}

class _SubPanelState extends State<_SubPanel> {
  static const int _columns = 5;

  /// 列距/行距（与旧 GridView crossAxisSpacing/mainAxisSpacing 一致）
  static const double _gapX = 4;
  static const double _gapY = 10;

  /// 本地显示顺序（含被拖项；渲染时被拖项原格隐藏，其 slot 即"空隙"）
  late List<Category> _order;

  /// 正在拖动的分类（null = 未拖动）
  Category? _dragging;

  /// 拖动结束已提交写库、等待数据库流确认期间为 true：
  /// 防止父组件重建用旧数据库顺序覆盖本地新顺序导致回跳
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _order = List.of(widget.subs);
  }

  @override
  void didUpdateWidget(covariant _SubPanel old) {
    super.didUpdateWidget(old);
    final dbIds = widget.subs.map((c) => c.id).toSet();
    if (_dragging != null) {
      // 拖动中：只合并新增/删除，不打乱正在拖动的顺序
      _order.removeWhere((c) => !dbIds.contains(c.id));
      for (final c in widget.subs) {
        if (!_order.any((e) => e.id == c.id)) _order.add(c);
      }
    } else if (_pending) {
      // 数据库流已确认与本地顺序一致时解除写库保护
      final localIds = _order.map((c) => c.id).toList();
      final dbIdList = widget.subs.map((c) => c.id).toList();
      var same = localIds.length == dbIdList.length;
      if (same) {
        for (var i = 0; i < localIds.length; i++) {
          if (localIds[i] != dbIdList[i]) {
            same = false;
            break;
          }
        }
      }
      if (same) _pending = false;
    } else {
      _order = List.of(widget.subs);
    }
  }

  /// 松手落位：按最终显示顺序一次性写库（与一级 onReorder 同节奏）
  void _endDrag() {
    if (_dragging == null) return;
    final ids = _order.map((c) => c.id).toList();
    _dragging = null;
    _pending = true;
    setState(() {});
    widget.onReorder(ids);
  }

  /// 指针全局坐标 → 目标格位（越界 clamp 到网格内）：
  /// 与被拖项当前位置不同则重排，空隙随手指连续移动
  void _onPointerMove(Offset global, double cellW, double cellH) {
    if (_dragging == null) return;
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(global);
    final col = ((local.dx + _gapX / 2) / (cellW + _gapX)).floor().clamp(
      0,
      _columns - 1,
    );
    final maxRow = (_order.length - 1) ~/ _columns;
    final row = ((local.dy + _gapY / 2) / (cellH + _gapY)).floor().clamp(
      0,
      maxRow,
    );
    var slot = row * _columns + col;
    if (slot >= _order.length) slot = _order.length - 1;
    final cur = _order.indexOf(_dragging!);
    if (slot != cur) {
      setState(() {
        final item = _order.removeAt(cur);
        _order.insert(slot, item);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _order.length + 1; // + 末尾"添加子类"
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellW =
              (constraints.maxWidth - _gapX * (_columns - 1)) / _columns;
          final cellH = cellW / 0.86; // 与旧 GridView childAspectRatio 一致
          final rows = (itemCount + _columns - 1) ~/ _columns;
          Offset posOf(int slot) => Offset(
            slot % _columns * (cellW + _gapX),
            slot ~/ _columns * (cellH + _gapY),
          );
          Widget cellFor(Category c) {
            final slot = _order.indexOf(c);
            final pos = posOf(slot);
            return AnimatedPositioned(
              key: ValueKey(c.id),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              left: pos.dx,
              top: pos.dy,
              width: cellW,
              height: cellH,
              child: LongPressDraggable<Category>(
                data: c,
                dragAnchorStrategy: childDragAnchorStrategy,
                onDragStarted: () => setState(() => _dragging = c),
                onDragUpdate: (d) =>
                    _onPointerMove(d.globalPosition, cellW, cellH),
                onDragEnd: (_) => _endDrag(),
                // 跟随手指的副本：与一级白卡拖起同款投影
                feedback: Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: cellW,
                    height: cellH,
                    child: _SubCell(sub: c, onTap: () {}),
                  ),
                ),
                // 拖动中隐藏原格：其 slot 即空隙，随手指移动
                childWhenDragging: const SizedBox.shrink(),
                child: _SubCell(sub: c, onTap: () => widget.onSubTap(c)),
              ),
            );
          }

          return SizedBox(
            height: rows * cellH + (rows - 1) * _gapY,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final c in _order) cellFor(c),
                // 加号格：固定在末位 slot，不参与拖动
                AnimatedPositioned(
                  key: const ValueKey('#add'),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  left: posOf(_order.length).dx,
                  top: posOf(_order.length).dy,
                  width: cellW,
                  height: cellH,
                  child: _AddSubCell(onTap: widget.onAddSub),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 子分类网格项：圆形彩色图标 + 名称（单击弹操作菜单）
class _SubCell extends StatelessWidget {
  const _SubCell({required this.sub, required this.onTap});

  final Category sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 圆形彩色头像：与记一笔页子分类格子一致，文字图标显首字
          CategoryAvatar(
            name: sub.name,
            iconCode: sub.iconCode,
            color: sub.colorValue,
          ),
          const SizedBox(height: 5),
          Text(
            sub.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// "添加子类"网格项：虚感弱化的 ⊕ 图标 + 文案
class _AddSubCell extends StatelessWidget {
  const _AddSubCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 24,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 5),
          Text(
            '添加子类',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
