import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/show_toast.dart';
import '../../widgets/color_palette_picker.dart';
import '../stats/stats_page.dart';

/// 标签管理页：从标签选择弹层的"管理"按钮进入
///
/// 功能：查看全部标签、重命名、改颜色、删除（级联删除账单关联，需确认）。
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

  /// 重命名标签
  Future<void> _rename(Tag tag) async {
    final controller = TextEditingController(text: tag.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: controller,
          maxLength: 10,
          autofocus: true,
          decoration: const InputDecoration(
            counterText: '',
            hintText: '标签名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == tag.name) return;
    if (!mounted) return;
    await context.read<TagRepository>().updateTag(tag.id, newName, tag.color);
    _refresh();
  }

  /// 改颜色
  Future<void> _changeColor(Tag tag) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择颜色'),
        content: ColorPalettePicker(
          selectedColor: tag.color,
          style: ColorIndicatorStyle.ring,
          onChanged: (c) => Navigator.pop(ctx, c),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (picked == null || picked == tag.color) return;
    if (!mounted) return;
    await context.read<TagRepository>().updateTag(tag.id, tag.name, picked);
    _refresh();
  }

  /// 删除标签（级联解除账单关联；影响笔数已在确认弹窗告知，不重复 toast）
  Future<void> _delete(Tag tag) async {
    await context.read<TagRepository>().deleteTag(tag.id);
    if (!mounted) return;
    _refresh();
  }

  /// 长按标签弹操作菜单
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
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  _rename(tag);
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette, color: AppColors.textPrimary),
                title: const Text('改颜色'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeColor(tag);
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

  /// 新建标签：弹窗内输入名称 + 选择颜色（图1 钱迹样式）
  ///
  /// 颜色必须由用户选定——创建入口已收敛到管理页，不再自动分配，
  /// 让每个标签的颜色都符合用户预期
  Future<void> _addTag() async {
    final controller = TextEditingController();
    var pickedColor = AppColors.tagPalette.first; // 默认选中色板首色
    final result = await showDialog<({String name, int color})>(
      context: context,
      // StatefulBuilder：色板点击即时刷新选中态，无需关闭弹窗
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建标签'),
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final t in _tags)
                        GestureDetector(
                          onLongPress: () => _showActions(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              // 管理页与选中态同款：实底白字（标签色就是其身份色）
                              color: Color(t.color),
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusCard,
                              ),
                            ),
                            child: Text(
                              t.name,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: AppDimens.gapSection),
                const Text(
                  '长按标签可重命名、改颜色、查看统计或删除',
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
