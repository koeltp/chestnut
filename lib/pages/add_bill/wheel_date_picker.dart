import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 滚轮式日期选择弹窗（钱迹式连续滚动）
///
/// 年/月/日三列都是**固定项数的循环滚轮，永不重建**。每一格显示的数字
/// 由"锚点日期 + 相对偏移"动态推算，因此日期可以在滚轮上连续跨越：
/// 9月30 的下一格显示 10月1（月列自动跳到 10月），1月1 的上一格显示
/// 上年 12月31。拖拽中只重绘文字，绝不重建滚轮、绝不打断手势。
///
/// 快捷行提供 今/昨/前 快捷键与时间入口（"时间 HH:mm"胶囊，点击弹
/// 时/分滚轮）。
///
/// 弹出方式：
/// ```dart
/// final (date, minute) = await showModalBottomSheet<(DateTime, int)>(
///   builder: (_) => WheelDatePicker(initial: 日期, initialMinute: 分钟数),
/// );
/// ```
///
/// [showTime] 传 false 时隐藏"时间 HH:mm"入口（纯日期选择场景，
/// 如分类统计漏斗的自定义起止日期），返回值的分钟数固定为 0。
class WheelDatePicker extends StatefulWidget {
  const WheelDatePicker({
    super.key,
    required this.initial,
    required this.initialMinute,
    this.showTime = true,
  });

  final DateTime initial;

  /// 初始时间，当日 0..1439 分钟
  final int initialMinute;

  /// 是否显示"时间 HH:mm"入口（默认显示；纯日期选择时传 false）
  final bool showTime;

  @override
  State<WheelDatePicker> createState() => _WheelDatePickerState();
}

class _WheelDatePickerState extends State<WheelDatePicker> {
  static const int _firstYear = 2010;
  static const int _yearCount = 2100 - 2010 + 1;
  static const int _monthCount = 12;
  // 日列固定 31 格：可见窗口内数字由锚点推算，跨月天然连续
  static const int _dayCount = 31;
  static const double _itemExtent = 44;
  static const double _pickerHeight = 132; // 3 行可见，中间为选中项

  late int _year = widget.initial.year;
  late int _month = widget.initial.month;
  late int _day = widget.initial.day;

  /// 账单时间（当日 0..1439 分钟），随日期弹窗一起确定返回
  late int _minute = widget.initialMinute;

  /// 各列最后回调的项号（0..count-1）。
  ///
  /// 同时充当 label 推算的锚点位置：该位置显示的数字就是当前
  /// _year/_month/_day，其余格按最短路径偏移推算。
  late int _realYear = _year - _firstYear;
  late int _realMonth = _month - 1;
  late int _realDay = _day - 1;

  late final _yearCtrl = FixedExtentScrollController(initialItem: _realYear);
  late final _monthCtrl = FixedExtentScrollController(initialItem: _realMonth);
  late final _dayCtrl = FixedExtentScrollController(initialItem: _realDay);

  /// 程序化滚动（jumpToItem）时屏蔽对应列回调并同步锚点，避免循环触发
  bool _syncing = false;

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  @override
  void dispose() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  /// 循环滚轮两格之间的最短路径差
  ///
  /// 回调项号跨界时会从 count-1 跳到 0（或反向），按 ±count 修正还原
  /// 真实移动格数。单次回调的移动格数远小于 count/2，判定安全。
  int _wrapDiff(int real, int anchor, int count) {
    var diff = real - anchor;
    if (diff > count / 2) diff -= count;
    if (diff < -count / 2) diff += count;
    return diff;
  }

  /// 程序化滚动并屏蔽联动，microtask 中恢复
  void _jump(FixedExtentScrollController controller, int item) {
    _syncing = true;
    controller.jumpToItem(item);
    scheduleMicrotask(() => _syncing = false);
  }

  // ---------- 三列回调：锚点推算日期，只重绘文字 ----------

  void _onYearChanged(int real) {
    if (_syncing) {
      _realYear = real;
      return;
    }
    final diff = _wrapDiff(real, _realYear, _yearCount);
    if (diff == 0) return;
    setState(() {
      _year += diff;
      _realYear = real;
    });
  }

