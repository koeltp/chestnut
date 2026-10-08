import 'package:flutter/material.dart';

/// 栗子记账色板
///
/// 全应用唯一的颜色来源，经典蓝白风；
/// 禁止在页面中散落魔法色值。
abstract final class AppColors {
  // ---------- 品牌色 ----------

  /// 主色：靛蓝
  static const Color primary = Color(0xFF2F6BEB);

  /// 主色深：用于渐变尾部与强调
  static const Color primaryDeep = Color(0xFF1E4FC4);

  /// 主色浅：用于渐变头部
  static const Color primaryLight = Color(0xFF5C8DF6);

  // ---------- 中性色 ----------

  /// 页面背景：极浅蓝灰（衬托白色卡片）
  static const Color background = Color(0xFFF6F8FB);

  /// 卡片背景
  static const Color card = Colors.white;

  /// 浅色填充：分段控件底、输入框底、键盘底
  static const Color fill = Color(0xFFEDF1F7);

  /// 分割线
  static const Color divider = Color(0xFFE7ECF3);

  /// 主文字：深藏蓝黑
  static const Color textPrimary = Color(0xFF17233D);

  /// 次要文字：灰蓝
  static const Color textSecondary = Color(0xFF8792A8);

  // ---------- 语义色 ----------

  /// 支出：红
  static const Color expense = Color(0xFFE5484D);

  /// 收入：绿
  static const Color income = Color(0xFF2FA46B);

  /// 预警：接近预算上限
  static const Color warning = Color(0xFFF09A37);

  /// 20 色通用选色板：分类与标签共用同一常量
  ///
  /// 同一颜色只在此定义一次，分类编辑选色、标签管理选色、标签自动分配
  /// 全部引用本列表，避免多处色板漂移不一致。
  static const List<int> tagPalette = [
    0xFFF4A6C0, // 粉
    0xFFD6288C, // 玫红
    0xFFF5842D, // 橙
    0xFFD63A2F, // 红
    0xFFE8B93E, // 金黄
    0xFFEF6B5C, // 橘红
    0xFF4FB3A6, // 青绿
    0xFF3E94A0, // 蓝绿
    0xFF3D7A24, // 深绿
    0xFF2A6478, // 深青
    0xFF45B8E8, // 天蓝
    0xFF5A9BF6, // 亮蓝
    0xFF3F63E8, // 宝蓝
    0xFF3D4AA0, // 靛蓝
    0xFF7B2FE0, // 紫
    0xFF8A5A3B, // 棕
    0xFF7D8896, // 灰
    0xFF8E4D8C, // 梅紫
    0xFF7A7F55, // 橄榄
    0xFF4A4A45, // 深灰
  ];

  /// 顶部品牌渐变
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primaryDeep],
  );

  /// 分类图标的浅色底（统一透明度，保证各处质感一致）
  static Color tint(Color color) => color.withValues(alpha: 0.12);

  /// 白色低透明度（用于渐变头部上的辅助文字/进度条底）
  static Color onHeader(double alpha) => Colors.white.withValues(alpha: alpha);
}
