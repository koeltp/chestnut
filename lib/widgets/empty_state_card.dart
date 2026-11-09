import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 空态卡片组件：统一各页面的"无数据"视觉风格。
///
/// 三种预设场景：
/// - [EmptyStateCard.none] — 真空态：页面从未有过数据（如新用户首次打开首页）
/// - [EmptyStateCard.filtered] — 筛选后无数据：给"清除筛选"按钮
/// - [EmptyStateCard.customRange] — 自定义区间无数据：给"调整区间"按钮
///
/// 也可以用 [EmptyStateCard.custom] 传入完全自定义文案/图标/操作。
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard._({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  /// 真空态："这个月还没有记账"
  const EmptyStateCard.none({
    super.key,
    String? periodLabel,
  })  : icon = Icons.savings_outlined,
        title = periodLabel ?? '这个月还没有记账',
        subtitle = '点击下方 + 记下第一笔吧',
        actionLabel = null,
        onAction = null;

  /// 筛选后无数据
  factory EmptyStateCard.filtered({
    Key? key,
    required VoidCallback onClear,
  }) =>
      EmptyStateCard._(
        key: key,
        icon: Icons.filter_alt_off_outlined,
        title: '当前筛选条件下暂无账单',
        subtitle: '试试清除筛选或换个条件',
        actionLabel: '清除筛选',
        onAction: onClear,
      );

  /// 自定义区间无数据
  factory EmptyStateCard.customRange({
    Key? key,
    required VoidCallback onAdjust,
  }) =>
      EmptyStateCard._(
        key: key,
        icon: Icons.event_busy_outlined,
        title: '该范围内暂无账单',
        subtitle: '试试调整查询区间',
        actionLabel: '调整区间',
        onAction: onAdjust,
      );

  /// 完全自定义
  factory EmptyStateCard.custom({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      EmptyStateCard._(
        key: key,
        icon: icon,
        title: title,
        subtitle: subtitle,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.fill,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 44,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: AppDimens.gapLg),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppDimens.gapMd),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.clear, size: 16),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
