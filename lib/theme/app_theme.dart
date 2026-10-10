import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

export 'app_colors.dart';
export 'app_dimens.dart';

/// 应用主题配置
///
/// 设计规范常量见 [AppColors] 与 [AppDimens]；页面统一 import 本文件
/// 即可同时获得主题与规范常量。
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      // 输入框提示文字统一灰色：Material 3 默认 hint 色偏深，
      // 灰底输入框里看起来像已填值，用户会误以为不用输入
      inputDecorationTheme: const InputDecorationThemeData(
        hintStyle: TextStyle(color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        // 顶栏底部柔和投影：与内容区分层（钱迹式立体效果）
        elevation: 3,
        shadowColor: Color(0x1F000000),
        surfaceTintColor: Colors.transparent,
        // 滚动时保持同样的投影（0 会导致上滑后立体效果消失）
        scrolledUnderElevation: 3,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: CircleBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusHeader),
          ),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        surface: AppColors.card,
      ),
    );
  }
}
