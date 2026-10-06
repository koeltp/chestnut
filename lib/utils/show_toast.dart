import 'package:flutter/material.dart';

/// 全局轻提示：统一浮动 SnackBar 样式（圆角、深色、底部悬浮）。
///
/// 替代各页面重复书写的 ScaffoldMessenger.showSnackBar 模板代码；
/// 默认 2 秒自动消失，可选 duration 自定义。
void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
}
