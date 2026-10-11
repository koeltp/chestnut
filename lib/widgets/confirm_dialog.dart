import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 通用二次确认对话框：全项目「确认 + 执行」动作（删除账单、删除
/// 资产、清空预算、归档等）共用，保证按钮文案与危险色口径一致。
/// 返回 true = 用户确认；[danger] 为 true 时确认键红色（删除类动作）
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelText),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: danger
              ? TextButton.styleFrom(foregroundColor: AppColors.expense)
              : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return confirmed == true;
}
