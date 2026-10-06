import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 分段器布局模式
enum AppSegmentedFit {
  /// 紧凑：总宽 = 内容自然宽，项间 6px 缝隙（默认）
  compact,

  /// 等分不撑满：总宽 = 内容自然宽，各项严格等分、无缝贴合
  equal,

  /// 撑满等分：铺满外部约束宽度，各项严格等分、无缝贴合
  stretch,
}

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
    this.fit = AppSegmentedFit.compact,
  });

  /// 选项与文案
  final List<(T, String)> options;

  /// 当前选中值
  final T selected;

  /// 选中回调
  final ValueChanged<T> onChanged;

  /// 各选项选中时的底色（支出红 / 收入绿等语义色）
  final List<Color> colors;

  /// 布局模式
  final AppSegmentedFit fit;

  @override
  Widget build(BuildContext context) {
    Widget row;
    switch (fit) {
      case AppSegmentedFit.compact:
        // 紧凑：内容自适应宽 + 项间 6px 缝隙
        final children = <Widget>[];
        for (var i = 0; i < options.length; i++) {
          children.add(_segment(i));
          if (i != options.length - 1) {
            children.add(const SizedBox(width: 6));
          }
        }
        row = Row(mainAxisSize: MainAxisSize.min, children: children);
      case AppSegmentedFit.equal:
        // 等分不撑满：IntrinsicWidth 先测内容自然总宽，
        // 再以该宽 tight 约束 Row，Expanded 各分一半（无缝）
        row = IntrinsicWidth(
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++)
                Expanded(child: _segment(i)),
            ],
          ),
        );
      case AppSegmentedFit.stretch:
        // 撑满：吃满外部约束宽度，Expanded 各分一半（无缝）
        row = Row(
          children: [
            for (var i = 0; i < options.length; i++)
              Expanded(child: _segment(i)),
          ],
        );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppDimens.radiusControl),
      ),
      child: row,
    );
  }

  Widget _segment(int i) {
    final (value, label) = options[i];
    // colors 允许缺省（默认只配两色）：超出部分回退主色，
    // 避免三选项分段器取 colors[2] 时 RangeError
    return _Segment(
      label: label,
      color: i < colors.length ? colors[i] : AppColors.primary,
      selected: value == selected,
      onTap: () => onChanged(value),
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