  void _onMonthChanged(int real) {
    if (_syncing) {
      _realMonth = real;
      return;
    }
    final diff = _wrapDiff(real, _realMonth, _monthCount);
    if (diff == 0) return;
    setState(() {
      final d = DateTime(_year, _month + diff);
      _year = d.year;
      _month = d.month;
      _realMonth = real;
      // 切到小月时日号越界（如 1月31 → 2月）：收敛日号。
      // 日列位置不动，label 会按新锚点日期重算，无需 jump。
      if (_day > _daysInMonth) {
        _day = _daysInMonth;
      }
    });
  }

  void _onDayChanged(int real) {
    if (_syncing) {
      _realDay = real;
      return;
    }
    final diff = _wrapDiff(real, _realDay, _dayCount);
    if (diff == 0) return;
    setState(() {
      // DateTime 自然进位：9月31 → 10月1、1月0 → 上年 12月31
      final d = DateTime(_year, _month, _day + diff);
      _year = d.year;
      _month = d.month;
      _day = d.day;
      _realDay = real;
    });
    // 跨月/跨年由月列/年列的 label 按新锚点自动显示，无需 jump
  }

  // ---------- 三列 label：锚点 + 偏移动态推算 ----------

  List<Widget> _yearChildren() {
    return [
      for (var i = 0; i < _yearCount; i++)
        Center(
          key: i == _realYear ? const ValueKey('year_selected') : null,
          child: _label(
            '${_year + _wrapDiff(i, _realYear, _yearCount)}',
            i == _realYear,
          ),
        ),
    ];
  }

  List<Widget> _monthChildren() {
    return [
      for (var i = 0; i < _monthCount; i++)
        Center(
          key: i == _realMonth ? const ValueKey('month_selected') : null,
          child: _label(
            // DateTime 自动处理跨年（如 12月 + 1 → 次年 1月）
            '${DateTime(_year, _month + _wrapDiff(i, _realMonth, _monthCount)).month}月',
            i == _realMonth,
          ),
        ),
    ];
  }

  List<Widget> _dayChildren() {
    return [
      for (var i = 0; i < _dayCount; i++)
        Center(
          key: i == _realDay ? const ValueKey('day_selected') : null,
          child: _label(
            // DateTime 自动进退位：月末 +1 → 下月1、1号 -1 → 上月末
            '${DateTime(_year, _month, _day + _wrapDiff(i, _realDay, _dayCount)).day}',
            i == _realDay,
          ),
        ),
    ];
  }

