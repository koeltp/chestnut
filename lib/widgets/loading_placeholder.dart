import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 首屏数据未就绪时的统一占位：小号转圈 + 可选提示文案。
///
/// 各页统一用它（而不是直接空白或默认的大转圈），既避免被误认为
/// 页面卡死，也保持首屏加载的视觉一致
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({super.key, this.text});

  /// 转圈下方提示文案；null 时只显示转圈
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.primary,
            ),
          ),
          if (text != null) ...[
            const SizedBox(height: 10),
            Text(
              text!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 数据流出错时的统一占位：和 [LoadingPlaceholder] 同一视觉体系，
/// 但明确表达"是失败，不是还没加载完"——否则错误会被误认成空态或卡死
class ErrorPlaceholder extends StatelessWidget {
  const ErrorPlaceholder({super.key, this.text = '数据加载失败，请稍后重试'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 28,
            color: AppColors.textSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
