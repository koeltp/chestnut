import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/asset_repository.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/section_card.dart';
import 'debt_note_list_page.dart';

/// 金额统一展示：模糊态显示占位符；负数带负号
/// （资产页各卡片共用，含组聚合列表）
String fmtAssetAmount(int cents, bool masked) {
  if (masked) return '¥ ****';
  final text = MoneyUtil.centsToYuanGroupedTrimmed(cents.abs());
  return '${cents < 0 ? '-' : ''}¥$text';
}

/// 净值总览卡：总净值大数字 + 总资产/总负债两列（钱迹式布局）
class NetValueCard extends StatelessWidget {
  const NetValueCard({super.key, required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return SectionCard(
      onTap: () => context.read<AssetProvider>().toggleMasked(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '总净值（总资产 − 总负债）',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimens.gapSm),
          Text(
            fmtAssetAmount(summary.netCents, masked),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          Row(
            children: [
              Expanded(
                child: _TotalColumn(
                  label: '总资产',
                  cents: summary.totalAssetCents,
                  color: AppColors.primary,
                  masked: masked,
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: AppColors.divider,
              ),
              Expanded(
                child: _TotalColumn(
                  label: '总负债',
                  cents: -summary.totalLiabilityCents,
                  color: AppColors.expense,
                  masked: masked,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 净值卡内两列之一：标签 + 金额在各自区块内居中
class _TotalColumn extends StatelessWidget {
  const _TotalColumn({
    required this.label,
    required this.cents,
    required this.color,
    required this.masked,
  });

  final String label;
  final int cents;
  final Color color;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          fmtAssetAmount(cents, masked),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 负债率卡：资产/负债项数 + 负债率 + 进度条
class LiabilityRateCard extends StatelessWidget {
  const LiabilityRateCard({super.key, required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    final rate = summary.liabilityRate;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '负债率',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${summary.assetCount} 项资产 | ${summary.liabilityCount} 项负债',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(rate * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: rate > 0.5 ? AppColors.expense : AppColors.income,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppDimens.gapMd),
              Expanded(
                child: Text(
                  masked
                      ? '负债占资产的 ****'
                      : '负债占资产 '
                          '¥${MoneyUtil.centsToYuanGroupedTrimmed(summary.totalLiabilityCents)}'
                          ' / '
                          '¥${MoneyUtil.centsToYuanGroupedTrimmed(summary.totalAssetCents)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 6,
              backgroundColor: AppColors.fill,
              valueColor: AlwaysStoppedAnimation(
                rate > 0.5 ? AppColors.expense : AppColors.income,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 总借出/借入卡：借条台账总量（含"不计入统计"的记录），点击进借条列表
class DebtNoteCard extends StatelessWidget {
  const DebtNoteCard({super.key, required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return SectionCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DebtNoteListPage()),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.north_east,
                  size: 18,
                  color: AppColors.income,
                ),
                const SizedBox(width: AppDimens.gapSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '总借出',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        fmtAssetAmount(summary.lendOutAllCents, masked),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.income,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.divider),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: AppDimens.gapMd),
              child: Row(
                children: [
                  const Icon(
                    Icons.south_west,
                    size: 18,
                    color: AppColors.expense,
                  ),
                  const SizedBox(width: AppDimens.gapSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '总借入',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          fmtAssetAmount(summary.borrowInAllCents, masked),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.expense,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
