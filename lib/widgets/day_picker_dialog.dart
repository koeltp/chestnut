import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 「每月几号」选择弹窗（信用卡出账日 / 还款日）
///
/// 1~31 的 7 列网格，点选后主题色圆点高亮，右下角取消。
/// 返回所选日（1~31）；取消 / 点外部关闭返回 null（不改当前值）。
Future<int?> showDayPickerDialog(
  BuildContext context, {
  int? initialDay,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _DayGridDialog(initialDay: initialDay),
  );
}

class _DayGridDialog extends StatefulWidget {
  const _DayGridDialog({this.initialDay});

  final int? initialDay;

  @override
  State<_DayGridDialog> createState() => _DayGridDialogState();
}

class _DayGridDialogState extends State<_DayGridDialog> {
  late int? _selected = widget.initialDay;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择日期',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
              children: [
                for (var day = 1; day <= 31; day++) _dayCell(day),
              ],
            ),
            // 底部右侧取消（点取消不改值）
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个日期格：选中态主题色圆底白字，未选中普通文字
  Widget _dayCell(int day) {
    final selected = _selected == day;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() => _selected = day);
        Navigator.pop(context, day);
      },
      child: Center(
        child: selected
            ? Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              )
            : Text(
                '$day',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
      ),
    );
  }
}
