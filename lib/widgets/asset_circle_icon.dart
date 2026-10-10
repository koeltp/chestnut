import 'package:flutter/material.dart';

import '../models/asset_category.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 资产分类彩色圆图标（分类选择器/表单/列表行共用）
///
/// 从分类名查图标与主题色，未命中（旧数据/异常数据）兜底"其它"样式。
class AssetCircleIcon extends StatelessWidget {
  const AssetCircleIcon({super.key, required this.category, this.size});

  /// 分类名（持久化到 assets.category 的值）
  final String category;

  /// 圆的直径；缺省为全局图标底尺寸
  final double? size;

  @override
  Widget build(BuildContext context) {
    final d = size ?? AppDimens.iconTile;
    final color = AssetGroups.colorOf(category);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(color: AppColors.tint(color), shape: BoxShape.circle),
      child: Icon(AssetGroups.iconOf(category), color: color, size: d * 0.53),
    );
  }
}
