import 'package:flutter/material.dart';

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
    this.note,
    this.location,
    this.dateLabel,
    this.onTap,
    this.onLongPress,
  });

  final String name;
  final int iconCode;
  final int colorValue;
  final BillType type;
  final int amountCents;
  final String? note;

  /// 消费地点（记账定位），无则不显示
  final String? location;

  /// 账单日期文案（如"10月4日"，分类统计明细等无日期分组头的场景显示），
  /// 无则不显示
  final String? dateLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isExpense = type == BillType.expense;
    final color = Color(colorValue);
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
            _CategoryIcon(iconCode: iconCode, color: color),
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
                  if (dateLabel != null && dateLabel!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      dateLabel!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
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
            Text(
              '${isExpense ? '-' : '+'}${MoneyUtil.centsToYuanTrimmed(amountCents)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isExpense ? AppColors.textPrimary : AppColors.income,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类圆形图标（列表条目与统计排行共用样式）
class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.iconCode, required this.color});

  final int iconCode;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDimens.iconTile,
      height: AppDimens.iconTile,
      decoration: BoxDecoration(color: AppColors.tint(color), shape: BoxShape.circle),
      child: Icon(
        // ignore: non_const_argument_for_const_parameter
        IconData(iconCode, fontFamily: 'MaterialIcons'),
        color: color,
        size: 21,
      ),
    );
  }
}
