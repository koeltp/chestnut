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
