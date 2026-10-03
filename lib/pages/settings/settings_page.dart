import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../providers/settings_provider.dart';
import '../../services/export_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'category_manage_page.dart';

/// 我的页：分类管理、记账定位开关、数据导出、关于
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          24,
        ),
        children: [
          _buildHeader(),
          const SizedBox(height: AppDimens.gapSection),
          _buildMenuCard(context),
          const SizedBox(height: AppDimens.gapSection),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppDimens.gapSection),
            child: Center(
              child: Text(
                '栗子记账 · 记下生活的每一笔',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 品牌头部
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Row(
        children: [
          // 栗子吉祥物 Logo（图片自带圆角与透明背景）
          Image.asset(
            'assets/images/logo.png',
            width: 56,
            height: 56,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 14),
          // 版本号颜色为运行时方法生成，无法整体 const
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '栗子记账',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Chestnut · v1.0.0',
                style: TextStyle(fontSize: 12, color: AppColors.onHeader(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 功能菜单
  Widget _buildMenuCard(BuildContext context) {
    final locationEnabled =
        context.watch<SettingsProvider>().billLocationEnabled;
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _menuItem(
            context,
            icon: Icons.category_outlined,
            color: AppColors.primary,
            title: '分类管理',
            subtitle: '自定义收支分类',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoryManagePage(),
              ),
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          _switchItem(
            context,
            icon: Icons.place_outlined,
            color: AppColors.income,
            title: '记账定位',
            subtitle: '开启后记一笔可附加当前位置',
            value: locationEnabled,
            onChanged: (v) =>
                context.read<SettingsProvider>().setBillLocationEnabled(v),
          ),
          const Divider(indent: 16, endIndent: 16),
          _menuItem(
            context,
            icon: Icons.file_download_outlined,
            color: AppColors.income,
            title: '导出账单',
            subtitle: '导出全部账单为 CSV 文件',
            onTap: () => _exportCsv(context),
          ),
          const Divider(indent: 16, endIndent: 16),
          _menuItem(
            context,
            icon: Icons.info_outline,
            color: AppColors.expense,
            title: '关于',
            subtitle: '了解栗子记账',
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  /// 单个菜单项
  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
          vertical: AppDimens.gapLg,
        ),
        child: Row(
          children: [
            Container(
              width: AppDimens.iconTile,
              height: AppDimens.iconTile,
              decoration: BoxDecoration(
                color: AppColors.tint(color),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: AppDimens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// 开关型设置项：与菜单项同样式，右侧为 Switch，无跳转
  Widget _switchItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapLg,
      ),
      child: Row(
        children: [
          Container(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            decoration: BoxDecoration(
              color: AppColors.tint(color),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: AppDimens.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 导出 CSV 并调起系统分享
  Future<void> _exportCsv(BuildContext context) async {
    try {
      final db = context.read<AppDatabase>();
      final file = await ExportService(db).exportCsv();
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          text: '栗子记账账单导出',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// 关于对话框
  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于栗子记账'),
        content: const Text(
          '栗子记账（Chestnut）是一款简洁精致的个人记账应用。\n\n'
          '· 收支记录与分类管理\n'
          '· 月度统计图表\n'
          '· 预算管理\n'
          '· 数据本地存储，安全私密\n\n'
          '版本：1.0.0',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
