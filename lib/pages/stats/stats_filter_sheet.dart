import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../theme/app_theme.dart';
import '../add_bill/wheel_date_picker.dart';

/// 漏斗筛选面板：快捷范围胶囊 + 自定义起止日期 + 关键词搜索
class StatsFilterSheet extends StatefulWidget {
  const StatsFilterSheet({
    super.key,
    required this.initialPeriod,
    required this.initialMonth,
    required this.initialCustom,
    required this.initialKeyword,
    required this.onApply,
  });

  final HomePeriod initialPeriod;
  final DateTime initialMonth;
  final ({DateTime? start, DateTime? end})? initialCustom;

  /// 已应用的关键词（回显到输入框）
  final String initialKeyword;
  final void Function(
    HomePeriod,
    DateTime,
    ({DateTime? start, DateTime? end})?,
    String keyword,
  )
  onApply;

  @override
  State<StatsFilterSheet> createState() => _StatsFilterSheetState();
}

class _StatsFilterSheetState extends State<StatsFilterSheet> {
  /// 当前点亮的快捷项（自定义模式时为 null）
  String? _quick;

  DateTime? _start;
  DateTime? _end;

  late final _keywordCtrl = TextEditingController(text: widget.initialKeyword);

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final custom = widget.initialCustom;
    if (custom == null) {
      _quick = switch (widget.initialPeriod) {
        HomePeriod.month =>
          _isSameMonth(widget.initialMonth, DateTime.now()) ? '本月' : null,
        HomePeriod.year =>
          _isSameYear(widget.initialMonth, DateTime.now()) ? '今年' : null,
        HomePeriod.all => '全部',
      };
    } else {
      _start = custom.start;
      _end = custom.end;
    }
  }

  static bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static bool _isSameYear(DateTime a, DateTime b) => a.year == b.year;

  /// 快捷项 → (范围模式, 基准月份)
  (HomePeriod, DateTime) _quickValue(String label) {
    final now = DateTime.now();
    return switch (label) {
      '本月' => (HomePeriod.month, DateTime(now.year, now.month)),
      '上月' => (HomePeriod.month, DateTime(now.year, now.month - 1)),
      '今年' => (HomePeriod.year, DateTime(now.year)),
      '去年' => (HomePeriod.year, DateTime(now.year - 1)),
      _ => (HomePeriod.all, DateTime(now.year)),
    };
  }

  /// 跨年快捷项文案（如"2025~2026"）：去年一整年 + 今年，随年份滚动
  String get _crossYearLabel {
    final y = DateTime.now().year;
    return '${y - 1}~$y';
  }

  /// 跨年项选中判断：当前自定义区间恰为"去年 1/1 ~ 今天（含）"。
  /// 截止端为排他口径，存储值为"明天 0 点"
  bool _isCrossYearActive() {
    final custom = widget.initialCustom;
    if (custom == null) return false;
    final now = DateTime.now();
    final s = custom.start;
    final e = custom.end;
    return s != null &&
        e != null &&
        s.year == now.year - 1 &&
        s.month == 1 &&
        s.day == 1 &&
        e == DateTime(now.year, now.month, now.day + 1);
  }

  /// 快捷项高亮判断：非自定义且模式/月份与当前匹配
  bool _isQuickActive(String label) {
    if (label == _crossYearLabel) return _isCrossYearActive();
    if (widget.initialCustom != null || _quick != label) return false;
    final (period, month) = _quickValue(label);
    final sameMonth = switch (label) {
      '本月' || '上月' => _isSameMonth(month, widget.initialMonth),
      '今年' || '去年' => _isSameYear(month, widget.initialMonth),
      _ => true,
    };
    return period == widget.initialPeriod && sameMonth;
  }

  /// 搜索按钮可点：选了日期或填了关键词；初始已带筛选时也允许——
  /// 面板全清空后点搜索 = 清除全部筛选
  bool get _canApply {
    if (_start != null || _end != null) return true;
    if (_keywordCtrl.text.trim().isNotEmpty) return true;
    return widget.initialCustom != null ||
        widget.initialKeyword.trim().isNotEmpty;
  }

  /// 面板当前关键词（快捷胶囊应用时一并带上，保持"整面板应用"语义）
  String get _keyword => _keywordCtrl.text.trim();

  /// 快捷胶囊：立即应用时间范围并关闭面板。
  /// 关键词一律清空（B 方案）——胶囊是"快速回到纯时间视角"：
  /// 不捎带搜索框里未应用的草稿，也顺带清掉已生效的关键词；
  /// 精细组合（关键词+日期）请用下方搜索区
  void _applyQuick(String label) {
    final now = DateTime.now();
    if (label == _crossYearLabel) {
      // 跨年统计走自定义区间：去年 1/1 ~ 今天（而非整年），范围模式不变。
      // 截止端为排他口径（<end），传"明天 0 点"才能把今天包含进来
      widget.onApply(widget.initialPeriod, widget.initialMonth, (
        start: DateTime(now.year - 1, 1, 1),
        end: DateTime(now.year, now.month, now.day + 1),
      ), '');
    } else {
      final (period, month) = _quickValue(label);
      widget.onApply(period, month, null, '');
    }
    Navigator.pop(context);
  }

  /// 自定义起止日期：选择后仅更新胶囊，点底部"确定"才应用。
  /// 支持只选一端（开放区间）；开始 > 截止时清掉旧的另一端，避免无效区间
  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final result = await showModalBottomSheet<(DateTime, int)>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusHeader),
        ),
      ),
      builder: (_) => WheelDatePicker(
        initial: isStart ? (_start ?? now) : (_end ?? now),
        initialMinute: 0,
        showTime: false,
      ),
    );
    if (result == null) return;
    // 异步等待后可能已离开页面
    if (!mounted) return;
    final picked = result.$1;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && picked.isAfter(_end!)) _end = null;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = null;
      }
    });
  }

  /// 搜索按钮：应用自定义区间与关键词（两端至少选了一个日期或有关键词），
  /// 关闭面板
  void _applyCustom() {
    if (!_canApply) return;
    widget.onApply(
      widget.initialPeriod,
      widget.initialMonth,
      _start == null && _end == null ? null : (start: _start, end: _end),
      _keyword,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        // 内容可滚动兜底：小屏 + 键盘全弹时可用空间不足也能滚动查看，永不溢出
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 快捷区在上：一键应用时间范围并关闭面板（关键词一并清空），
              // 精细组合（关键词+日期）走下方搜索区
              const Text(
                '账单日期',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final label in [
                    '本月',
                    '上月',
                    '今年',
                    '去年',
                    _crossYearLabel,
                    '全部',
                  ])
                    _chip(
                      label,
                      selected: _isQuickActive(label),
                      onTap: () => _applyQuick(label),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              // 搜索区在下：关键词 + 自定义起止组合，点"搜索"统一应用
              const Text(
                '搜索',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keywordCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索备注、地点、分类',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  // 有输入时显示清除按钮
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _keywordCtrl,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(
                          Icons.cancel,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () {
                          _keywordCtrl.clear();
                          setState(() {});
                        },
                      );
                    },
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                cursorColor: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _chip(
                      _start == null
                          ? '开始日期'
                          // 完整格式消歧：跨年筛选时只显示月/日无法区分年份
                          : '${_start!.year}/${_start!.month}/${_start!.day}',
                      selected: _start != null,
                      fullWidth: true,
                      onTap: () => _pickDate(isStart: true),
                      onClear: () => setState(() => _start = null),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '-',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: _chip(
                      _end == null
                          ? '截止日期'
                          : '${_end!.year}/${_end!.month}/${_end!.day}',
                      selected: _end != null,
                      fullWidth: true,
                      onTap: () => _pickDate(isStart: false),
                      onClear: () => setState(() => _end = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 搜索：选了日期或填了关键词才可点（见 _canApply）；
              // 支持只选开始或只选截止（开放区间）
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _canApply ? _applyCustom : null,
                  style: FilledButton.styleFrom(
                    // 定高容器内按钮文字垂直居中：去掉默认内边距与
                    // padded 触摸目标（隐形 48px 最小高），否则中文行高下必溢出
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(64, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.fill,
                    disabledForegroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    '搜索',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 胶囊选项：快捷项宽度自适应内容（图 1 样式），日期胶囊撑满整列；
  /// 浅灰底圆角，选中浅蓝底蓝字；[onClear] 非空且选中时尾部显示 ×
  Widget _chip(
    String label, {
    required bool selected,
    VoidCallback? onTap,
    bool fullWidth = false,
    VoidCallback? onClear,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            // 尾部×：点击只清本端（起止日期各自清除），命中最内层
            // GestureDetector，不会冒泡触发胶囊本身的 onTap
            if (onClear != null && selected) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.cancel,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
