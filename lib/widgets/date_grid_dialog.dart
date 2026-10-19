import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/app_date.dart';

/// 网格式日期段选择弹窗（居中 showDialog，点选即关闭返回）
///
/// 与滚轮日期选择弹窗（WheelDatePicker）配合：标题行点击某一段时弹出
/// 对应网格，选完回填滚轮。三种形态：
/// - 年份：[AppDate.minYear] ~ 当前年份，倒序 3 列网格（顶部是今年，往下滑到 1900）
/// - 月份：1~12 月，3 列网格，标题带当前年份主色强调
/// - 日期：日历式网格，周日起头一行七天，顶部星期表头（周日红色点缀），
///   月首前置留白，天数按 year/month 动态生成（自动覆盖平/闰年与大小月）
///
/// 视觉规范：宽 min(屏宽-2*pagePadding, 360)、大格大字（年/月格高 ~52、
/// 字号 16）、圆角 20、入场 fade+scale、选中态 120ms 过渡。
///
/// 点选即返回所选值；取消 / 点弹窗外部关闭返回 null（调用方不改当前值）。

/// 年份网格弹窗，返回所选年份（1900 ~ 今年）
Future<int?> showYearGridDialog(BuildContext context, {required int selected}) {
  return _showGridDialog<int>(
    context,
    _GridDialog(type: _GridType.year, selected: selected),
  );
}

/// 月份网格弹窗，返回所选月份（1~12）
Future<int?> showMonthGridDialog(BuildContext context, {required int selected}) {
  return _showGridDialog<int>(
    context,
    _GridDialog(type: _GridType.month, selected: selected, year: DateTime.now().year),
  );
}

/// 日期日历弹窗，返回所选日（1 ~ 当月天数，按 year/month 动态生成，
/// 自动覆盖平年/闰年 2 月与大小月）
Future<int?> showDayGridDialog(
  BuildContext context, {
  required int year,
  required int month,
  required int selected,
}) {
  return _showGridDialog<int>(
    context,
    _GridDialog(
      type: _GridType.day,
      selected: selected,
      year: year,
      month: month,
    ),
  );
}

/// 统一入场动画：fade + scale（0.92 → 1.0），比默认纯 fade 更有质感
///
/// showGeneralDialog 才支持 transitionBuilder（showDialog 没有），
/// 拦截层行为保持与 showDialog 默认一致（半透明黑、点外部可关）。
Future<T?> _showGridDialog<T>(BuildContext context, Widget child) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => child,
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

enum _GridType { year, month, day }

class _GridDialog extends StatefulWidget {
  const _GridDialog({
    required this.type,
    required this.selected,
    this.year = 0,
    this.month = 0,
  });

  final _GridType type;
  final int selected;

  /// 标题强调 / 日期网格的上下文年月（年份网格不需要）
  final int year;
  final int month;

  @override
  State<_GridDialog> createState() => _GridDialogState();
}

class _GridDialogState extends State<_GridDialog> {
  // ---------- 大气版视觉常量 ----------

  /// 弹窗圆角（与底部弹层 24 圆角呼应）
  static const double _radius = 20;

  /// 网格横/纵向间距
  static const double _colGap = 12;
  static const double _rowGap = 12;

  /// 年/月格宽高比（宽 360 时格高 ≈ 52）
  static const double _cellAspect = 1.9;

  /// 年份网格可见行数（6 行更大气，一屏 18 个年份）
  static const int _visibleRows = 6;

  /// 日历选中圆点直径（格宽 ≈ 42，留 2px 呼吸）
  static const double _dayCircle = 40;

  /// 弹窗最大内容宽度
  static const double _maxWidth = 360;

  /// 年份网格滚动定位（打开时滚到选中年所在行）
  ScrollController? _yearCtrl;

  @override
  void dispose() {
    _yearCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        child: SizedBox(
          // 大气版宽度：小屏留 pagePadding 边距，大屏封顶 360
          width: math.min(
            MediaQuery.sizeOf(context).width - 2 * AppDimens.pagePadding,
            _maxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title,
              const SizedBox(height: 14),
              switch (widget.type) {
                _GridType.year => _yearGrid(),
                _GridType.month => _monthGrid(),
                _GridType.day => _dayGrid(),
              },
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
      ),
    );
  }

