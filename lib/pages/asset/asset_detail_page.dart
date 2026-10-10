import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/asset_flow_view_repository.dart';
import '../../models/asset_category.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/asset_circle_icon.dart';
import '../../widgets/bill_detail_sheet.dart';
import '../../widgets/bill_list_item.dart';
import '../../widgets/debt_flow_row.dart';
import '../../widgets/debt_note_detail_sheet.dart';
import '../../widgets/section_card.dart';
import '../stats/stats_page.dart';
import 'asset_edit_page.dart';

/// 账户流水页：顶部总资产卡 + 关联流水列表
///
/// 资产管理页点资产行进入。整页只订阅一层 [FlowView]——组装逻辑在
/// [AssetFlowViewRepository] 完成。总资产卡整卡可点进编辑页（改资料/
/// 改市值唯一入口）；流水含支出/收入与转账（转出/转入双向各一条），
/// 点条目弹对应详情
class AssetDetailPage extends StatelessWidget {
  const AssetDetailPage({super.key, required this.assetId});

  final int assetId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FlowView>(
      stream: context
          .read<AssetFlowViewRepository>()
          .watchAssetFlow(assetId),
      builder: (context, snapshot) {
        final view = snapshot.data;
        final asset = view?.asset;
        return Scaffold(
          appBar: AppBar(title: Text(asset?.name ?? '账户')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSection,
              AppDimens.pagePadding,
              24,
            ),
            children: [
              // 账户被删除（非归档）时概览不展示；归档账户照常
              if (asset != null) _SummaryCard(asset: asset),
              if (asset != null)
                const SizedBox(height: AppDimens.gapSection),
              if (view != null) _FlowCard(view: view),
            ],
          ),
        );
      },
    );
  }
}

/// 总资产卡：图标 + 名称/副标题 + 余额大数字；整卡可点进编辑页
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    final isLiability = asset.kind == AssetKind.liability;
    final isCredit =
        AssetGroups.groupOf(asset.category) == AssetGroups.credit;
    // 副标题：信用卡展示额度与出账日/还款日摘要，其余展示备注
    final subtitle = isCredit
        ? [
            if (asset.creditLimitCents != null)
              '额度 ¥${MoneyUtil.centsToYuanGroupedTrimmed(asset.creditLimitCents!)}',
            if (asset.billDay != null) '出账日 ${asset.billDay}',
            if (asset.repayDay != null) '还款日 ${asset.repayDay}',
          ].join(' · ')
        : asset.note;
    return SectionCard(
      // 整卡可点：进编辑页（改资料与改市值唯一入口）
      onTap: () => pushAssetEditPage(
        context,
        category: AssetGroups.categoryOf(asset.category) ??
            AssetGroups.fund.categories.first,
        existing: asset,
      ),
      child: Row(
        children: [
          AssetCircleIcon(category: asset.category),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // 未计入净值标记：关闭"计入总资产"的账户
                    if (!asset.includeInNet) ...[
                      const SizedBox(width: 6),
                      _excludedChip(),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
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
          const SizedBox(width: AppDimens.gapMd),
          Text(
            masked
                ? '¥ ****'
                : '¥${MoneyUtil.centsToYuanGroupedTrimmed(asset.valueCents)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isLiability ? AppColors.expense : AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // 进编辑页的发现性提示：整卡可点，箭头与表单行同款
          const Icon(
            Icons.chevron_right,
            size: 22,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  /// 「未计入」小胶囊：浅灰底 + 灰色小字（关闭计入净值的账户）
  Widget _excludedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
    );
  }
}

/// 流水卡：账单 + 借条已在视图层合并排序，此处仅按条目类型分发渲染
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.view});

  final FlowView view;

  @override
  Widget build(BuildContext context) {
    final entries = view.entries;
    return SectionCard(
      padding: EdgeInsets.zero,
      child: entries.isEmpty
          ? const _EmptyFlow()
          : Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16),
                  if (entries[i].bill != null)
                    _BillFlowRow(
                      bill: entries[i].bill!,
                      view: view,
                    )
                  else
                    DebtFlowRow(
                      note: entries[i].debt!,
                      hasImage: view.debtIdsWithPhotos
                          .contains(entries[i].debt!.id),
                      accountLine:
                          debtAccountLine(entries[i].debt!, view.relatedAssets),
                      onTap: () => showDebtNoteDetailSheet(
                        context,
                        note: entries[i].debt!,
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

/// 流水卡内账单行：分类字典/账户小字/图片标记全部取自视图
class _BillFlowRow extends StatelessWidget {
  const _BillFlowRow({required this.bill, required this.view});

  final Bill bill;
  final FlowView view;

  @override
  Widget build(BuildContext context) {
    final isTransfer = bill.type == BillType.transfer;
    final category = view.categories[bill.categoryId];
    return BillListItem(
      name: category?.name ?? (isTransfer ? '转账' : '未知分类'),
      iconCode: category?.iconCode ??
          (isTransfer
              ? Icons.swap_horiz.codePoint
              : Icons.help_outline.codePoint),
      colorValue: category?.colorValue ??
          (isTransfer ? 0xFF8A8A8A : 0xFFA8A8A8),
      type: bill.type,
      amountCents: bill.amountCents,
      discountCents: bill.discountCents,
      note: bill.note,
      location: bill.location,
      hasImage: view.billIdsWithImages.contains(bill.id),
      // 转账"转出 -> 转入"、收支显示所选账户：与首页同口径
      accountLine: billAccountLine(bill, view.relatedAssets),
      onTap: () => showBillDetailSheet(
        context,
        bill: bill,
        categories: view.categories,
        // 详情里点分类：跳转到该分类的统计页
        onCategoryTap: (c) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StatsPage(initialCategory: c),
          ),
        ),
      ),
    );
  }
}

/// 空态引导：还没有任何关联流水
class _EmptyFlow extends StatelessWidget {
  const _EmptyFlow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          '暂无流水，记账时选择该账户即可关联',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
