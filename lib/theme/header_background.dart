import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// 首页顶部卡背景
///
/// 默认经典蓝渐变（[AppColors.headerGradient]），可切换为
/// assets/images/backgrounds/ 下的图片。图片命名约定：
/// `bg_<显示名>.jpg`，去掉 bg_ 前缀与扩展名即展示名；
/// pubspec 声明整个目录，放入新图无需改代码——选择页通过
/// AssetManifest 自动发现。
abstract final class HeaderBackground {
  /// SharedPreferences 键：存选中图片的资产路径；无键 = 经典蓝渐变
  static const kPrefKey = 'header_background';

  static const _dir = 'assets/images/backgrounds/';
  static const _prefix = 'bg_';

  /// 图片背景上的主色遮罩：深藏蓝自上而下 .30 → .58 渐变，
  /// 保证白字在任意浅色图片上可读
  static const Color _mask = Color(0xFF172840);

  /// 枚举目录下全部背景图资产路径，按显示名排序
  static Future<List<String>> availableAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest
            .listAssets()
            .where(
              (path) =>
                  path.startsWith(_dir) &&
                  path.substring(_dir.length).startsWith(_prefix) &&
                  path.contains('.'),
            )
            .toList()
          ..sort((a, b) => displayName(a).compareTo(displayName(b)));
    return assets;
  }

  /// 资产路径 → 展示名（去 bg_ 前缀与扩展名）
  static String displayName(String asset) {
    final name = asset.split('/').last;
    return name.substring(_prefix.length, name.lastIndexOf('.'));
  }

  /// 顶部卡装饰：经典蓝渐变，或"图片 + 主色遮罩渐变"
  static Decoration decoration(String? asset) {
    if (asset == null || asset.isEmpty) {
      return const BoxDecoration(gradient: AppColors.headerGradient);
    }
    return BoxDecoration(
      image: DecorationImage(image: AssetImage(asset), fit: BoxFit.cover),
      // BoxDecoration 中 gradient 绘制在 image 之上，天然作遮罩层
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_mask.withValues(alpha: 0.30), _mask.withValues(alpha: 0.58)],
      ),
    );
  }
}
