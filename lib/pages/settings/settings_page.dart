import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../providers/settings_provider.dart';
import '../../services/export_service.dart';
import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/show_toast.dart';
import '../../widgets/section_card.dart';
import '../../widgets/update_dialog.dart';
import 'about_page.dart';
import 'category_manage_page.dart';
import 'backup_page.dart';
import 'passcode_settings_page.dart';

/// 我的页：分类管理、定位开关、数据导出、关于
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 当前应用版本名（启动后异步获取，头部与关于框共用，不再硬编码）
  String _versionName = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _versionName = info.version);
    });
  }

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
                _versionName.isEmpty ? 'Chestnut' : 'Chestnut · v$_versionName',
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
    final locationEnabled = context
        .watch<SettingsProvider>()
        .billLocationEnabled;
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
          _menuItem(
            context,
            icon: Icons.lock_outline,
            color: AppColors.primary,
            title: '密码保护',
            subtitle: '数字密码与指纹/面容解锁',
            onTap: () {
              // 未设密码时直达设置流程，跳过未设置态主界面
              final settings = context.read<SettingsProvider>();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PasscodeSettingsPage(startSetup: !settings.passcodeEnabled),
                ),
              );
            },
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
            icon: Icons.backup_outlined,
            color: AppColors.primary,
            title: '备份与恢复',
            subtitle: '导出完整备份 / 导入备份恢复数据',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BackupPage()),
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          _menuItem(
            context,
            icon: Icons.system_update_outlined,
            color: AppColors.primaryDeep,
            title: '检查更新',
            subtitle: _versionName.isEmpty
                ? '发现新版本可立即升级'
                : '当前 v$_versionName · 检查新版本',
            onTap: () => _checkUpdateManually(context),
          ),
          const Divider(indent: 16, endIndent: 16),
          _menuItem(
            context,
            icon: Icons.info_outline,
            color: AppColors.expense,
            title: '关于',
            subtitle: '版本、隐私政策与开源信息',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutPage()),
            ),
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
      showAppToast(context, '导出失败：$e');
    }
  }

  /// 手动检查更新：转圈 → 有新版直接弹更新卡片；已是最新/失败给轻提示。
  /// 与启动自动检查的区别：不受"以后再说"忽略记录限制，且失败要明示。
  /// Dev 包直接提示：更新装的是生产包，在 Dev 包里走只会多装一个包
  Future<void> _checkUpdateManually(BuildContext context) async {
    if (kDebugMode) {
      showAppToast(context, '开发版不支持应用内更新');
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _CheckingDialog(),
      ),
    );
    try {
      final info = await UpdateService().checkForUpdate();
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭检查中弹窗
      if (info == null) {
        showAppToast(context, '已是最新版本');
      } else {
        await showUpdateDialog(context, info);
      }
    } on UpdateException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showAppToast(context, e.message);
    }
  }
}

/// "正在检查更新"小弹窗：白色圆角卡 + 转圈，不可点遮罩关闭
class _CheckingDialog extends StatelessWidget {
  const _CheckingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              '正在检查更新…',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
