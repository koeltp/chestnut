import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/enums.dart';
import '../providers/debt_note_provider.dart';
import '../theme/app_colors.dart';
import '../utils/money_util.dart';
import '../utils/show_toast.dart';
import 'detail_widgets.dart';

/// 借条还款详情底部弹窗：点击明细中的还款条目时展示
///
/// 修改语义不存在（记错直接删了重记），提供删除（二次确认，
/// 余额联动与利息账单自动撤销）
Future<void> showRepaymentDetailSheet(
  BuildContext context, {
  required DebtNoteRepayment repayment,
  required DebtNote? note,
}) {
  final provider = context.read<DebtNoteProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => _RepaymentDetailBody(
      repayment: repayment,
      note: note,
      provider: provider,
    ),
  );
}

class _RepaymentDetailBody extends StatelessWidget {
  const _RepaymentDetailBody({
    required this.repayment,
    required this.note,
    required this.provider,
  });

  final DebtNoteRepayment repayment;
  final DebtNote? note;
  final DebtNoteProvider provider;

  Future<void> _confirmDelete(BuildContext sheetContext) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: const Text('删除还款记录'),
        content: const Text(
          '确定删除这笔还款吗？借条余额与关联账户将同步恢复，拆分的利息账单一并删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    try {
      await provider.deleteRepayment(repayment);
    } catch (_) {
      // 删除失败静默不打扰（弹窗已关），余额联动在事务内保证一致性
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBorrowIn = note?.direction != DebtDirection.lendOut;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isBorrowIn ? '还款详情' : '收款详情',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                DetailPill(
                  '删除',
                  danger: true,
                  onTap: () => _confirmDelete(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DetailInfoRow(
              label: isBorrowIn ? '还款给' : '收款来自',
              child: Text(
                note?.personName ?? '已删除的借条',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            DetailInfoRow(
              label: '合计',
              child: Text(
                '${isBorrowIn ? '-' : '+'}'
                '${MoneyUtil.centsToYuanGroupedTrimmed(repayment.amountCents)} CNY',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isBorrowIn ? AppColors.expense : AppColors.income,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (repayment.interestCents != null) ...[
              const Divider(height: 1, color: AppColors.divider),
              DetailInfoRow(
                label: '本金',
                child: Text(
                  '${MoneyUtil.centsToYuanTrimmed(
                    repayment.amountCents - repayment.interestCents!,
                  )} CNY',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              DetailInfoRow(
                label: '利息',
                child: Text(
                  '${MoneyUtil.centsToYuanTrimmed(repayment.interestCents!)} CNY',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
            const Divider(height: 1, color: AppColors.divider),
            DetailInfoRow(
              label: isBorrowIn ? '还款日期' : '收款日期',
              child: Text(
                _fmtDate(repayment.repaidAt),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (repayment.note != null && repayment.note!.isNotEmpty) ...[
              const Divider(height: 1, color: AppColors.divider),
              DetailInfoRow(
                label: '备注',
                child: Text(
                  repayment.note!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
