import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/header_background.dart';

/// 顶部背景选择页：经典蓝渐变 + backgrounds 目录下自动发现的图片
class HeaderBackgroundPage extends StatefulWidget {
  const HeaderBackgroundPage({super.key});

  @override
  State<HeaderBackgroundPage> createState() => _HeaderBackgroundPageState();
}

class _HeaderBackgroundPageState extends State<HeaderBackgroundPage> {
  /// 目录下自动发现的背景图；null = 仍在加载
  List<String>? _assets;

  @override
  void initState() {
    super.initState();
    HeaderBackground.availableAssets().then((assets) {
      if (mounted) setState(() => _assets = assets);
    });
  }

  /// 点选即生效并记忆；留在本页便于连续预览，选中态即时刷新
  Future<void> _select(String? asset) async {
    await context.read<SettingsProvider>().setHeaderBackground(asset);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<SettingsProvider>().headerBackground;
    final assets = _assets;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('顶部背景'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      body: assets == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : GridView.count(
              padding: const EdgeInsets.all(AppDimens.pagePadding),
              crossAxisCount: 2,
              mainAxisSpacing: AppDimens.gapMd,
              crossAxisSpacing: AppDimens.gapMd,
              childAspectRatio: 4 / 3,
              children: [
                _cell(
                  label: '经典蓝渐变',
                  selected: selected == null || selected.isEmpty,
                  decoration: const BoxDecoration(
                    gradient: AppColors.headerGradient,
                  ),
                  onTap: () => _select(null),
                ),
                for (final asset in assets)
                  _cell(
                    label: HeaderBackground.displayName(asset),
                    selected: selected == asset,
                    decoration:
                        HeaderBackground.decoration(asset) as BoxDecoration,
                    onTap: () => _select(asset),
                  ),
              ],
            ),
    );
  }

  /// 单个缩略图格：选中时主色描边 + 右上角对勾
  Widget _cell({
    required String label,
    required bool selected,
    required Decoration decoration,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(decoration: decoration),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              if (selected)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
