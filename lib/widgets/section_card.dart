import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';

/// 统一卡片容器
///
/// 全应用唯一的卡片样式：白底 + 统一圆角 + 极浅投影。
/// 各页面用它包裹内容区块，保证视觉层次一致。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDimens.cardPadding),
    this.margin = EdgeInsets.zero,
    this.radius = AppDimens.radiusCard,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// 卡片圆角：默认全局规范值，紧凑小卡可传更小值
  final double radius;

  /// 传入时可点击（卡片整体水波反馈）
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          // 极浅投影：仅用于把卡片从米色背景上托起，不做明显立体感
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: padding == EdgeInsets.zero
          ? child
          : Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}
