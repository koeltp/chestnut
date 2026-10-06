import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 隐私政策原生长文页（离线可看）：
/// 内容与博客网页版 https://www.taipi.top/chestnut/privacy.html 保持一致，
/// 修改时两边同步。首启同意弹窗与"关于"页均跳转至此。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('隐私政策'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: const [
          _Paragraph(
            '栗子记账（以下简称"本应用"）是一款个人开发的本地记账工具。'
            '我们深知账目信息属于高度敏感的个人数据，因此本应用在设计上'
            '遵循"数据不出端"原则：不注册、不登录、无服务器存储。',
          ),
          _SectionTitle('一、我们收集的信息'),
          _Paragraph(
            '本应用不收集、不上传你的任何账目数据（金额、分类、备注、时间、位置等），'
            '这些数据仅保存在你设备的应用私有目录中。\n'
            '本应用不接入任何账号体系、广告 SDK、统计分析 SDK 与崩溃上报 SDK，'
            '不申请手机号、通讯录等个人身份信息。',
          ),
          _SectionTitle('二、权限使用说明'),
          _Paragraph(
            '1. 网络访问：仅用于地图瓦片加载、地点搜索（高德开放平台）'
            '以及应用内版本更新（访问 www.taipi.top 获取版本清单与安装包），'
            '不会向任何服务器发送你的账目数据。\n'
            '2. 位置信息：仅在你主动使用"记账定位"、地图选点或搜索附近地点时'
            '获取当前位置，不进行任何后台位置采集；定位功能默认关闭，'
            '你可以始终不授予位置权限，不影响记账主功能。\n'
            '3. 生物识别：用于指纹 / 面容快捷解锁。验证在系统本地完成，'
            '本应用不读取、不存储生物特征信息。\n'
            '4. 安装未知来源应用：仅在你确认应用内更新后，'
            '用于拉起系统安装器安装新版本，需你手动授权。',
          ),
          _SectionTitle('三、第三方服务'),
          _Paragraph(
            '本应用的地图与定位能力由高德开放平台（北京高德云图科技有限公司）'
            '提供。在你使用地图相关功能时，高德 SDK 会按照其隐私政策处理'
            '设备标识、网络与位置等信息，用于提供地图服务与安全风控。'
            '高德相关信息处理规则详见《高德隐私权政策》：\n'
            'https://lbs.amap.com/pages/privacy/\n'
            '在你首次启动本应用并同意本政策之前，我们不会初始化高德 SDK，'
            '也不会向其发起任何请求。',
          ),
          _SectionTitle('四、数据存储、导出与删除'),
          _Paragraph(
            '所有账目数据以 SQLite 数据库形式保存在本机应用私有目录。\n'
            '你可以随时通过"备份与恢复"功能将完整数据库导出为文件，'
            '自行保存或迁移到其他设备；导出文件由你掌控，本应用不保留副本。\n'
            '删除单条账目可在应用内直接操作；卸载本应用将删除全部本地数据，'
            '卸载前请先导出备份。',
          ),
          _SectionTitle('五、应用更新'),
          _Paragraph(
            '本应用通过 www.taipi.top 上托管的版本清单检查更新，'
            '请求仅包含网络访问本身所需的标准信息，不携带任何身份标识或账目数据。'
            '更新安装包经 SHA-256 与文件大小双重校验后才会提示安装。',
          ),
          _SectionTitle('六、未成年人保护'),
          _Paragraph(
            '本应用为通用记账工具，不针对未成年人设计，也不主动收集未成年人信息。',
          ),
          _SectionTitle('七、政策更新'),
          _Paragraph(
            '本政策可能随功能调整而更新，更新后将在本页面与网页版同步公示。'
            '涉及重大变更时，应用内会再次以显著方式提示你确认。',
          ),
          _SectionTitle('八、联系我们'),
          _Paragraph(
            '如对本政策有任何疑问、意见或涉及个人数据的请求，可通过以下方式联系：\n'
            '邮箱：tp@taipi.top\n'
            '站点：https://www.taipi.top\n\n'
            '生效日期：2026 年 10 月 6 日',
          ),
        ],
      ),
    );
  }
}

/// 小节标题
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

/// 正文段落
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
