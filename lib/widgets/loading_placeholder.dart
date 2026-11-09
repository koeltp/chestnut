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
