import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/asset_repository.dart';
import '../../models/asset_category.dart';
import '../../models/institutions.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_dimens.dart';
import 'asset_archived_section.dart';
import 'asset_category_sheet.dart';
import 'asset_chart_cards.dart';
import 'asset_edit_page.dart';
import 'asset_group_list.dart';
import 'asset_summary_cards.dart';
import 'institution_picker_sheet.dart';

/// 资产管理页：钱迹式净资产盘点
///
/// 自上而下：净资产总览卡 → 负债率卡 → 总借出/借入卡 → 组聚合列表
/// → 净值走势 → 资产构成 → 已归档折叠区。所有区块随数据库流实时刷新。
/// 各区块组件拆在同目录：asset_summary_cards / asset_group_list /
/// asset_chart_cards / asset_archived_section。
class AssetPage extends StatelessWidget {
  const AssetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产管理'),
        actions: [
          // 金额明文/模糊切换：净资产属敏感数字，默认模糊
          IconButton(
            tooltip: '显示/隐藏金额',
            onPressed: () =>
                context.read<AssetProvider>().toggleMasked(),
            icon: Icon(
              context.watch<AssetProvider>().masked
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'asset_add_fab',
        // 钱迹式添加流程：先选分类，再进动态表单页（借出/借入进借条页）。
        // 信用卡/银行卡与投资理财组选完立刻弹机构层（卡类只看银行组，
        // 投资组隐藏银行组），选好的机构带进编辑页；
        // 机构弹层取消也照常进入（机构为选填，编辑页内仍可再选）
        onPressed: () async {
          final def = await showAssetCategorySheet(context);
          if (def == null || !context.mounted) return;
          final isCard = def.name == '信用卡' || def.name == '银行卡';
          final isInvest = AssetGroups.investCategories.contains(def.name);
          String? institution;
          if (isCard || isInvest) {
            institution = await showInstitutionPickerSheet(
              context,
              sections: isCard ? kBankSectionFilter : kInvestSectionFilter,
            );
            if (!context.mounted) return;
          }
          await handleAssetCategoryPicked(context, def, institution: institution);
        },
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          // 底部预留 FAB 高度+边距：已归档展开到底时，
          // 末行"恢复"按钮能滚到 FAB 上方，不被遮挡
          88,
        ),
        children: [
          StreamBuilder<AssetSummary>(
            stream: context.read<AssetProvider>().summaryStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              final summary = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NetValueCard(summary: summary),
                  const SizedBox(height: AppDimens.gapSection),
                  LiabilityRateCard(summary: summary),
                  // 总借出/借入卡：一条借条都没有时不占版面，
                  // 从添加分类选"借出/借入"建第一条后才显示
                  if (summary.lendOutAllCents != 0 ||
                      summary.borrowInAllCents != 0) ...[
                    const SizedBox(height: AppDimens.gapSection),
                    DebtNoteCard(summary: summary),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppDimens.gapSection),
          const GroupListSection(),
          const SizedBox(height: AppDimens.gapSection),
          StreamBuilder<AssetSummary>(
            stream: context.read<AssetProvider>().summaryStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NetTrendCard(
                    currentNetCents: snapshot.data!.snapshotNetCents,
                  ),
                  const SizedBox(height: AppDimens.gapSection),
                  const StructureCard(),
                ],
              );
            },
          ),
          const ArchivedSection(),
        ],
      ),
    );
  }
}
