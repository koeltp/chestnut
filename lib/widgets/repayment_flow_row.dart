import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/money_util.dart';
import 'category_avatar.dart';

/// 借条还款流水行（共享组件）：首页明细 / 账户流水页通用
///
/// 行结构与借条行 [DebtFlowRow] / 账单行完全同构：
/// · 左侧 40px 灰色圆标（还款 ↙ / 收款 ↗）；
/// · 中间主标题 = 对方名（借条已删则显示兜底文案），
///   副标题 =「利息 ¥x」｜备注（单行省略）；
/// · 右侧金额按资金进出着色：借入还款 -¥ 红（钱出）、借出收款 +¥ 绿（钱回）
class RepaymentFlowRow extends StatelessWidget {
  const RepaymentFlowRow({
    super.key,
    required this.repayment,
    required this.debtNote,
    required this.onTap,
  });

  final DebtNoteRepayment repayment;

  /// 所属借条（对方名来源）；null = 借条已删除（防御性兜底）
  final DebtNote? debtNote;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 借条缺失（已删除）时按借入还款渲染：金额着色以资金流出为准
    final isBorrowIn = debtNote?.direction != DebtDirection.lendOut;
    final moneyOut = isBorrowIn;
    final hasInterest = repayment.interestCents != null;
    final hasNote = repayment.note != null && repayment.note!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.cardPadding,
          vertical: AppDimens.gapMd,
        ),
        child: Row(
          children: [
            // 方向圆标：还款（钱出）/ 收款（钱回）
            CategoryAvatar(
              name: isBorrowIn ? '还款' : '收款',
              iconCode: isBorrowIn
                  ? Icons.south_west.codePoint
                  : Icons.north_east.codePoint,
              color: 0xFF8A8A8A,
            ),
            const SizedBox(width: AppDimens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debtNote?.personName ?? '已删除的借条',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (hasInterest || hasNote) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (hasInterest)
                          Text(
                            '利息 ¥${MoneyUtil.centsToYuanTrimmed(repayment.interestCents!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        if (hasInterest && hasNote) ...[
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
                              repayment.note!,
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
            Text(
              '${moneyOut ? '-' : '+'}'
              '¥${MoneyUtil.centsToYuanTrimmed(repayment.amountCents)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                // 借入还款 = 钱出（红），借出收款 = 钱回（绿）：资金进出口径
                color: moneyOut ? AppColors.expense : AppColors.income,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
