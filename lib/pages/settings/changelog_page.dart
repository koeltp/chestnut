import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// 更新记录页：完整展示历次版本的变更说明。
///
/// 数据源是打包进 APK 的 CHANGELOG.md（与仓库根目录同源，发版时随包更新），
/// 按 `## [版本] - 日期` 分段、`### 分组` 收条目解析后渲染；
/// 离线可看、无网络依赖。更新日志弹层底部「查看全部更新记录」跳到这里。
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  /// 解析结果；加载完成前为 null（页面显示转圈）
  List<ChangelogVersion>? _versions;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('CHANGELOG.md').then(_parse).then((versions) {
      if (mounted) setState(() => _versions = versions);
    });
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
              itemCount: versions.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppDimens.gapSection),
              itemBuilder: (_, i) => _VersionCard(version: versions[i]),
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
            for (final item in section.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7, right: 8),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
