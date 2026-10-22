import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/update_dialog.dart';
import 'backup_page.dart';

/// 更新记录页：完整展示历次版本的变更说明。
///
/// 双数据源：
/// - 本地 CHANGELOG.md（与仓库根目录同源，发版时随包更新），按
///   `## [版本] - 日期` 分段、`### 分组` 收条目解析后渲染，离线可看；
/// - 线上 latest.json 清单：仅当线上版本比本机新时，顶部展示"可更新"
///   卡片（与更新弹窗同源的数据），带一键更新入口。
/// 更新日志弹层底部「查看全部更新记录」跳到这里。
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  /// 解析结果；加载完成前为 null（页面显示转圈）
  List<ChangelogVersion>? _versions;

  /// 线上比本机新的版本：拉取成功且确有新版才非空，列表顶部展示
  UpdateInfo? _remoteUpdate;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('CHANGELOG.md').then(_parse).then((versions) {
      if (mounted) setState(() => _versions = versions);
    });
    _loadRemoteUpdate();
  }

  /// 拉线上清单做版本比较：仅当线上构建号大于本机时展示最新版卡。
  /// 已是最新时不展示——本地 CHANGELOG.md 首条就是当前版本，重复展示
  /// 会像同一版发了两遍；网络/清单失败静默跳过：记录页必须离线可看
  Future<void> _loadRemoteUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final latest = await UpdateService().fetchLatestManifest();
      if (latest.versionCode <= currentCode) return;
      if (mounted) setState(() => _remoteUpdate = latest);
    } catch (_) {
      // 无网/清单异常：只看本地记录即可，不打扰
    }
  }

  /// CHANGELOG.md → 版本列表。文件由人和脚本共同维护，解析对未知行
  /// 一律忽略：坏行宁可少显示也不让页面挂掉
  List<ChangelogVersion> _parse(String markdown) {
    final versions = <ChangelogVersion>[];
    ChangelogVersion? current;
    ChangelogSection? section;

    for (final line in markdown.split('\n')) {
      final versionMatch = RegExp(r'^## \[(.+?)\] - (.+?)\s*$').firstMatch(line);
      if (versionMatch != null) {
        current = ChangelogVersion(
          version: versionMatch.group(1)!,
          date: versionMatch.group(2)!,
        );
        versions.add(current);
        section = null;
        continue;
      }
      if (current == null) continue; // 第一个版本段之前的内容（标题、说明）
      final sectionMatch = RegExp(r'^### (.+?)\s*$').firstMatch(line);
      if (sectionMatch != null) {
        section = ChangelogSection(title: sectionMatch.group(1)!);
        current.sections.add(section);
        continue;
      }
      final itemMatch = RegExp(r'^- (.+?)\s*$').firstMatch(line);
      if (itemMatch != null && section != null) {
        section.items.add(itemMatch.group(1)!);
      }
    }
    return versions;
  }

  @override
  Widget build(BuildContext context) {
    final versions = _versions;
    final remote = _remoteUpdate;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('更新记录'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      body: versions == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pagePadding,
                AppDimens.gapSection,
                AppDimens.pagePadding,
                32,
              ),
              itemCount: versions.length + (remote == null ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: AppDimens.gapSection),
              itemBuilder: (_, i) {
                // 首位固定给线上最新版卡，历史版本顺延
                if (remote != null && i == 0) return _LatestCard(info: remote);
                return _VersionCard(version: versions[remote == null ? i : i - 1]);
              },
            ),
    );
  }
}

/// 单个版本的变更卡片：版本号 + 日期 + 分组条目
class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.version});

  final ChangelogVersion version;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(AppDimens.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${version.version}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                version.date,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          for (final section in version.sections) ...[
            const SizedBox(height: 12),
            Text(
              section.title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDeep,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in section.items) _NoteRow(text: item),
          ],
        ],
      ),
    );
  }
}

/// CHANGELOG.md 的一个版本段
class ChangelogVersion {
  ChangelogVersion({required this.version, required this.date});

  final String version;
  final String date;

  /// 变更分组（新增/修复/变更…），按文件中出现顺序
  final List<ChangelogSection> sections = [];
}

/// 版本段内的一个分组（如"新增"）及其条目
class ChangelogSection {
  ChangelogSection({required this.title});

  final String title;
  final List<String> items = [];
}

/// 线上最新版卡片：仅当线上版本比本机新时出现在列表顶部。
/// 数据来自 latest.json 清单（与更新弹窗同源），随版本发布自动更新，
/// 不依赖本包内的 CHANGELOG.md 快照；带一键更新入口
class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final date = info.publishedAtLocalText;
    return SectionCard(
      padding: const EdgeInsets.all(AppDimens.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${info.versionName}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              // "可更新"徽章：与下方已安装的历史版本卡区分
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '可更新',
                  style: TextStyle(fontSize: 10, color: AppColors.primary),
                ),
              ),
              const Spacer(),
              if (date != null)
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final note in info.releaseNotes) _NoteRow(text: note),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              onPressed: () => _update(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '立即更新',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 进更新弹窗：与"我的页-检查更新"同一流程；
  /// 用户选了"去备份"就在记录页之上继续跳备份页
  Future<void> _update(BuildContext context) async {
    final result = await showUpdateDialog(context, info);
    if (result == UpdateDialogResult.goBackup && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BackupPage()),
      );
    }
  }
}

/// 圆点变更条目：历史版本卡与线上最新版卡共用
class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 8),
            child: Icon(Icons.circle, size: 5, color: AppColors.textSecondary),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
