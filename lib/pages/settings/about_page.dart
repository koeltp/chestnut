import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../utils/show_toast.dart';
import '../../widgets/section_card.dart';
import '../privacy/privacy_policy_page.dart';

/// 关于页：版本信息、隐私政策入口、开源仓库与反馈渠道、版权与许可声明
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _versionName = '';

  /// 开源仓库地址
  static final Uri _repoUrl = Uri.parse('https://github.com/koeltp/chestnut');

  /// 反馈邮箱：预置收件人与主题，降低用户输入成本
  static final Uri _emailUri = Uri(
    scheme: 'mailto',
    path: 'tp@taipi.top',
    query: 'subject=${Uri.encodeComponent('栗子记账反馈')}',
  );

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _versionName = info.version);
    });
  }

  /// 统一的外部链接拉起：失败时给出提示（设备无浏览器 / 无邮件客户端）
  Future<void> _open(Uri uri, String failHint) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppToast(context, failHint);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('关于'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          32,
        ),
        children: [
          _buildHeader(),
          const SizedBox(height: AppDimens.gapSection),
          _buildIntroCard(),
          const SizedBox(height: AppDimens.gapSection),
          _buildLinkCard(context),
          const SizedBox(height: AppDimens.gapSection),
          _buildCopyright(),
        ],
      ),
    );
  }

  /// Logo + 名称 + 版本号
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: AppColors.headerGradient,
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.all(14),
          child: Image.asset(
            'assets/images/logo.png',
            width: 60,
            height: 60,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '栗子记账',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _versionName.isEmpty ? 'Chestnut' : 'v$_versionName',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 一句话简介
  Widget _buildIntroCard() {
    return SectionCard(
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Text(
          '一款无广告、无账号、数据完全本地的记账 App。\n'
          '快速记账、两级分类、统计图表、预算提醒、记账定位与本地备份，'
          '账目数据始终只属于你自己。',
          style: TextStyle(
            fontSize: 14,
            height: 1.7,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 链接菜单：隐私政策（应用内页面）/ 开源仓库 / 意见反馈
  Widget _buildLinkCard(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _item(
            icon: Icons.privacy_tip_outlined,
            color: AppColors.primary,
            title: '隐私政策',
            value: '数据如何存储与使用',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyPage()),
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          _item(
            icon: Icons.code,
            color: AppColors.primaryDeep,
            title: '开源仓库',
            value: 'github.com/koeltp/chestnut',
            onTap: () => _open(_repoUrl, '无法打开浏览器'),
          ),
          const Divider(indent: 16, endIndent: 16),
          _item(
            icon: Icons.mail_outline,
            color: AppColors.expense,
            title: '意见反馈',
            value: 'tp@taipi.top',
            onTap: () => _open(_emailUri, '未找到邮件应用'),
          ),
        ],
      ),
    );
  }

  /// 底部版权与许可
  Widget _buildCopyright() {
    return const Column(
      children: [
        Text(
          'Copyright © 2026 taipi.top',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        SizedBox(height: 6),
        Text(
          '基于 MIT License 开源 · 官网 taipi.top',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 链接菜单项（与我的页菜单同构，独立实现避免跨页私有方法依赖）
  Widget _item({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
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
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
