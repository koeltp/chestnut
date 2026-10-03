import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 统一分段切换器
///
/// 记一笔页（支出/收入）、统计页、分类管理页共用的胶囊分段控件；
/// [options] 与 [colors] 一一对应，选中项以对应语义色实底呈现。
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.colors = const [AppColors.primary, AppColors.primary],
    this.expand = false,
  });

  /// 选项与文案
  final List<(T, String)> options;

  /// 当前选中值
  final T selected;

  /// 选中回调
  final ValueChanged<T> onChanged;

  /// 各选项选中时的底色（支出红 / 收入绿等语义色）
  final List<Color> colors;

  /// 是否横向撑满容器
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      final (value, label) = options[i];
      final isSelected = value == selected;
      children.add(
        _Segment(
          label: label,
          color: colors[i],
          selected: isSelected,
          onTap: () => onChanged(value),
        ),
      );
      if (i != options.length - 1) {
        children.add(const SizedBox(width: 6));
      }
    }

    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: expand
          ? children.map((c) => Expanded(child: c)).toList()
          : children,
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppDimens.radiusControl),
      ),
      child: row,
    );
  }
}

/// 单个分段项
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimens.radiusControl - 3),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
