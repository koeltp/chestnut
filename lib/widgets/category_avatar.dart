import 'package:flutter/material.dart';

/// 文字图标的约定 codePoint：0 不与任何真实 Material 图标冲突，
/// 数据库 iconCode 存 0 即为"文字图标"（显示名称首字），无需加列迁移
const int kTextIconCode = 0;

/// 分类头像：统一显示分类图标（圆形浅色底 + 分类色图标）或名称首字
/// （iconCode 为 [kTextIconCode] 时），两种模式同风格：13% 透明分类
/// 底 + 分类色前景，全应用分类图标显示点共用本组件
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.name,
    required this.iconCode,
    required this.color,
    this.size = 40,
    this.iconSize = 21,
  });

  /// 分类名称（文字模式下取首字显示）
  final String name;

  /// 分类图标 codePoint；[kTextIconCode] 表示文字图标
  final int iconCode;

  /// 分类色（ARGB 整数），作前景色与 13% 透明底色
  final int color;

  /// 头像容器直径
  final double size;

  /// 前景尺寸（图标字号/文字首字字号）
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: iconCode == kTextIconCode
          ? Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              maxLines: 1,
              style: TextStyle(
                color: c,
                fontSize: iconSize,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            )
          : Icon(
              // ignore: non_const_argument_for_const_parameter
              IconData(iconCode, fontFamily: 'MaterialIcons'),
              color: c,
              size: iconSize,
            ),
    );
  }
}
