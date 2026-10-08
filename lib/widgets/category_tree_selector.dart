import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'category_avatar.dart';

/// 分类树选择模式
enum CategoryTreeMode {
  /// 单选（记一笔/编辑页）：账单最终挂在一个分类上，可挂一级本身
  single,

  /// 多选（统计筛选）：选中集合可包含一级与二级
  multi,
}

/// 分类树选择器：记一笔单选与统计筛选多选共用的唯一组件
///
/// 两种模式各用最合适的形态：
/// - 单选（圆形格子）：一级每行 5 个，二级面板插在所属行下方；点一级
///   = 挂一级本身并展开（不预选二级）；点二级选中；再点当前已选二级
///   = 取消、挂回一级
/// - 多选（行式树）：点一级行只展开/收起（选中集合不变），右侧独立
///   三态复选框管整组全选/清空；二级行整行可点、只勾自己。浏览热区
///   与修改热区物理分离，避免"回来看看选了什么"意外变成整组全选
class CategoryTreeSelector extends StatefulWidget {
  const CategoryTreeSelector({
    super.key,
    required this.categories,
    required this.mode,
    this.selectedId,
    this.selectedIds,
    this.initialExpandedId,
    this.onSingleChanged,
    this.onMultiChanged,
  }) : assert(mode == CategoryTreeMode.single
            ? selectedId != null && onSingleChanged != null
            : selectedIds != null && onMultiChanged != null);

  /// 当前收支类型下的全部分类（一级 + 二级）
  final List<Category> categories;

  final CategoryTreeMode mode;

  /// 单选：当前选中分类 id
  final int? selectedId;

  /// 多选：当前选中分类 id 集合
  final Set<int>? selectedIds;

  /// 初始展开的一级 id（单选新建传第一个一级；编辑回显传选中二级所在组；
  /// 多选可传第一个有选中项的组，不传则全部收起）
  final int? initialExpandedId;

  /// 单选变化回调
  final ValueChanged<int>? onSingleChanged;

  /// 多选变化回调
  final ValueChanged<Set<int>>? onMultiChanged;

  @override
  State<CategoryTreeSelector> createState() => _CategoryTreeSelectorState();
}

