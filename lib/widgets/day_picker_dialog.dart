import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 「每月几号」选择弹窗（信用卡出账日 / 还款日）
///
/// 1~31 的 7 列网格，点选后主题色圆点高亮，右下角取消。
/// 返回所选日（1~31）；取消 / 点外部关闭返回 null（不改当前值）。
///
/// 视觉与日期网格弹窗（date_grid_dialog）统一：圆角 20、标题 20 加粗、
/// 大号圆点、入场 fade+scale。
Future<int?> showDayPickerDialog(
  BuildContext context, {
  int? initialDay,
}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _DayGridDialog(initialDay: initialDay),
    // 入场 fade + scale，与日期网格弹窗一致
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择日期',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
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

  /// 单个日期格：选中态主题色圆底白字，未选中普通文字（120ms 过渡）
  Widget _dayCell(int day) {
    final selected = _selected == day;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() => _selected = day);
        Navigator.pop(context, day);
      },
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
            child: Text('$day'),
          ),
        ),
      ),
    );
  }
}
