import 'dart:async';

import 'package:flutter/material.dart';

/// 当前在屏的 toast 条目：新 toast 插入前移除旧的（同屏只留一个，
/// 与原 SnackBar clearSnackBars 行为一致）
OverlayEntry? _activeEntry;
Timer? _dismissTimer;

/// 全局轻提示：屏幕居中黑色圆角浮层（系统级提示样式）。
///
/// 挂在 rootOverlay 上，盖得住页面与底部弹窗；系统键盘是独立窗口
/// 盖不住（Flutter 没有能画到键盘之上的层级），键盘弹出时自动上移
/// 到键盘上方居中。默认 2 秒自动消失，可选 duration 自定义。
void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  _activeEntry?.remove();
  _dismissTimer?.cancel();
  final entry = OverlayEntry(builder: (_) => _ToastView(message: message));
  _activeEntry = entry;
  Overlay.of(context, rootOverlay: true).insert(entry);
  _dismissTimer = Timer(duration, () {
    if (_activeEntry == entry) {
      entry.remove();
      _activeEntry = null;
      _dismissTimer = null;
    }
  });
}

/// 居中浮层：黑底白字圆角条；键盘弹出时把中心区域整体上移，
/// 浮层落在键盘上方而不是被键盘挡住
class _ToastView extends StatelessWidget {
  const _ToastView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return IgnorePointer(
      // 不拦截触摸：toast 展示期间下层仍可点击
      child: Align(
        alignment: Alignment.center,
        // 下内边距抬升可用区域中心 = 上移半个键盘高度
        child: Padding(
          padding: EdgeInsets.only(bottom: insets.bottom / 2),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
