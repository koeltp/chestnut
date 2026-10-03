/// 尺寸规范：间距 / 圆角 / 图标底统一取值（8pt 网格）
abstract final class AppDimens {
  // ---------- 间距 ----------

  /// 页面水平边距
  static const double pagePadding = 16;

  /// 卡片内边距
  static const double cardPadding = 16;

  /// 组件小间距
  static const double gapSm = 8;

  /// 组件中间距
  static const double gapMd = 12;

  /// 组件大间距
  static const double gapLg = 16;

  /// 区块间距
  static const double gapSection = 12;

  // ---------- 圆角 ----------

  /// 卡片圆角
  static const double radiusCard = 5;

  /// 按钮 / 输入框圆角
  static const double radiusControl = 12;

  /// 头部渐变区 / 弹层顶部圆角
  static const double radiusHeader = 24;

  // ---------- 图标底尺寸 ----------

  /// 分类图标统一尺寸：全应用（列表条目/分类管理/记一笔/编辑预览）一致
  static const double iconTile = 40;
}
