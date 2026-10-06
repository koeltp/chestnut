import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 帮助说明条目：一个图标 + 标题 + 说明
class HelpSheetItem {
  const HelpSheetItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// 底部弹出的帮助说明面板
///
/// 统一样式：半透明遮罩 + 顶部圆角卡片 + 图标化要点 + 全宽"知道了"。
/// 备份与恢复、分类管理等页面的顶栏"？"共用，替代系统默认 AlertDialog。
class HelpSheet {
  HelpSheet._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<HelpSheetItem> items,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      // 只保留自绘手柄，关闭系统默认拖动条，避免顶部出现两条横杠
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          // 内容可滚动：条目多、文字长时兜底，避免 bottom overflow
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部拖动手柄
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimens.gapMd),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDimens.gapMd),
                for (final (i, item) in items.indexed) ...[
                  if (i > 0) const SizedBox(height: AppDimens.gapMd),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.tint(AppColors.primary),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.icon,
                          size: 17,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.description,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppDimens.gapLg),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusCard,
                        ),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('知道了', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
