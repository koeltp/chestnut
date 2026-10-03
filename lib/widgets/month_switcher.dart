import 'package:flutter/material.dart';

import '../utils/month_util.dart';

/// 月份切换器（首页 / 统计 / 预算页共用）
///
/// 左右箭头切换月份，中间显示"yyyy年M月"；点击文字可打开
/// 显示方式选择弹窗（首页专用，钱迹式）。
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
    this.foregroundColor = Colors.white,
    this.text,
    this.onTapText,
    this.showArrows = true,
    this.arrowStepMonths = 1,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  /// 文字与箭头颜色：深色头部上用白色，浅色页面上传深棕色
  final Color foregroundColor;

  /// 覆盖显示文本（按年/全部模式），null 时显示 yyyy年M月
  final String? text;

  /// 点击中间文字的回调（弹显示方式选择），null 时不可点
  final VoidCallback? onTapText;

  /// 是否显示左右切换箭头（"全部"模式无意义，可隐藏）
  final bool showArrows;

  /// 箭头每次跳动的月数（按年模式传 12，一次切一年）
  final int arrowStepMonths;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showArrows) _arrow(Icons.chevron_left, -1),
        // 中间文字可点击弹出显示方式选择（带下拉小箭头提示）
        InkWell(
          onTap: onTapText,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text ?? MonthUtil.displayName(month),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: foregroundColor,
                  ),
                ),
                if (onTapText != null) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.expand_more,
                    size: 16,
                    color: foregroundColor.withValues(alpha: 0.85),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showArrows) _arrow(Icons.chevron_right, 1),
      ],
    );
  }

  /// 月份箭头按钮（[offset] 为 -1 上一步 / 1 下一步，
  /// 步长由 [arrowStepMonths] 控制）
  Widget _arrow(IconData icon, int offset) {
    return InkWell(
      onTap: () => onChanged(
        DateTime(month.year, month.month + offset * arrowStepMonths),
      ),
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 22, color: foregroundColor),
      ),
    );
  }
}
