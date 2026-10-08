import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 选中色的提示样式
enum ColorIndicatorStyle {
  /// 白色对勾（选色弹窗内嵌态常用）
  check,

  /// 外圈描边（独立选色对话框常用）
  ring,
}

/// 通用色板选择器
///
/// 分类编辑选色、标签改色、新建标签选色共用本组件，
/// 颜色列表统一引用 [AppColors.tagPalette]，保证全应用选色
/// 入口外观一致；选中样式可在[ColorIndicatorStyle]间切换。
class ColorPalettePicker extends StatelessWidget {
  const ColorPalettePicker({
    super.key,
    required this.selectedColor,
    required this.onChanged,
    this.colors = AppColors.tagPalette,
    this.style = ColorIndicatorStyle.check,
    this.dotSize = 36,
    this.spacing = 14,
  });

  /// 当前选中色（ARGB 整数）
  final int selectedColor;

  /// 点击某个颜色的回调
  final ValueChanged<int> onChanged;

  /// 可选颜色（默认共用 20 色通用色板）
  final List<int> colors;

  /// 选中态提示样式
  final ColorIndicatorStyle style;

  /// 单个圆点直径
  final double dotSize;

  /// 圆点间距
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final c in colors)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: dotSize,
              height: dotSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: style == ColorIndicatorStyle.ring && c == selectedColor
                    ? Border.all(color: AppColors.textPrimary, width: 2)
                    : null,
              ),
              child: style == ColorIndicatorStyle.check && c == selectedColor
                  ? Icon(Icons.check, size: dotSize * 0.56, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}
