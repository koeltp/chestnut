import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 分段器布局模式
enum AppSegmentedFit {
  /// 等分不撑满：总宽 = 内容自然宽，各项严格等分、无缝贴合（默认）
  equal,

  /// 撑满等分：铺满外部约束宽度，各项严格等分、无缝贴合
  stretch,
}

/// 统一分段切换器
///
/// 记一笔页（支出/收入）、统计页、分类管理页共用的分段控件；
/// 选中项以对应语义色**满格实底**呈现（完全遮住灰底），
/// 圆角贴合容器：首段左两角圆、末段右两角圆、中间段直角。
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.colors = const [AppColors.primary, AppColors.primary],
    this.fit = AppSegmentedFit.equal,
  });

  /// 选项与文案
  final List<(T, String)> options;

  /// 当前选中值；为 null 时全部段呈未选中态（如预算模式清空后）
  final T? selected;

  /// 选中回调
  final ValueChanged<T> onChanged;

  /// 各选项选中时的底色（支出红 / 收入绿等语义色）
  final List<Color> colors;

  /// 布局模式
  final AppSegmentedFit fit;

  @override
  Widget build(BuildContext context) {
    final row = switch (fit) {
      // 等分不撑满：IntrinsicWidth 先测内容自然总宽，
      // 再以该宽 tight 约束 Row，Expanded 各分一等份（无缝）
      AppSegmentedFit.equal => IntrinsicWidth(
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++)
                Expanded(child: _segment(i)),
            ],
          ),
        ),
      // 撑满：吃满外部约束宽度，Expanded 各分一等份（无缝）
      AppSegmentedFit.stretch => Row(
          children: [
            for (var i = 0; i < options.length; i++)
              Expanded(child: _segment(i)),
          ],
        ),
    };

    // 无内边距：选中段才能满格遮住灰底
    return Container(
      // 裁切子元素：选中段满格直角块在容器圆角拐角处被裁成
      // 与容器一致的圆角——圆角由裁切提供、恒定不参与动画，
      // 避免切换时 BorderRadius 补间的"圆角先小后大"闪烁
      clipBehavior: Clip.antiAlias,
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
