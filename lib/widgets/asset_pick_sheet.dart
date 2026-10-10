import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/money_util.dart';
import 'asset_circle_icon.dart';

/// 账户选择底部弹窗：记一笔页选择资产账户用
///
/// 平铺列出未归档账户（资产在前负债在后，与资产管理页同序），
/// 风格对齐主流记账 App：资产单行紧凑；信用卡带额度副行——
/// 额度使用进度条 + 还款倒计时 + 可用额度，点击行即选中返回。
/// [allowNone] = 支出/收入模式允许"不关联账户"；转账模式两个入口
/// 都必选，不显示该项。
/// 返回 `(Asset?, bool)?`：点列表项 = (选中资产，"不关联"为 null, true)；
/// 下滑关闭/点外部 = null（取消操作，调用方保持原值不变）。
Future<(Asset?, bool)?> showAssetPickSheet(
  BuildContext context, {
  required List<Asset> assets,
  bool allowNone = false,
}) {
  return showModalBottomSheet<(Asset?, bool)>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _AssetPickSheet(assets: assets, allowNone: allowNone),
  );
}

class _AssetPickSheet extends StatelessWidget {
  const _AssetPickSheet({required this.assets, required this.allowNone});

  final List<Asset> assets;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        // 账户很多时限高滚动，一般个位数账户由内容自适应
        constraints: const BoxConstraints(maxHeight: 520),
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppDimens.radiusHeader),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                '选择账户',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (assets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Text(
                  '还没有资产账户，先到"我的-资产管理"添加一个吧',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: assets.length + (allowNone ? 1 : 0),
                itemBuilder: (context, i) {
                  // "不关联账户"固定在列表首位（支出/收入模式）
                  if (allowNone && i == 0) {
                    return ListTile(
                      leading: Container(
                        width: AppDimens.iconTile,
                        height: AppDimens.iconTile,
                        decoration: const BoxDecoration(
                          color: AppColors.fill,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.block_outlined,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      title: const Text(
                        '不关联账户',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      // 不关联 = 确认"选择空"，与下滑取消（null record）区分
                      onTap: () => Navigator.of(context).pop((null, true)),
                    );
                  }
                  return _assetTile(context, assets[i - (allowNone ? 1 : 0)]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 账户行：图标 + 名称 + 右侧余额；信用卡（已设额度）额外展示
  /// 额度进度条、还款倒计时与可用额度，点击即选（无勾选标记）
  Widget _assetTile(BuildContext context, Asset asset) {
    final isLiability = asset.kind == AssetKind.liability;
    final limit = asset.creditLimitCents ?? 0;
    final hasLimit = isLiability && limit > 0;
    // 信用卡显示红色欠款（溢缴款按普通余额展示）；资产正常色
    final owed = isLiability && asset.valueCents > 0;
    final balance = MoneyUtil.centsToYuanGroupedTrimmed(asset.valueCents);
    return InkWell(
      onTap: () => Navigator.of(context).pop((asset, true)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          // 信用卡副行顶在名称下方；资产行内容少，整体垂直居中
          crossAxisAlignment:
              hasLimit ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            AssetCircleIcon(category: asset.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
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
                      const SizedBox(width: 8),
                      Text(
                        owed ? '-¥$balance' : '¥$balance',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: owed ? AppColors.expense : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (hasLimit) ...[
                    const SizedBox(height: 8),
                    // 额度使用进度条：欠款占额度的比例
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (asset.valueCents / limit).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: AppColors.fill,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _repayHint(asset) ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '可用:¥${MoneyUtil.centsToYuanGroupedTrimmed(limit - asset.valueCents)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 还款倒计时文案：距下一个还款日（repayDay 为每月几号）的天数；
  /// 未设还款日返回 null（副行只显示可用额度）
  String? _repayHint(Asset asset) {
    final day = asset.repayDay;
    if (day == null || day < 1 || day > 31) return null;
    final now = DateTime.now();
    // 本月还款日已过则算下月（month 超 12 时 DateTime 自动进位到次年）
    var next = DateTime(now.year, now.month, day);
    if (!next.isAfter(now)) next = DateTime(now.year, now.month + 1, day);
    return '${next.difference(now).inDays}天内还款';
  }
}
