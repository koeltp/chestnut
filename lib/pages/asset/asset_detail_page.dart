import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/bill_image_repository.dart';
import '../../models/asset_category.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../providers/bill_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/debt_note_provider.dart';
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

/// 账户明细页：顶部总资产卡 + 关联流水列表
///
/// 资产管理页点资产行进入。总资产卡整卡可点进编辑页（改资料/改市值
/// 统一走编辑）；流水含支出/收入（按 assetId 匹配）与转账（转出/转入
/// 双向各一条），点条目弹账单详情
class AssetDetailPage extends StatefulWidget {
  const AssetDetailPage({super.key, required this.assetId});

  final int assetId;

  @override
  State<AssetDetailPage> createState() => _AssetDetailPageState();
}

class _AssetDetailPageState extends State<AssetDetailPage> {
  /// 从活跃资产流里找当前账户（编辑保存后流推送，页面自动刷新）
  Asset? _findAsset(List<Asset> assets) {
    for (final a in assets) {
      if (a.id == widget.assetId) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<Asset>>(
          stream: context.read<AssetProvider>().activeStream(),
          builder: (context, snap) => Text(_findAsset(snap.data ?? [])?.name ?? '账户'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          24,
        ),
        children: [
          StreamBuilder<List<Asset>>(
            stream: context.read<AssetProvider>().activeStream(),
            builder: (context, snap) {
              final asset = _findAsset(snap.data ?? []);
              if (asset == null) return const SizedBox.shrink();
              return _SummaryCard(asset: asset);
            },
          ),
          const SizedBox(height: AppDimens.gapSection),
          _FlowListSection(assetId: widget.assetId),
        ],
      ),
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
}

/// 关联流水列表：支出/收入 + 转账双向；点条目弹账单详情
class _FlowListSection extends StatelessWidget {
  const _FlowListSection({required this.assetId});

  final int assetId;

  @override
  Widget build(BuildContext context) {
    final billProvider = context.read<BillProvider>();
    return StreamBuilder<List<Bill>>(
      stream: billProvider.assetBillsStream(assetId),
      builder: (context, billSnap) {
        final bills = billSnap.data ?? const <Bill>[];
        return StreamBuilder<List<DebtNote>>(
          // 关联借条流：借出/借入挂了此账户的钱进出，与账单混排
          stream: context.read<DebtNoteProvider>().debtsOfAssetStream(assetId),
          builder: (context, debtSnap) {
            final debts = debtSnap.data ?? const <DebtNote>[];
            return StreamBuilder<Map<int, Asset>>(
              // id → 资产映射（含归档）：金额下方账户小字查名
              stream: context.read<AssetProvider>().assetsMapStream(),
              builder: (context, assetSnap) {
                final assets = assetSnap.data ?? const <int, Asset>{};
                return StreamBuilder<Map<int, Category>>(
                  stream: context
                      .read<CategoryProvider>()
                      .categoriesMapStream(),
                  builder: (context, catSnap) {
                    final categories =
                        catSnap.data ?? const <int, Category>{};
                    return StreamBuilder<Set<int>>(
                      stream: context
                          .read<BillImageRepository>()
                          .watchBillIdsWithImages(
                            bills.map((b) => b.id).toList(),
                          ),
                      builder: (context, imgSnap) {
                        final imageBillIds = imgSnap.data ?? const <int>{};
                        return StreamBuilder<Set<int>>(
                          // 有借据照片的借条 id（全表流）：方向头像相机角标
                          stream: context
                              .read<DebtNoteProvider>()
                              .photoNoteIdsStream(),
                          builder: (context, debtImgSnap) {
                            final debtImageIds =
                                debtImgSnap.data ?? const <int>{};
                            // 账单 + 借条统一按时间倒序混排（同刻按创建时间）
                            final entries = <_FlowEntry>[
                              for (final b in bills)
                                _FlowEntry(b.date, b.createdAt, bill: b),
                              for (final d in debts)
                                _FlowEntry(d.borrowedAt, d.createdAt, debt: d),
                            ]..sort((x, y) {
                                final byDate = y.date.compareTo(x.date);
                                if (byDate != 0) return byDate;
                                return y.createdAt.compareTo(x.createdAt);
                              });
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
                                            _FlowRow(
                                              bill: entries[i].bill!,
                                              categories: categories,
                                              assets: assets,
                                              hasImage: imageBillIds
                                                  .contains(entries[i].bill!.id),
                                            )
                                          else
                                            DebtFlowRow(
                                              note: entries[i].debt!,
                                              hasImage: debtImageIds
                                                  .contains(entries[i].debt!.id),
                                              accountLine: debtAccountLine(
                                                entries[i].debt!,
                                                assets,
                                              ),
                                              onTap: () =>
                                                  showDebtNoteDetailSheet(
                                                context,
                                                note: entries[i].debt!,
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// 单条流水行：本方视角呈现（转出/转入方向由 assetId 决定）
class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.bill,
    required this.categories,
    required this.assets,
    required this.hasImage,
  });

  final Bill bill;
  final Map<int, Category> categories;
  final Map<int, Asset> assets;
  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    final isTransfer = bill.type == BillType.transfer;
    final category = categories[bill.categoryId];
    return BillListItem(
      name: category?.name ?? (isTransfer ? '转账' : '未知分类'),
      iconCode: category?.iconCode ??
          (isTransfer
              ? Icons.swap_horiz.codePoint
              : Icons.help_outline.codePoint),
      colorValue: category?.colorValue ?? (isTransfer ? 0xFF8A8A8A : 0xFFA8A8A8),
      type: bill.type,
      amountCents: bill.amountCents,
      discountCents: bill.discountCents,
      note: bill.note,
      location: bill.location,
      hasImage: hasImage,
      // 转账"转出 -> 转入"、收支显示所选账户：与首页/统计同口径
      accountLine: billAccountLine(bill, assets),
      onTap: () => showBillDetailSheet(
        context,
        bill: bill,
        categories: categories,
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

/// 账单/借条混排条目：两者取其一
class _FlowEntry {
  const _FlowEntry(this.date, this.createdAt, {this.bill, this.debt});

  final DateTime date;
  final DateTime createdAt;
  final Bill? bill;
  final DebtNote? debt;
}
