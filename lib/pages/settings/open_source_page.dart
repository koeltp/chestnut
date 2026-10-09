import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../utils/show_toast.dart';
import '../../widgets/section_card.dart';

/// 开源说明页：把"无广告、无账号、数据本地"的承诺变成可验证的事实。
///
/// 与隐私政策页同构（长文 + 小节），末尾提供仓库入口与 Flutter
/// 自带的完整许可声明（满足开源许可证对"分发时附带许可文本"的要求）。
class OpenSourcePage extends StatefulWidget {
  const OpenSourcePage({super.key});

  @override
  State<OpenSourcePage> createState() => _OpenSourcePageState();
}

class _OpenSourcePageState extends State<OpenSourcePage> {
  String _versionName = '';

  /// 开源仓库地址（与关于页一致，避免两处口径漂移）
  static final Uri _repoUrl = Uri.parse('https://github.com/koeltp/chestnut');

  @override
  void initState() {
    super.initState();
    // 许可声明弹窗顶部会展示版本号，与关于页取值方式保持一致
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _versionName = info.version);
    });
  }

  /// 统一的外部链接拉起：失败时给出提示（设备无浏览器）
  Future<void> _open(Uri uri, String failHint) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppToast(context, failHint);
  }

  /// 拉起 Flutter 内置的许可声明页：自动汇总全部依赖的实际许可文本，
  /// 无需手动维护逐个组件的许可内容，也避免写错许可类型
  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: '栗子记账',
      applicationVersion: _versionName.isEmpty ? null : 'v$_versionName',
      applicationIcon: Image.asset(
        'assets/images/logo.png',
        width: 64,
        height: 64,
        fit: BoxFit.contain,
      ),
      applicationLegalese: 'Copyright © 2026 taipi.top',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('开源说明'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          ...const [
            _Paragraph(
              '栗子记账的全部源码以 MIT 许可证公开在 GitHub 上。'
              '我们说"无广告、无账号、数据完全本地"，这句话不需要你'
              '只是相信——开源让承诺可以被验证。',
            ),
            _SectionTitle('一、为什么开源'),
            _Paragraph(
              '闭源应用的安全与隐私完全依赖开发者的口头保证，'
              '而开源把这份保证交给了所有人检验：任何人都可以下载源码'
              '逐行审查，确认应用没有偷偷上传你的账目数据，'
              '也没有埋藏广告与追踪代码。'
              '信任不靠口号，靠可验证。',
            ),
            _SectionTitle('二、你获得的保障'),
            _Paragraph(
              '1. 源码完全公开：功能逻辑与数据流向均可被独立审查；\n'
              '2. 可自行编译：你可以从源码构建属于自己的版本，'
              '不依赖任何人的口头保证；\n'
              '3. 过程透明：问题报告与修复历史在仓库中公开可查；\n'
              '4. 自由支配：可以修改、自用乃至再分发。\n'
              '如果发现任何可疑的代码或行为，'
              '欢迎在仓库提交 Issue 公开质询。',
            ),
            _SectionTitle('三、MIT 许可证'),
            _Paragraph(
              'MIT 是约束最宽松的开源许可证之一：你可以自由地使用、'
              '复制、修改与再分发本应用，唯一的条件是保留原始的'
              '版权与许可声明。与所有开源软件一样，'
              '本软件按"现状"提供，不附带任何形式的担保。',
            ),
            _SectionTitle('四、开源组件'),
            _Paragraph(
              '本应用基于 Flutter 框架构建，并使用众多优秀的开源组件，'
              '主要包括：provider（状态管理）、drift 与 sqlite3'
              '（本地数据库）、fl_chart（统计图表）、intl（格式化）、'
              'geolocator 与 map_launcher（定位与导航）、'
              'local_auth（生物识别解锁）、image_picker 与 photo_view'
              '（账单图片）等。这些组件多采用 MIT、BSD 等宽松许可，'
              '完整的依赖清单与全部许可文本可在下方"开源许可"中查看。',
            ),
            _SectionTitle('五、关于第三方 SDK'),
            _Paragraph(
              '需要如实说明：本应用的地图与定位能力由高德开放平台提供的'
              ' SDK 实现，该 SDK 为闭源二进制组件，不属于本应用的开源范围，'
              '其数据处理规则详见《隐私政策》。本应用承诺的开源，'
              '指的正是仓库中你能看到的全部应用源码。',
            ),
          ],
          const SizedBox(height: 24),
          _buildActionCard(),
        ],
      ),
    );
  }

  /// 底部操作卡：仓库入口 + 完整许可声明
  Widget _buildActionCard() {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _actionRow(
            icon: Icons.code,
            color: AppColors.primaryDeep,
            title: '访问开源仓库',
            value: 'github.com/koeltp/chestnut',
            onTap: () => _open(_repoUrl, '无法打开浏览器'),
          ),
          const Divider(indent: 16, endIndent: 16),
          _actionRow(
            icon: Icons.menu_book_outlined,
            color: AppColors.income,
            title: '开源许可',
            value: '查看全部依赖的许可文本',
            onTap: _showLicenses,
          ),
        ],
      ),
    );
  }

  /// 操作行（与关于页链接菜单同构，独立实现避免跨页私有方法依赖）
  Widget _actionRow({
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
          horizontal: 16,
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

/// 小节标题（与隐私政策页同构）
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// 正文段落（与隐私政策页同构）
class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        height: 1.7,
        color: AppColors.textPrimary,
      ),
    );
  }
}
