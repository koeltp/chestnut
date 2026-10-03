import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../theme/app_colors.dart';

/// 显示方式选择弹窗（钱迹式，首页顶部年月点击弹出）
///
/// 三种查看模式循环切换（点右上角"按月/按年/全部 >"）：
/// - 按月：年份滚轮 + 12 个月两列网格，点月份即选中该年月
/// - 按年：3 列年份网格，点年份即选中该年
/// - 全部：说明文字 + 确定按钮，首页加载所有数据
///
/// 视觉规范（对齐钱迹）：弹窗近乎全宽、标题行大字加粗、行距大、
/// 年列与月区之间细竖分割线。
class PeriodPickerDialog extends StatefulWidget {
  const PeriodPickerDialog({
    super.key,
    required this.initialMode,
    required this.initialMonth,
  });

  /// 打开时所处的查看模式
  final HomePeriod initialMode;

  /// 当前查看的月份（按月/按年模式的高亮与初始定位）
  final DateTime initialMonth;

  /// 弹出该弹窗的便捷方法，返回 `(模式, 基准月份)`；点遮罩关闭时为 null
  static Future<(HomePeriod, DateTime?)?> show(
    BuildContext context, {
    required HomePeriod initialMode,
    required DateTime initialMonth,
  }) {
    return showDialog<(HomePeriod, DateTime?)>(
      context: context,
      builder: (_) => PeriodPickerDialog(
        initialMode: initialMode,
        initialMonth: initialMonth,
      ),
    );
  }

  @override
  State<PeriodPickerDialog> createState() => _PeriodPickerDialogState();
}

class _PeriodPickerDialogState extends State<PeriodPickerDialog> {
  /// 年份可选范围：2012 ~ 当前年 +3（与钱迹一致）
  late final int _minYear = 2012;
  late final int _maxYear = DateTime.now().year + 3;

  /// 列表行高：大行距（钱迹式疏朗布局）
  static const double _rowExtent = 57;

  /// 分割线颜色
  static const Color _line = Color(0xFFEEEEEE);

  late HomePeriod _mode = widget.initialMode;

  /// 年份滚轮当前定位的年份（按月模式下滚动选择，点月份时生效）
  late int _year = widget.initialMonth.year;

  late final FixedExtentScrollController _yearController;

  @override
  void initState() {
    super.initState();
    _yearController = FixedExtentScrollController(
      initialItem: widget.initialMonth.year - _minYear,
    );
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  int get _yearCount => _maxYear - _minYear + 1;

  /// 关闭弹窗并回传选择结果
  void _finish(HomePeriod mode, DateTime? month) =>
      Navigator.pop<(HomePeriod, DateTime?)>(context, (mode, month));

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      // 近乎全宽（钱迹式），默认 Dialog 左右边距太大显得小气
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow(),
          Container(height: 0.5, color: _line),
          // "月份起始日"行仅按月模式显示（钱迹按年/全部模式无此行）
          if (_mode == HomePeriod.month) _startDayRow(),
          // 三种模式的选择主体
          ...switch (_mode) {
            HomePeriod.month => _buildMonthBody(),
            HomePeriod.year => [_buildYearBody()],
            HomePeriod.all => [_buildAllBody()],
          },
        ],
      ),
    );
  }

  /// 标题行："显示方式" ｜ 右侧模式切换入口（循环：月→年→全部）
  Widget _titleRow() {
    return InkWell(
      onTap: () => setState(() {
        _mode = switch (_mode) {
          HomePeriod.month => HomePeriod.year,
          HomePeriod.year => HomePeriod.all,
          HomePeriod.all => HomePeriod.month,
        };
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
        child: Row(
          children: [
            const Text(
              '显示方式',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              _mode.label,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// "月份起始日"行（钱迹支持自定义起始日，当前版本固定 01 仅展示）
  Widget _startDayRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
      child: Row(
        children: [
          const Text(
            '月份起始日',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          const Text(
            '01',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  // ---------- 按月模式（图1）：年份滚轮 + 月份两列网格 ----------

  List<Widget> _buildMonthBody() {
    return [
      SizedBox(
        height: _rowExtent * 7,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左：年份列表（近平面滚动 + 吸附回弹，选中年蓝色胶囊）
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: _yearController,
                itemExtent: _rowExtent,
                // 透视极小：视觉为普通列表滚动，无 3D 挤压感
                perspective: 0.0008,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) =>
                    setState(() => _year = _minYear + i),
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: _yearCount,
                  builder: (context, index) {
                    final y = _minYear + index;
                    final selected = y == _year;
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          '$y年',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: selected
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: selected
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // 年列与月区之间的细竖分割线（钱迹式）
            Container(width: 0.5, color: _line),
            // 右：12 个月两列网格（当前查看的月份蓝色高亮）
            Expanded(
              flex: 2,
              child: GridView.builder(
                padding: EdgeInsets.zero,
                itemCount: 12,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  // 行高与年份列表一致（大行距疏朗布局）
                  childAspectRatio: 2.1,
                ),
                itemBuilder: (context, i) {
                  final m = i + 1;
                  final selected =
                      _year == widget.initialMonth.year &&
                      m == widget.initialMonth.month;
                  return Center(
                    child: InkWell(
                      onTap: () =>
                          _finish(HomePeriod.month, DateTime(_year, m)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '$m月',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 17,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: selected
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // ---------- 按年模式（图2）：3 列年份网格 ----------

  Widget _buildYearBody() {
    // 大行距（64）× 6.5 行：底部露出半行，提示可滚动（与钱迹一致）
    const rowHeight = 64.0;
    return SizedBox(
      height: rowHeight * 6.5,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        itemCount: _yearCount,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          // 格高 = 行高 64（大行距疏朗布局，钱迹式）
          childAspectRatio: 104 / 64,
        ),
        itemBuilder: (context, i) {
          // 倒序展示（最新年份在前，与钱迹一致）
          final year = _maxYear - i;
          final selected = year == widget.initialMonth.year;
          return Center(
            child: InkWell(
              onTap: () => _finish(
                HomePeriod.year,
                DateTime(year, widget.initialMonth.month),
              ),
              borderRadius: BorderRadius.circular(26),
              child: Container(
                // 大号蓝色胶囊（选中年）
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Text(
                  '$year年',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- 全部模式（图3）：说明文字 + 确定 ----------

  Widget _buildAllBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Text(
            '在首页加载【当前账本】下所有时间范围内的数据',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: OutlinedButton(
            onPressed: () => _finish(HomePeriod.all, null),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _line, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              '确定',
              style: TextStyle(fontSize: 16, color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
