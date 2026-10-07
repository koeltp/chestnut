import 'package:flutter/material.dart';

import 'category_avatar.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/money_util.dart';

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

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isExpense = type == BillType.expense;
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
            CategoryAvatar(name: name, iconCode: iconCode, color: colorValue),
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
                  if (location != null && location!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
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
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppDimens.gapSm),
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
                : Text(
                    '${isExpense ? '-' : '+'}${MoneyUtil.centsToYuanTrimmed(amountCents)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color:
                          isExpense ? AppColors.textPrimary : AppColors.income,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
