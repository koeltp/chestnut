import 'package:flutter/material.dart';

import '../data/database.dart';
import 'category_avatar.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/money_util.dart';

/// 条目"金额下方账户小字"的统一口径：转账显示"转出账户 -> 转入账户"
/// （方向由数据决定，转出在前），支出/收入显示记这笔时选的账户名；
/// 未关联账户返回 null（不显示该行）。首页/统计/账户流水三处共用
String? billAccountLine(Bill bill, Map<int, Asset> assets) {
  switch (bill.type) {
    case BillType.transfer:
      final from = assets[bill.assetId]?.name ?? '已删除账户';
      final to = assets[bill.toAssetId]?.name ?? '已删除账户';
      return '$from -> $to';
    case BillType.expense:
    case BillType.income:
      final id = bill.assetId;
      if (id == null) return null;
      return assets[id]?.name ?? '已删除账户';
  }
}

/// 借条"金额下方关联账户小字"：按 relatedAssetId 查名，
/// 未关联返回 null（不显示），账户被删除兜底「已删除账户」。
/// 首页/账户流水/借条台账三处共用
String? debtAccountLine(DebtNote note, Map<int, Asset> assets) {
  final id = note.relatedAssetId;
  if (id == null) return null;
  return assets[id]?.name ?? '已删除账户';
}

/// 账单条目
///
/// 首页账单卡片内的基础单元：分类圆形图标 + 名称备注 + 类型着色金额。
/// 尺寸与配色全部取自设计规范，保证与其它列表观感一致。
class BillListItem extends StatelessWidget {
  const BillListItem({
    super.key,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    required this.type,
    required this.amountCents,
    this.discountCents,
    this.note,
    this.location,
    this.tags,
    this.hasImage = false,
    this.accountLine,
    this.onTap,
    this.onLongPress,
  });

  final String name;
  final int iconCode;
  final int colorValue;
  final BillType type;
  final int amountCents;

  /// 优惠金额（分）；非空且 >0 时备注行前缀显示绿色"省 ¥x"
  final int? discountCents;
  final String? note;

  /// 消费地点（记账定位），无则不显示
  final String? location;

  /// 该账单的标签列表（可为空）
  final List<Tag>? tags;

  /// 是否带图片：分类头像右下角叠相机小角标。列表保持极简——
  /// 不显示缩略图也不显示数量，图片入口只在详情弹窗
  final bool hasImage;

  /// 金额下方账户小字：转账"转出 -> 转入"、收支显示所选账户名；
  /// null/空不显示。口径见 [billAccountLine]
  final String? accountLine;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isExpense = type == BillType.expense;
    // 转账不计收支：金额无 +/- 前缀、中性色（余额影响在双方账户各自体现）
    final isTransfer = type == BillType.transfer;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.cardPadding,
          vertical: AppDimens.gapMd,
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CategoryAvatar(
                  name: name,
                  iconCode: iconCode,
                  color: colorValue,
                ),
                // 相机角标：白底圆片叠在头像右下角内侧。
                // 内嵌不越界——负偏移在某些裁剪容器下会被裁掉看不见
                if (hasImage)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.divider,
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.photo_camera,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppDimens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  // 优惠与备注同一行：省 ¥x（绿）｜ 备注（灰），
                  // 只有二者至少其一时整行才出现
                  if ((discountCents != null && discountCents! > 0) ||
                      (note != null && note!.isNotEmpty)) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (discountCents != null && discountCents! > 0)
                          Text(
                            '省 ¥${MoneyUtil.centsToYuanTrimmed(discountCents!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.income,
                            ),
                          ),
                        if ((discountCents != null && discountCents! > 0) &&
                            note != null &&
                            note!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '|',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.divider,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (note != null && note!.isNotEmpty)
                          Expanded(
                            child: Text(
                              note!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  // 标签与定位合并一行：标签胶囊 ｜ 📍 定位。
                  // 标签数量通常很少，固定宽度在前；定位 Expanded 省略。
                  if ((tags != null && tags!.isNotEmpty) ||
                      (location != null && location!.isNotEmpty)) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (tags != null && tags!.isNotEmpty)
                          Flexible(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                for (final t in tags!) _MiniTagChip(tag: t),
                              ],
                            ),
                          ),
                        if ((tags != null && tags!.isNotEmpty) &&
                            location != null &&
                            location!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '|',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.divider,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (location != null && location!.isNotEmpty)
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.place_outlined,
                                  size: 11,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    location!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppDimens.gapSm),
            // 金额 + 账户小字纵排（小字：转账"转出 -> 转入"/收支所选账户）
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 免单（实付 0 且有优惠）直接显示绿色"免单"，比"¥0"直观
                (amountCents == 0 && discountCents != null && discountCents! > 0)
                    ? const Text(
                        '免单',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.income,
                        ),
                      )
                    : isTransfer
                    ? Text(
                        MoneyUtil.centsToYuanTrimmed(amountCents),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      )
                    : Text(
                        '${isExpense ? '-' : '+'}${MoneyUtil.centsToYuanTrimmed(amountCents)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          // 金额颜色与记一笔输入金额一致：支出红 / 收入绿
                          color:
                              isExpense ? AppColors.expense : AppColors.income,
                        ),
                      ),
                if (accountLine != null && accountLine!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  // 账户名可能较长（转账双方），限宽省略，避免挤压中列
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      accountLine!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表条目内的迷你标签胶囊：浅色底 + 标签色小字
class _MiniTagChip extends StatelessWidget {
  const _MiniTagChip({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final c = Color(tag.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag.name,
        style: TextStyle(
          fontSize: 10,
          color: c,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
