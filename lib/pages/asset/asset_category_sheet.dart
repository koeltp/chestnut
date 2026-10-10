import 'package:flutter/material.dart';

import '../../models/asset_category.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/asset_circle_icon.dart';

/// 底部弹窗：选择资产分类（钱迹式，按组分节展示彩色圆图标网格）
///
/// [groups] 传入时只显示这些组（编辑态限制同 kind，防止改类型导致
/// 历史快照正负语义翻转）；缺省显示全部组（新增流程）。
/// 返回用户选中的分类定义；点击遮罩/返回键关闭返回 null。
Future<AssetCategoryDef?> showAssetCategorySheet(
  BuildContext context, {
  List<AssetGroupDef>? groups,
}) {
  return showModalBottomSheet<AssetCategoryDef>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategorySheet(groups: groups),
  );
}

class _CategorySheet extends StatelessWidget {
  const _CategorySheet({this.groups});

  final List<AssetGroupDef>? groups;

  @override
  Widget build(BuildContext context) {
    // 编辑态（限定组）过滤借条类：借出/借入是新增流程的借条入口，
    // 不能作为已有资产的分类（否则账户与借条语义混乱）
    final list = groups
        ?.map(
          (g) => AssetGroupDef(
            g.name,
            g.kind,
            g.categories
                .where((c) => c.name != '借出' && c.name != '借入')
                .toList(),
          ),
        )
        .toList();
    final displayGroups = list ?? AssetGroups.all;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          // 拖动条
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppDimens.gapMd),
            child: Text(
              '选择资产分类',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.divider),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                for (final group in displayGroups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  // 每行 4 个分类：彩色圆图标 + 名称
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.92,
                    mainAxisSpacing: 8,
                    children: [
                      for (final def in group.categories)
                        _CategoryCell(
                          def: def,
                          onTap: () => Navigator.of(context).pop(def),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个分类格：圆图标 + 名称，整体可点
class _CategoryCell extends StatelessWidget {
  const _CategoryCell({required this.def, required this.onTap});

  final AssetCategoryDef def;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusControl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AssetCircleIcon(category: def.name, size: 44),
          const SizedBox(height: 6),
          Text(
            def.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
