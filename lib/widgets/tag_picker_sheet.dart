import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/repositories/tag_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../pages/settings/tag_manage_page.dart';

/// 标签选择弹层（记一笔/编辑页共用）
///
/// 顶部已选标签胶囊（点取消）+ 全部标签网格（点选）+ 输入框建新标签
/// + 右上角"管理"进入独立标签管理页。选中状态即时回传调用方。
class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.selectedIds,
    required this.allTags,
    required this.onChanged,
  });

  /// 当前已选标签 id
  final Set<int> selectedIds;

  /// 全部标签（由调用方缓存传入，避免每次打开弹层都查库）
  final List<Tag> allTags;

  /// 选中变化回调（新增/取消都会触发）
  final void Function(Set<int> ids) onChanged;

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<int>.from(widget.selectedIds);
  }

  /// 切换某个标签的选中状态
  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
    widget.onChanged(Set<int>.from(_selected));
  }

  /// 进入标签管理页（返回时刷新缓存）
  Future<void> _openManage() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const TagManagePage()),
    );
    if (!mounted) return;
    // 管理页可能增删改标签，重新拉取全部
    final tags = await context.read<TagRepository>().getTags();
    if (!mounted) return;
    setState(() {
      widget.allTags
        ..clear()
        ..addAll(tags);
      // 清理已被删除的标签 id
      _selected.removeWhere((id) => !tags.any((t) => t.id == id));
    });
    widget.onChanged(Set<int>.from(_selected));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pagePadding,
            16,
            AppDimens.pagePadding,
            AppDimens.pagePadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行：标签 + 管理按钮
              Row(
                children: [
                  const Text(
                    '标签',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _openManage,
                    child: const Text('管理'),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.gapMd),
              // 单一标签列表：选中=实底白字，未选=白底彩框彩字
              // （不再单列"已选区"，避免同一个标签上下重复出现）
              if (widget.allTags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in widget.allTags)
                      _TagChip(
                        tag: t,
                        selected: _selected.contains(t.id),
                        onTap: () => _toggle(t.id),
                      ),
                  ],
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '暂无标签，点右上角"管理"创建',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标签胶囊：选中态实底白字，未选中态浅底+彩色边框
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  final Tag tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.color);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          // 未选中=白底彩框（描边胶囊，图2 风格）；选中=实底白字；
          // 圆角与卡片一致（radiusCard），避免胶囊过于圆润
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          border: Border.all(color: color),
        ),
        child: Text(
          tag.name,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : color,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