  /// 今/昨/前快捷：状态整体跳到目标日期，三列位置按差值同步
  void _quick(int minusDays) {
    final old = DateTime(_year, _month, _day);
    final target = DateTime.now().subtract(Duration(days: minusDays));
    final yDiff = target.year - old.year;
    final mDiff = (target.year - old.year) * 12 + target.month - old.month;
    final dDiff = target.difference(old).inDays;
    setState(() {
      _year = target.year;
      _month = target.month;
      _day = target.day;
    });
    // 目标位置 = 当前锚点 + 差值（取模回到 0..count-1）
    _jump(_yearCtrl, (_realYear + yDiff) % _yearCount);
    _jump(_monthCtrl, (_realMonth + mDiff) % _monthCount);
    _jump(_dayCtrl, (_realDay + dDiff) % _dayCount);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapLg,
          AppDimens.pagePadding,
          AppDimens.gapMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 三列滚轮：年 / 月 / 日（可见 3 行，中间为选中项）
            SizedBox(
              height: _pickerHeight,
              child: Row(
                children: [
                  _wheelColumn(
                    key: const ValueKey('year_wheel'),
                    controller: _yearCtrl,
                    onChanged: _onYearChanged,
                    children: _yearChildren(),
                  ),
                  _wheelColumn(
                    key: const ValueKey('month_wheel'),
                    controller: _monthCtrl,
                    onChanged: _onMonthChanged,
                    children: _monthChildren(),
                  ),
                  _wheelColumn(
                    key: const ValueKey('day_wheel'),
                    controller: _dayCtrl,
                    onChanged: _onDayChanged,
                    children: _dayChildren(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.gapMd),
            // 快捷行：今 / 昨 / 前（选中当天时高亮）+ 时间入口（纯日期模式隐藏）
            Row(
              children: [
                _quickChip('今', 0),
                const SizedBox(width: 10),
                _quickChip('昨', 1),
                const SizedBox(width: 10),
                _quickChip('前', 2),
                const Spacer(),
                // 时间入口：点击弹出时/分滚轮
                if (widget.showTime)
                  InkWell(
                    key: const ValueKey('time_chip'),
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.fill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '时间 ${_pad2(_minute ~/ 60)}:${_pad2(_minute % 60)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.gapSm),
            // 取消 / 确定（右对齐）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    (DateTime(_year, _month, _day), _minute),
                  ),
                  child: const Text(
                    '确定',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 弹出 Material 钟面时间选择器，确定后更新时间
  ///
  /// 定制：去掉顶部"选择时间"标题（helpText 置空）、时:分数字不带背景色。
  Future<void> _pickTime() async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (context) => Theme(
        // 钟面主色跟随应用主题色
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                onPrimary: Colors.white,
              ),
          timePickerTheme: const TimePickerThemeData(
            backgroundColor: Colors.white,
            // 选中段数字不加背景色，文字层次沿用默认（未选蓝灰 / 选中黑）
            hourMinuteColor: Colors.transparent,
            // 选中框只显示下边框（默认 M3 是四边圆角框）：小时/分钟共用
            // 该 shape，选中者显示蓝下划线，未选中无框
            hourMinuteShape: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        child: TimePickerDialog(
          initialTime: TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60),
          helpText: '',
          // "小时/分钟"标签在数字下方左对齐、与居中的数字错位（内置布局
          // 不可配置）；置空隐藏，与 Google 自家 M3 时钟一致——表盘选中
          // 态已表达时/分语义，无需文字标签
          hourLabelText: '',
          minuteLabelText: '',
        ),
      ),
    );
    if (picked != null) {
      setState(() => _minute = picked.hour * 60 + picked.minute);
    }
  }

  String _pad2(int v) => v.toString().padLeft(2, '0');

  /// 选中项深色加粗、相邻项淡蓝，形成层次感
  Widget _label(String text, bool selected) {
    return Text(
      text,
      style: selected
          ? const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            )
          : TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: AppColors.primary.withValues(alpha: 0.4),
            ),
    );
  }

  /// 鼠标滚轮每次只滚一格
  ///
  /// SDK 对滚轮事件的默认处理是把 scrollDelta 直接加到滚动位置，
  /// Windows 一格滚轮 ≈ 120px ≈ 2.7 个 item，会一次跳过 2~3 格
  /// （表现为"9月30 被跳过直接到 29"）。利用 resolver「最深命中者
  /// 先注册、赢者通吃」的规则，把每个 item 用 Listener 包住抢注
  /// 滚轮事件，改为按选中项 ±1 格精确滚动。
  void _registerWheel(PointerSignalEvent event, FixedExtentScrollController controller) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      if (e is! PointerScrollEvent) return;
      // 滚轮向下（dy>0）= 前进一格，与常规列表直觉一致
      final forward = e.scrollDelta.dy > 0;
      final current = (controller.position.pixels / _itemExtent).round();
      controller.animateToItem(
        current + (forward ? 1 : -1),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 单列滚轮：可见 3 行，选中行上下带横线
  ///
  /// 必须用 ListWheelScrollView + Looping delegate 才是真正的循环滚轮
  /// （CupertinoPicker 不支持循环，到底就停）。
  Widget _wheelColumn({
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
    required List<Widget> children,
    Key? key,
  }) {
    final picker = ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.5,
      childDelegate: ListWheelChildLoopingListDelegate(
        // 每个 item 包 Listener 抢注滚轮事件（见 _registerWheel）
        children: [
          for (final child in children)
            Listener(
              onPointerSignal: (e) => _registerWheel(e, controller),
              child: child,
            ),
        ],
      ),
      onSelectedItemChanged: onChanged,
    );
    return Expanded(
      key: key,
      child: Stack(
        children: [
          picker,
          // 选中行上下横线
          Positioned(
            top: _pickerHeight / 2 - _itemExtent / 2,
            left: 0,
            right: 0,
            child: Container(height: 1, color: AppColors.divider),
          ),
          Positioned(
            bottom: _pickerHeight / 2 - _itemExtent / 2,
            left: 0,
            right: 0,
            child: Container(height: 1, color: AppColors.divider),
          ),
        ],
      ),
    );
  }

  /// 快捷日期圆钮：选中对应日期时主色实底白字，否则白底描边
  Widget _quickChip(String label, int minusDays) {
    final d = DateTime.now().subtract(Duration(days: minusDays));
    final active = _year == d.year && _month == d.month && _day == d.day;
    return InkWell(
      onTap: () => _quick(minusDays),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 40,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

