import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../services/qianji_import_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/show_toast.dart';
import '../../widgets/section_card.dart';

/// 钱迹导入结果页
///
/// 展示本次导入的统计，并提供"整批撤销"（按批次号删除本次写入的
/// 全部账单，其他数据不受影响）；撤销与完成后都回到备份与恢复页。
class QianjiImportResultPage extends StatefulWidget {
  const QianjiImportResultPage({super.key, required this.result});

  final QianjiImportResult result;

  @override
  State<QianjiImportResultPage> createState() => _QianjiImportResultPageState();
}

class _QianjiImportResultPageState extends State<QianjiImportResultPage> {
  bool _undoing = false;

  Future<void> _undo() async {
    final result = widget.result;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销本次导入'),
        content: Text(
          '将删除本次导入的 ${result.importedCount} 笔账单，'
          '导入前手动记的账不受影响。确定撤销？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('确定撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _undoing = true);
    try {
      final deleted = await QianjiImportService.deleteBatch(
        context.read<AppDatabase>(),
        result.batchId,
      );
      if (!mounted) return;
      showAppToast(context, '已撤销本次导入，删除 $deleted 笔账单');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '撤销失败：$e');
      setState(() => _undoing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(centerTitle: true, title: const Text('导入完成')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          24,
        ),
        children: [
          SectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: AppColors.income,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '成功导入 ${result.importedCount} 笔',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '支出 ${result.expenseCount} 笔 · 收入 ${result.incomeCount} 笔',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (result.fallbackCount > 0 ||
              result.unsupportedCount > 0 ||
              result.badCount > 0) ...[
            const SizedBox(height: AppDimens.gapSection),
            SectionCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '明细说明',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (result.fallbackCount > 0)
                      _detailRow(
                        '${result.fallbackCount} 笔未匹配分类，已计入「其他」',
                      ),
                    if (result.unsupportedCount > 0)
                      _detailRow(
                        '${result.unsupportedCount} 笔为退款/转账等不支持类型，已跳过',
                      ),
                    if (result.badCount > 0)
                      _detailRow('${result.badCount} 笔内容异常，已跳过'),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppDimens.gapSection * 2),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.expense,
              side: const BorderSide(color: AppColors.expense),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _undoing ? null : _undo,
            child: _undoing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.expense,
                    ),
                  )
                : const Text('撤销本次导入'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 5, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
