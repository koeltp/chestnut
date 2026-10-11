import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/asset_category.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/section_card.dart';
import 'asset_delete.dart';

/// 已归档折叠区：归档资产不参与净值，可在此恢复
class ArchivedSection extends StatelessWidget {
  const ArchivedSection({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Asset>>(
      stream: context.read<AssetProvider>().archivedStream(),
      builder: (context, snapshot) {
        final list = snapshot.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppDimens.gapSection),
          child: SectionCard(
            padding: EdgeInsets.zero,
            // ExpansionTile 的 ListTile 需要直接落在 Material 上渲染
            // 墨水涟漪；不包这层 Material，debug 下每次重建都会报
            // "ink 不可见"断言（卡片背景夹在 ListTile 与 Scaffold 的
            // Material 之间）
            child: Material(
              color: Colors.transparent,
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  title: Text(
                    '已归档 (${list.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      _ArchivedRow(asset: list[i]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 归档行：只读展示 + 恢复 / 删除按钮（删除仅对已归档资产暴露）
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.asset});

  final Asset asset;

  Future<void> _delete(BuildContext context) =>
      confirmDeleteAsset(context, asset);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapSm,
      ),
      child: Row(
        children: [
          Icon(
            AssetGroups.iconOf(asset.category),
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppDimens.gapMd),
          Expanded(
            child: Text(
              asset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => context.read<AssetProvider>().setArchived(
              asset,
              archived: false,
            ),
            child: const Text('恢复'),
          ),
          TextButton(
            onPressed: () => _delete(context),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
