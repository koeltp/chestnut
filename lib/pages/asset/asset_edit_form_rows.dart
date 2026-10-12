import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/form_rows.dart';

/// 出账日/还款日行：点行弹「每月几号」选日，已选显示"每月 X 日"
/// 并带 × 可清除，未选显示占位；尾部图标同为 22×22 盒子，切换不跳位
class AssetDayRow extends StatelessWidget {
  const AssetDayRow({
    super.key,
    required this.label,
    required this.day,
    required this.onPick,
    required this.onClear,
  });

  final String label;

  /// 已选日期（1~31，null = 未填）
  final int? day;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return FormRow(
      label: label,
      onTap: onPick,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _dayText(day),
            style: TextStyle(
              fontSize: 15,
              color: day == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
          _dayTrailing(day, onClear),
        ],
      ),
    );
  }

  /// 显示文案：已选显示"每月 X 日"，未选显示占位
  String _dayText(int? day) =>
      day == null ? '选填，点此选择' : '每月 $day 日';

  /// 行尾图标：已选显示 ×（点清除），未选显示 >；
  /// 两者同为 22×22 盒子，切换时位置不跳
  Widget _dayTrailing(int? day, VoidCallback onClear) {
    if (day == null) {
      return const Icon(
        Icons.chevron_right,
        size: 22,
        color: AppColors.textSecondary,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClear,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: Icon(Icons.close, size: 22, color: AppColors.textSecondary),
      ),
    );
  }
}
