import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/asset_category.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/asset_circle_icon.dart';
import '../../widgets/institution_logo.dart';
import '../../widgets/section_card.dart';
import 'asset_detail_page.dart';
import 'asset_summary_cards.dart';

/// 组聚合列表：每种资产类型一张独立卡片（钱迹式），组行为
/// 图标 + 组名 + 项数 + 合计，点击原地展开组内账户列表，点账户行
/// 进流水明细页。没有账户的组整个不显示，添加首个账户后才出现。
/// 合计口径：未归档且计入总资产的账户。
class GroupListSection extends StatefulWidget {
  const GroupListSection({super.key});

  @override
  State<GroupListSection> createState() => _GroupListSectionState();
}

class _GroupListSectionState extends State<GroupListSection> {
  /// 已展开的组名集合（组名即分类体系主键）
  final Set<String> _expanded = {};

  void _toggle(String groupName) {
    setState(() {
      if (!_expanded.remove(groupName)) _expanded.add(groupName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Asset>>(
      stream: context.read<AssetProvider>().activeStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final list = snapshot.data!;
        // 分类名 -> 组：一次遍历完成分桶
        final byGroup = <AssetGroupDef, List<Asset>>{};
        for (final a in list) {
          byGroup.putIfAbsent(AssetGroups.groupOf(a.category), () => []).add(a);
        }
        // 空组不渲染：用户 + 添加首个账户后该组卡片才出现
        final groups = AssetGroups.all
            .where((g) => (byGroup[g] ?? const []).isNotEmpty)
            .toList();
        return Column(
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              SectionCard(
                padding: EdgeInsets.zero,
                child: _GroupRow(
                  group: groups[i],
                  items: byGroup[groups[i]]!,
                  expanded: _expanded.contains(groups[i].name),
                  onToggle: () => _toggle(groups[i].name),
                ),
              ),
              // 组卡片之间的间距（列表首尾由页面统一控制）
              if (i < groups.length - 1)
                const SizedBox(height: AppDimens.gapSection),
            ],
          ],
        );
      },
    );
  }
}

/// 组行：图标 + 组名 + 项数 + 合计 + 旋转 chevron；展开后组内账户
/// 行直接挂在下方（行间分割线，与组行同卡）
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.items,
    required this.expanded,
    required this.onToggle,
  });

  final AssetGroupDef group;
  final List<Asset> items;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    // 组合计只含"计入总资产"的账户（关闭开关的仅展示不计入）
    final total = items
        .where((a) => a.includeInNet)
        .fold<int>(0, (s, a) => s + a.valueCents);
    final color = AssetGroups.colorOf(group.categories.first.name);
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.pagePadding,
              vertical: AppDimens.gapMd,
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
                  child: Icon(group.icon, color: color, size: 21),
                ),
                const SizedBox(width: AppDimens.gapMd),
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${items.length} 项',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppDimens.gapMd),
                Text(
                  fmtAssetAmount(
                      group.kind == AssetKind.liability ? -total : total, masked),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: group.kind == AssetKind.liability
                        ? AppColors.expense
                        : AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                // 展开/收起指示：右 chevron 旋转 90° 变下 chevron
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            _AssetRow(asset: items[i]),
          ],
        ],
      ],
    );
  }
}

/// 资产行（组展开列表内）：点击进账户流水页
class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    final isLiability = asset.kind == AssetKind.liability;
    final subtitle = _subtitleOf(asset);
    final display =
        '¥${MoneyUtil.centsToYuanGroupedTrimmed(asset.valueCents)}';
    return InkWell(
      // 点行进账户流水页；总资产卡整卡可点进编辑页
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AssetDetailPage(assetId: asset.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
          vertical: AppDimens.gapMd,
        ),
        child: Row(
          children: [
            // 机构配了品牌 logo 则显示机构 logo，否则回落分类图标
            institutionHasLogo(asset.institution)
                ? InstitutionLogo(name: asset.institution!)
                : AssetCircleIcon(category: asset.category),
            const SizedBox(width: AppDimens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      // 未计入净值标记：关闭"计入总资产"的账户
                      if (!asset.includeInNet) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.fill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '未计入',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppDimens.gapSm),
            Text(
              masked ? '¥ ****' : display,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isLiability ? AppColors.expense : AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 行副标题：备注优先；信用卡账户展示额度/出账日/还款日摘要
  String? _subtitleOf(Asset asset) {
    if (asset.kind == AssetKind.liability &&
        AssetGroups.groupOf(asset.category) == AssetGroups.credit) {
      final parts = <String>[
        if (asset.creditLimitCents != null)
          '额度 ¥${MoneyUtil.centsToYuanGroupedTrimmed(asset.creditLimitCents!)}',
        if (asset.billDay != null) '出账日 ${asset.billDay}',
        if (asset.repayDay != null) '还款日 ${asset.repayDay}',
      ];
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    final note = asset.note;
    if (note != null && note.isNotEmpty) return note;
    return null;
  }
}
