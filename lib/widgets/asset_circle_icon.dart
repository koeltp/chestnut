import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/asset_category.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 资产分类彩色圆图标（分类选择器/表单/列表行共用）
///
/// 从分类名查图标与主题色，未命中（旧数据/异常数据）兜底"其它"样式。
/// 品牌 logo 两种载体：字体 glyph（simple-icons）与 SVG 资源
/// （iconfont 白色剪影，圆盘+镂空素材已预处理为纯白 glyph）。
/// SVG 占圆 92%，glyph 占 53%（字体字面留白偏大故缩小）。
class AssetCircleIcon extends StatelessWidget {
  const AssetCircleIcon({super.key, required this.category, this.size});

  /// 分类名（持久化到 assets.category 的值）
  final String category;

  /// 圆的直径；缺省为全局图标底尺寸
  final double? size;

  @override
  Widget build(BuildContext context) {
    final d = size ?? AppDimens.iconTile;
    final def = AssetGroups.categoryOf(category);
    final color = Color(def?.color ?? 0xFF9E9E9E);
    // 品牌 logo：实色底；品类图标：浅色底
    final isBrand = def?.brand ?? false;
    final bg = isBrand ? color : AppColors.tint(color);
    final svg = def?.brandSvg;
    Widget glyphWidget;
    if (svg != null) {
      // 白色剪影 logo 落在品牌实色圆底上
      glyphWidget = SvgPicture.asset(svg, width: d * 0.92, height: d * 0.92);
    } else {
      // 字体 glyph：品牌用白色（浅底品牌用深色），品类用主题色
      final glyph = !isBrand
          ? color
          : (def!.darkGlyph ? const Color(0xFF1A1A1A) : Colors.white);
      glyphWidget = Icon(
        AssetGroups.iconOf(category),
        color: glyph,
        size: d * 0.53,
      );
    }
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: glyphWidget,
    );
  }
}
