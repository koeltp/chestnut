import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/show_toast.dart';
import '../../widgets/color_palette_picker.dart';
import '../stats/stats_page.dart';

/// 标签管理页：从"我的"页或标签选择弹层的"管理"按钮进入
///
/// 功能：查看全部标签、编辑（名称+颜色）、删除（级联解除账单关联，需确认）、
/// 长按拖动排序（与分类管理页二级分类同款手感：拿起让位、松手落库）。
/// 标签是跨分类的场景维度，删除不影响账单本身，仅解除关联。
class TagManagePage extends StatefulWidget {
  const TagManagePage({super.key});

  @override
  State<TagManagePage> createState() => _TagManagePageState();
}

class _TagManagePageState extends State<TagManagePage> {
  List<Tag> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final tags = await context.read<TagRepository>().getTags();
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _loading = false;
    });
  }

  /// 标签编辑/新建共用弹窗：名称输入 + 20 色色板。
  ///
  /// [existing] 非空 = 编辑（预填名称与颜色），为空 = 新建（默认首色）。
  /// 返回 (name, color)，用户取消返回 null。
  Future<({String name, int color})?> _showTagDialog({Tag? existing}) async {
    final controller = TextEditingController(text: existing?.name);
    var pickedColor = existing?.color ?? AppColors.tagPalette.first;
    // StatefulBuilder：色板点击即时刷新选中态，无需关闭弹窗
    return showDialog<({String name, int color})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新建标签' : '编辑标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: 10,
                autofocus: true,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '标签名',
                ),
              ),
              const SizedBox(height: 16),
              // 20 色色板（对勾标当前色）
              ColorPalettePicker(
                selectedColor: pickedColor,
                dotSize: 32,
                spacing: 12,
                onChanged: (c) => setDialogState(() => pickedColor = c),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx, (name: text, color: pickedColor));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑标签：名称 + 颜色一体修改
  Future<void> _edit(Tag tag) async {
    final result = await _showTagDialog(existing: tag);
    if (result == null) return;
    if (result.name == tag.name && result.color == tag.color) return;
    if (!mounted) return;
    try {
      await context
          .read<TagRepository>()
          .updateTag(tag.id, result.name, result.color);
      _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '保存失败：$e');
    }
  }

  /// 删除标签（级联解除账单关联；影响笔数已在确认弹窗告知，不重复 toast）
  Future<void> _delete(Tag tag) async {
    await context.read<TagRepository>().deleteTag(tag.id);
    if (!mounted) return;
    _refresh();
  }

  /// 单击标签弹操作菜单（编辑/删除/查看统计；长按拖动排序由胶囊自身承担）
  void _showActions(Tag tag) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: AppColors.textPrimary),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(ctx);
                  _edit(tag);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.expense),
                title: const Text('删除', style: TextStyle(color: AppColors.expense)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(tag);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart, color: AppColors.textPrimary),
                title: const Text('查看统计数据'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => StatsPage(initialTag: tag),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除二次确认
  Future<void> _confirmDelete(Tag tag) async {
    // 删除前先查引用数量，让用户明确影响范围
    final refCount =
        await context.read<TagRepository>().countBillsByTagId(tag.id);
    if (!mounted) return;
    final impact = refCount == 0
        ? '当前没有账单使用此标签。'
        : '有 $refCount 笔账单使用此标签，删除后这些账单将失去该标签'
            '（账单本身不受影响）。';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除「${tag.name}」？\n\n$impact'),
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
    if (confirmed == true) _delete(tag);
  }

  /// 新建标签：弹窗内输入名称 + 选择颜色
  ///
  /// 颜色必须由用户选定——创建入口已收敛到管理页，不再自动分配，
  /// 让每个标签的颜色都符合用户预期
  Future<void> _addTag() async {
    final result = await _showTagDialog();
    if (result == null) return;
    if (!mounted) return;
    try {
      await context
          .read<TagRepository>()
          .addTag(result.name, color: result.color);
      _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '创建失败：$e');
    }
  }

  /// 拖动结束落库：按最终顺序全量写 sortOrder，再刷新同步本地顺序
  ///
  /// 落库失败需提示用户，否则 UI 上看起来成功、下次进入弹回旧序且无反馈
  Future<void> _onReorder(List<int> orderedIds) async {
    try {
      await context.read<TagRepository>().reorderTags(orderedIds);
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        showAppToast(context, '排序保存失败：$e');
        // 失败时同步回数据库顺序，避免 UI 与实际数据不一致
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('标签管理'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppDimens.pagePadding),
              children: [
                if (_tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        '暂无标签',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  _TagFlow(
                    tags: _tags,
                    onTapTag: _showActions,
                    onReorder: _onReorder,
                  ),
                const SizedBox(height: AppDimens.gapSection),
                const Text(
                  '点击标签可编辑、查看统计或删除；长按拖动可调整顺序',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTag,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 胶囊流长按拖动排序：与分类管理页二级分类同款手感
///
/// 二级面板是固定 5 列网格（等宽格位，坐标除法换算）；标签胶囊宽度随文字
/// 变化，因此用 TextPainter 预测量每个胶囊尺寸 + 模拟 Wrap 换行得到逐个
/// 坐标，再以 Stack + AnimatedPositioned 摆放实现滑动让位动画。
class _TagFlow extends StatefulWidget {
  const _TagFlow({
    required this.tags,
    required this.onTapTag,
    required this.onReorder,
  });

  /// 数据库当前顺序（sortOrder 升序）
  final List<Tag> tags;

  /// 单击弹操作菜单
  final ValueChanged<Tag> onTapTag;

  /// 拖动结束：按最终显示顺序全量落库
  final Future<void> Function(List<int> orderedIds) onReorder;

  @override
  State<_TagFlow> createState() => _TagFlowState();
}

class _TagFlowState extends State<_TagFlow> {
  static const _gap = 10.0; // 胶囊间距（水平与换行共用）
  static const _chipTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.white,
    fontWeight: FontWeight.w500,
  );

  /// 本地显示顺序（拖动期间的唯一事实来源）
  List<Tag> _order = [];

  Tag? _dragging;

  /// 落库进行中：挡住外部刷新，防止数据库流把本地新顺序弹回旧位
  bool _pending = false;

  final Map<int, Size> _sizeCache = {};

  /// build 时缓存的逐胶囊坐标（拖动命中查找用，滞后一帧可接受）
  List<Offset> _posCache = [];

  @override
  void initState() {
    super.initState();
    _order = List.of(widget.tags);
  }

  @override
  void didUpdateWidget(_TagFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 拖动中或落库期间不同步，防止把本地新顺序弹回旧位；
    // 内容级比较（id/名称/颜色），改名改色后也能刷新显示
    if (!_pending && _dragging == null && !_sameList(widget.tags, _order)) {
      _order = List.of(widget.tags);
      _sizeCache.clear();
    }
  }

  bool _sameList(List<Tag> a, List<Tag> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].color != b[i].color) {
        return false;
      }
    }
    return true;
  }

  // ---- 布局：测量 + 模拟 Wrap 换行 ----

  Size _chipSize(Tag t) {
    return _sizeCache.putIfAbsent(t.id, () {
      final tp = TextPainter(
        text: TextSpan(text: t.name, style: _chipTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final size = Size(tp.width + 20, tp.height + 10); // 内边距 10/5 对称
      tp.dispose();
      return size;
    });
  }

  /// 按当前 _order 顺序模拟 Wrap 换行，得到逐胶囊坐标
  List<Offset> _layoutPositions(double maxWidth) {
    final positions = <Offset>[];
    var x = 0.0;
    var y = 0.0;
    for (final t in _order) {
      final size = _chipSize(t);
      if (x > 0 && x + size.width > maxWidth) {
        x = 0;
        y += size.height + _gap;
      }
      positions.add(Offset(x, y));
      x += size.width + _gap;
    }
    return positions;
  }

  double _flowHeight(List<Offset> positions) {
    if (positions.isEmpty) return 0;
    // 底部加余量：中文实际渲染行高可能略大于 TextPainter 计算值，
    // Stack 默认裁剪，余量不足时最后一行下沿会被裁掉
    return positions.last.dy + _chipSize(_order.last).height + 6;
  }

  // ---- 拖动 ----

  void _onDragUpdate(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || _dragging == null) return;
    final local = box.globalToLocal(globalPosition);
    // 矩形包含命中（略外扩）：胶囊之间的缝隙是死区，手指在两胶囊边界
    // 徘徊时不会因"最近中心"来回切换导致顺序抖动
    Tag? hit;
    for (var i = 0; i < _order.length; i++) {
      final t = _order[i];
      if (identical(t, _dragging)) continue;
      final p = _posCache[i];
      final size = _chipSize(t);
      final rect = Rect.fromLTWH(
        p.dx - 4,
        p.dy - 4,
        size.width + 8,
        size.height + 8,
      );
      if (rect.contains(local)) {
        hit = t;
        break;
      }
    }
    if (hit == null) return;
    final di = _order.indexOf(_dragging!);
    final ti = _order.indexOf(hit);
    if (ti == di || ti == -1) return;
    setState(() {
      final item = _order.removeAt(di);
      _order.insert(ti, item);
    });
  }

  Future<void> _endDrag() async {
    final tag = _dragging;
    if (tag == null) return;
    _dragging = null;
    if (!mounted) return;
    setState(() {}); // 恢复原位显示（顺序已是最终顺序）
    if (_sameList(widget.tags, _order)) return; // 顺序没变不写库
    _pending = true;
    try {
      await widget.onReorder(_order.map((t) => t.id).toList());
    } finally {
      _pending = false;
    }
  }

  // ---- 胶囊 ----

  Widget _chip(Tag t, {bool floating = false}) {
    return Material(
      color: Color(t.color),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      elevation: floating ? 3 : 0,
      child: InkWell(
        // 拖动副本不需要点击响应
        onTap: floating ? null : () => widget.onTapTag(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(t.name, style: _chipTextStyle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final positions = _layoutPositions(constraints.maxWidth);
        _posCache = positions;
        return SizedBox(
          height: _flowHeight(positions),
          child: Stack(
            children: [
              for (var i = 0; i < _order.length; i++)
                AnimatedPositioned(
                  key: ValueKey(_order[i].id),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  left: positions[i].dx,
                  top: positions[i].dy,
                  child: LongPressDraggable<Tag>(
                    data: _order[i],
                    // 副本从原位置拿起（跟随手指在原胶囊上的相对位置）
                    dragAnchorStrategy: childDragAnchorStrategy,
                    onDragStarted: () => setState(() => _dragging = _order[i]),
                    onDragUpdate: (details) =>
                        _onDragUpdate(details.globalPosition),
                    onDragEnd: (_) => _endDrag(),
                    onDraggableCanceled: (_, _) => _endDrag(),
                    feedback: _chip(_order[i], floating: true),
                    // 原位隐藏，空隙即它的 slot，其余胶囊滑动让位
                    childWhenDragging: const SizedBox.shrink(),
                    child: _chip(_order[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
