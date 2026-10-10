import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/money_util.dart';
import 'category_avatar.dart';

/// 借条流水行（共享组件）：首页明细 / 账户流水页 / 借条台账三处通用
///
/// 行结构与账单行 [BillListItem] 完全同构：
/// · 左侧 40px 灰色方向圆标（借出 ↗ / 借入 ↙）+ 借据照片相机角标；
/// · 中间主标题 = 人名；副标题 =「未计入」胶囊 ｜ 备注（单行省略）；
/// · 右侧金额按资金进出着色：借出 -¥ 红（钱出）、借入 +¥ 绿（钱入），
///   金额下方为关联账户小字。
class DebtFlowRow extends StatelessWidget {
  const DebtFlowRow({
    super.key,
    required this.note,
    required this.onTap,
    this.hasImage = false,
    this.accountLine,
  });

  final DebtNote note;
  final VoidCallback onTap;

  /// 是否带借据照片：方向头像右下角叠相机小角标（与账单行同款）。
  /// 列表保持极简——不显示缩略图也不显示数量，照片入口只在详情弹窗
  final bool hasImage;

  /// 金额下方关联账户小字：未关联账户为 null（不显示该行）
  final String? accountLine;

  @override
  Widget build(BuildContext context) {
    final isLendOut = note.direction == DebtDirection.lendOut;
    final hasNote = note.note != null && note.note!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.cardPadding,
          vertical: AppDimens.gapMd,
        ),
        child: Row(
          children: [
            // 方向圆标 + 借据照片相机角标：与账单行完全同款
            Stack(
              clipBehavior: Clip.none,
              children: [
                CategoryAvatar(
                  name: isLendOut ? '借出' : '借入',
                  iconCode: isLendOut
                      ? Icons.north_east.codePoint
                      : Icons.south_west.codePoint,
                  color: 0xFF8A8A8A,
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
                    note.personName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  // 「未计入」胶囊与备注同一行（同账单行「省¥x｜备注」），
                  // 二者至少其一时整行才出现
                  if (!note.includeInTotal || hasNote) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (!note.includeInTotal) _excludedChip(),
                        if (!note.includeInTotal && hasNote) ...[
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
                        if (hasNote)
                          Expanded(
                            child: Text(
                              note.note!,
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
                ],
              ),
            ),
            const SizedBox(width: AppDimens.gapSm),
            // 金额 + 关联账户小字纵排（与账单行右侧完全同款）
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${isLendOut ? '-' : '+'}'
                  '${MoneyUtil.centsToYuanTrimmed(note.amountCents)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    // 借出 = 钱出（红），借入 = 钱入（绿）：资金进出口径
                    color: isLendOut ? AppColors.expense : AppColors.income,
                  ),
                ),
                if (accountLine != null && accountLine!.isNotEmpty) ...[
                  const SizedBox(height: 2),
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

  /// 「未计入」小胶囊：浅灰底 + 灰色小字（关闭统计开关的借条仅台账展示）
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