class _CategoryTreeSelectorState extends State<CategoryTreeSelector> {
  /// 当前展开二级区域的一级 id
  int? _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpandedId;
  }

  List<Category> get _roots =>
      widget.categories.where((c) => c.parentId == null).toList();

  List<Category> _subsOf(int rootId) =>
      widget.categories.where((c) => c.parentId == rootId).toList();

  bool get _isSingle => widget.mode == CategoryTreeMode.single;

  // ---------- 单选交互 ----------

  /// 点一级：挂一级本身并展开（不预选二级）
  void _onSingleRootTap(Category root) {
    setState(() => _expanded = root.id);
    widget.onSingleChanged!(root.id);
  }

  /// 点二级：点当前已选的二级 = 取消、挂回一级；否则切换到该二级
  void _onSingleSubTap(Category root, Category sub) {
    setState(() => _expanded = root.id);
    final next = widget.selectedId == sub.id ? root.id : sub.id;
    widget.onSingleChanged!(next);
  }

  // ---------- 多选交互 ----------

  /// 点一级行：只展开/收起，选中集合一个都不改——
  /// 浏览已有选择是高频动作，绝不能顺手改掉选择
  void _toggleExpand(int rootId) {
    setState(() => _expanded = _expanded == rootId ? null : rootId);
  }

  /// 点一级复选框：非全选（空/部分）→ 整组全选；全选 → 整组清空
  void _onMultiRootCheck(Category root) {
    setState(() {
      final ids = [root.id, ..._subsOf(root.id).map((c) => c.id)];
      final selected = widget.selectedIds!;
      if (_multiRootState(root) == _RootBadge.full) {
        selected.removeAll(ids);
      } else {
        selected.addAll(ids);
      }
    });
    widget.onMultiChanged!(Set<int>.from(widget.selectedIds!));
  }

  /// 点二级行/复选框：单独勾选/取消
  void _onMultiSubTap(Category sub) {
    setState(() {
      final selected = widget.selectedIds!;
      selected.contains(sub.id)
          ? selected.remove(sub.id)
          : selected.add(sub.id);
    });
    widget.onMultiChanged!(Set<int>.from(widget.selectedIds!));
  }

  /// 一级整组选中态：full 整组全选 / partial 只选了部分 / none 全未选
  _RootBadge _multiRootState(Category root) {
    final ids = [root.id, ..._subsOf(root.id).map((c) => c.id)];
    final picked = ids.where(widget.selectedIds!.contains).length;
    if (picked == 0) return _RootBadge.none;
    return picked == ids.length ? _RootBadge.full : _RootBadge.partial;
  }

  // ---------- 布局 ----------

  @override
  Widget build(BuildContext context) {
    return _isSingle ? _buildSingleGrid() : _buildMultiTree();
  }

  /// 单选：5 列圆形格子，二级面板插入对应一级行之后
  Widget _buildSingleGrid() {
    final roots = _roots;
    final rows = <List<Category>>[
      for (var i = 0; i < roots.length; i += 5)
        roots.sublist(i, (i + 5 > roots.length) ? roots.length : i + 5),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        for (final row in rows) ...[
          _buildRootRow(row),
          if (_expanded != null &&
              row.any((r) => r.id == _expanded) &&
              // 无二级的一级不渲染空面板（无子直接选中即可）
              _subsOf(_expanded!).isNotEmpty)
            _buildSubPanel(
              root: row.firstWhere((r) => r.id == _expanded),
              subs: _subsOf(_expanded!),
              column: row.indexWhere((r) => r.id == _expanded),
            ),
        ],
      ],
    );
  }

  /// 一级行：5 等分格子，不足补空
  Widget _buildRootRow(List<Category> row) {
    return Row(
      children: [
        for (final root in row) _buildRootCell(root),
        for (var i = row.length; i < 5; i++) const Expanded(child: SizedBox()),
      ],
    );
  }

  /// 单个一级格：实底=选中该一级本身，或选中了其下任意子类（标明账单
  /// 所在组，避免选了"早餐"后"餐饮"退回未选底色）
  Widget _buildRootCell(Category root) {
    return Expanded(
      child: _RootCell(
        category: root,
        filled: widget.selectedId == root.id ||
            _subsOf(root.id).any((s) => s.id == widget.selectedId),
        onTap: () => _onSingleRootTap(root),
      ),
    );
  }

  /// 单选二级面板：三角箭头对准所属一级 + 浅底圆角 5 列网格
  Widget _buildSubPanel({
    required Category root,
    required List<Category> subs,
    required int column,
  }) {
    // 三角形中心对齐第 column 列中点，映射到 Alignment.x（-1 ~ 1）
    final arrowX = (column * 2 + 1) / 5 - 1;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment(arrowX, -1),
            child: CustomPaint(size: const Size(14, 6), painter: _TrianglePainter()),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 0.82,
            ),
            itemCount: subs.length,
            itemBuilder: (context, index) {
              final sub = subs[index];
              return _SubCell(
                category: sub,
                selected: widget.selectedId == sub.id,
                onTap: () => _onSingleSubTap(root, sub),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 多选：行式树。root 行只管展开，复选框独立；无子 root 点行即勾选
  Widget _buildMultiTree() {
    final roots = _roots;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: roots.length,
      itemBuilder: (context, i) {
        final root = roots[i];
        final subs = _subsOf(root.id);
        final expanded = _expanded == root.id;
        return Column(
          children: [
            _buildMultiRootRow(root, subs, expanded),
            if (expanded && subs.isNotEmpty)
              ...subs.map(_buildMultiSubRow),
            if (i < roots.length - 1)
              const Divider(
                height: 1,
                thickness: 0.5,
                indent: 12,
                endIndent: 12,
              ),
          ],
        );
      },
    );
  }

  /// 多选一级行：[箭头] 头像 名称 …… [三态复选框]
  Widget _buildMultiRootRow(
    Category root,
    List<Category> subs,
    bool expanded,
  ) {
    final hasSubs = subs.isNotEmpty;
    return InkWell(
      // 有子=只展开；无子=行本身就是勾选动作（没有可展开内容）
      onTap: () =>
          hasSubs ? _toggleExpand(root.id) : _onMultiRootCheck(root),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: 12),
            SizedBox(
              width: 30,
              child: hasSubs
                  ? Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      size: 22,
                      color: AppColors.textSecondary,
                    )
                  : null,
            ),
            CategoryAvatar(
              name: root.name,
              iconCode: root.iconCode,
              color: root.colorValue,
              size: 30,
              iconSize: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                root.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            // 独立复选框：手势在子节点竞技场胜出，不触发行的展开
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onMultiRootCheck(root),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _TriCheckbox(state: _multiRootState(root)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 多选二级行：左侧与一级头像对齐，整行可点（只勾自己一个）
  Widget _buildMultiSubRow(Category sub) {
    final picked = widget.selectedIds!.contains(sub.id);
    return InkWell(
      onTap: () => _onMultiSubTap(sub),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            const SizedBox(width: 52),
            CategoryAvatar(
              name: sub.name,
              iconCode: sub.iconCode,
              color: sub.colorValue,
              size: 26,
              iconSize: 14,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sub.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onMultiSubTap(sub),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _TriCheckbox(
                  state: picked ? _RootBadge.full : _RootBadge.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 整组选中态：none 无 / full 全选 / partial 部分
enum _RootBadge { none, full, partial }

/// 三态复选框：空框 / 主色底白横杠 / 主色底白对勾
class _TriCheckbox extends StatelessWidget {
  const _TriCheckbox({required this.state});

  final _RootBadge state;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: state == _RootBadge.none
            ? Colors.transparent
            : AppColors.primary,
        borderRadius: BorderRadius.circular(5),
        border: state == _RootBadge.none
            ? Border.all(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                width: 1.5,
              )
            : null,
      ),
      child: state == _RootBadge.none
          ? null
          : Icon(
              state == _RootBadge.full ? Icons.check : Icons.remove,
              size: 14,
              color: Colors.white,
            ),
    );
  }
}

/// 一级分类格子：40 圆头像 + 名称（仅单选形态使用）
class _RootCell extends StatelessWidget {
  const _RootCell({
    required this.category,
    required this.filled,
    required this.onTap,
  });

  final Category category;

  /// 是否实底（选中该一级 / 选中了其下子类）
  final bool filled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return InkWell(
      onTap: onTap,
      // 反馈只由头像底色 150ms 渐变承担，禁方形水波/高亮
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? color : color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: _Glyph(
                category: category,
                color: filled ? Colors.white : color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1,
                color: filled ? color : AppColors.textPrimary,
                fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级分类格子：40 圆头像 + 名称（仅单选形态使用）
class _SubCell extends StatelessWidget {
  const _SubCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: _Glyph(
              category: category,
              color: selected ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: selected ? color : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆头像内图形：文字图标显示首字，否则 Material 图标（仅单选格子使用）
class _Glyph extends StatelessWidget {
  const _Glyph({required this.category, required this.color});

  final Category category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (category.iconCode == kTextIconCode) {
      return Text(
        category.name.isEmpty ? '?' : category.name.characters.first,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 21,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Icon(
      // 码点存库动态读取非 const，发布构建需 --no-tree-shake-icons
      // ignore: non_const_argument_for_const_parameter
      IconData(category.iconCode, fontFamily: 'MaterialIcons'),
      color: color,
      size: 21,
    );
  }
}

/// 单选面板顶部三角指示器：与面板同色（AppColors.fill），
/// 营造"气泡指向所属一级分类"的效果
class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.fill;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