  /// 标题：带年/月上下文主色强调（打开即知自己在哪一层）
  Widget get _title {
    const base = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );
    const accent = TextStyle(color: AppColors.primary);
    return switch (widget.type) {
      _GridType.year => const Text('选择年份', style: base),
      _GridType.month => Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(text: '${widget.year}', style: accent),
              const TextSpan(text: '年'),
            ],
          ),
        ),
      _GridType.day => Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(text: '${widget.year}', style: accent),
              const TextSpan(text: '年'),
              TextSpan(text: '${widget.month}', style: accent),
              const TextSpan(text: '月'),
            ],
          ),
        ),
    };
  }

  // ---------- 年份网格 ----------

  Widget _yearGrid() {
    final last = AppDate.maxYear;
    return LayoutBuilder(
      builder: (context, cons) {
        // 格高由弹窗宽度与宽高比推出，用于把选中年滚动到首屏
        final itemH = (cons.maxWidth - 2 * _colGap) / 3 / _cellAspect;
        _yearCtrl ??= ScrollController(
          initialScrollOffset:
              ((last - widget.selected) ~/ 3) * (itemH + _rowGap),
        );
        // 选中年距列表顶部过远时，首帧后把越界偏移收敛到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = _yearCtrl;
          if (c != null && c.hasClients) {
            final clamped = c.offset.clamp(0.0, c.position.maxScrollExtent);
            if (clamped != c.offset) c.jumpTo(clamped);
          }
        });
        return SizedBox(
          height: itemH * _visibleRows + _rowGap * (_visibleRows - 1),
          child: GridView.builder(
            controller: _yearCtrl,
            itemCount: last - AppDate.minYear + 1,
            // 必须显式清零内边距：GridView 默认会吃进 MediaQuery 的
            // 状态栏安全区，顶部凭空多出一行空白
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: _colGap,
              mainAxisSpacing: _rowGap,
              childAspectRatio: _cellAspect,
            ),
            itemBuilder: (context, i) {
              final y = last - i; // 倒序：顶部是今年，往下滑到 1900
              return _cell(
                '$y年',
                y == widget.selected,
                () => Navigator.pop(context, y),
              );
            },
          ),
        );
      },
    );
  }

  // ---------- 月份网格 ----------

  Widget _monthGrid() {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisSpacing: _colGap,
      mainAxisSpacing: _rowGap,
      childAspectRatio: _cellAspect,
      children: [
        for (var m = 1; m <= 12; m++)
          _cell(
            '$m月',
            m == widget.selected,
            () => Navigator.pop(context, m),
          ),
      ],
    );
  }

  // ---------- 日期日历网格 ----------

  Widget _dayGrid() {
    // 周日起头：Dart weekday 周一=1…周日=7，取模后周日=0（无前置空位）
    final firstWeekday = DateTime(widget.year, widget.month, 1).weekday % 7;
    final days = DateTime(widget.year, widget.month + 1, 0).day;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 星期表头（周日红色点缀，国内日历习惯）
        Row(
          children: [
            for (final w in ['日', '一', '二', '三', '四', '五', '六'])
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: w == '日'
                          ? AppColors.expense
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 宽屏（桌面端窗口）下日历可能超出弹窗高度：限高后内容超出时
        // 可滚动（shrinkWrap 在内容不足时仍按内容收缩）
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
            children: [
              // 月首前置留白（当月 1 号不对齐周首时）
              for (var i = 0; i < firstWeekday; i++) const SizedBox(),
              for (var d = 1; d <= days; d++)
                _cell(
                  '$d',
                  d == widget.selected,
                  () => Navigator.pop(context, d),
                  circle: true,
                  // 周日列（第 1 列）日期红色点缀
                  accent: (firstWeekday + d - 1) % 7 == 0,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 公共单元格 ----------

  /// 单个选择格：选中态主色底白字（日期为圆形，年/月为胶囊），
  /// 未选中普通文字（[accent] 时红色，用于周日列）。
  /// 选中态用 120ms AnimatedContainer 过渡，点选更顺滑。
  Widget _cell(
    String label,
    bool selected,
    VoidCallback onTap, {
    bool circle = false,
    bool accent = false,
  }) {
    final textStyle = TextStyle(
      fontSize: circle ? 15 : 16,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      color: selected
          ? Colors.white
          : (accent ? AppColors.expense : AppColors.textPrimary),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(circle ? _dayCircle / 2 : 999),
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: circle ? _dayCircle : double.infinity,
          height: circle ? _dayCircle : 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(999),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            style: textStyle,
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
