import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../models/enums.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_tree_selector.dart';
import '../add_bill/wheel_date_picker.dart';

/// 筛选面板应用回调：区间（起止均含当天）+ 关键词 + 标签 + 分类
typedef FilterApplyCallback =
    void Function(
      ({DateTime? start, DateTime? end}) range,
      String keyword,
      Set<int> tagIds,
      Set<int> categoryIds,
    );

/// 漏斗筛选面板（统计页）
///
/// 面板内一切条件只暂存，**必须点"搜索"才统一生效**：
/// 搜索框 → 账单日期快捷填充 → 起止日期 → 分类多选 → 标签多选。
/// 快捷日期只是"替用户把起止日期填好"，不独立执行、不关闭面板，
/// 因此可与关键词/分类/标签自由组合。
class StatsFilterSheet extends StatefulWidget {
  const StatsFilterSheet({
    super.key,
    required this.initialRange,
    required this.initialType,
    required this.initialKeyword,
    required this.initialTagIds,
    required this.initialCategoryIds,
    required this.onApply,
  });

  /// 已生效的日期区间（起止均含当天；null = 全部）
  final ({DateTime? start, DateTime? end})? initialRange;

  /// 当前收支类型（分类树据此加载）
  final BillType initialType;

  final String initialKeyword;
  final Set<int> initialTagIds;
  final Set<int> initialCategoryIds;

  final FilterApplyCallback onApply;

  @override
  State<StatsFilterSheet> createState() => _StatsFilterSheetState();
}

class _StatsFilterSheetState extends State<StatsFilterSheet> {
  DateTime? _start;
  DateTime? _end;

  /// 当前点亮的快捷项（手动改动起止后自动熄灭）
  String? _quick;

  late final _keywordCtrl = TextEditingController(text: widget.initialKeyword);

  late final Set<int> _selectedTagIds = Set<int>.from(widget.initialTagIds);
  late final Set<int> _selectedCategoryIds =
      Set<int>.from(widget.initialCategoryIds);

  List<Tag> _allTags = [];

  /// 当前收支类型下的分类树（供分类多选弹层与已选胶囊回显）
  List<Category> _typeCategories = [];

  @override
  void initState() {
    super.initState();
    final r = widget.initialRange;
    _start = r?.start;
    _end = r?.end;
    _quick = _matchQuick(_start, _end);
    _loadData();
  }

  /// 加载标签与当前类型分类树
  Future<void> _loadData() async {
    final tags = await context.read<TagRepository>().getTags();
    final cats = await _loadCategories();
    if (!mounted) return;
    setState(() {
      _allTags = tags;
      _typeCategories = cats;
    });
  }

  /// 取当前收支类型全部分类（分类树数据量极小，一次查询即可）
  Future<List<Category>> _loadCategories() {
    final db = context.read<AppDatabase>();
    return (db.select(db.categories)
          ..where((c) => c.type.equalsValue(widget.initialType))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  /// 某月最后一天
  static int _lastDayOfMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// 跨年快捷项文案（如"2025~2026"）
  String get _crossYearLabel {
    final y = DateTime.now().year;
    return '${y - 1}~$y';
  }

  /// 快捷项 → 预设区间（起止均含当天）
  ({DateTime? start, DateTime? end}) _quickRange(String label) {
    final now = DateTime.now();
    return switch (label) {
      '本月' => (
        start: DateTime(now.year, now.month, 1),
        end: DateTime(
          now.year,
          now.month,
          _lastDayOfMonth(now.year, now.month),
        ),
      ),
      '上月' => (
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(
          now.year,
          now.month - 1,
          _lastDayOfMonth(now.year, now.month - 1),
        ),
      ),
      '今年' => (
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year, 12, 31),
      ),
      '去年' => (
        start: DateTime(now.year - 1, 1, 1),
        end: DateTime(now.year - 1, 12, 31),
      ),
      _ => (
        // 跨年：去年 1/1 ~ 今天（保持"统计到今天含今天"语义）
        start: DateTime(now.year - 1, 1, 1),
        end: DateTime(now.year, now.month, now.day),
      ),
    };
  }

  /// 比较区间是否与某快捷预设一致（两端都按日期粒度）
  bool _rangeEquals(
    DateTime? s1,
    DateTime? e1,
    DateTime? s2,
    DateTime? e2,
  ) {
    bool same(DateTime? a, DateTime? b) {
      if (a == null && b == null) return true;
      if (a == null || b == null) return false;
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }
    return same(s1, s2) && same(e1, e2);
  }

  /// 找到与区间匹配的快捷项（全部 = 两端 null）
  String? _matchQuick(DateTime? start, DateTime? end) {
    if (start == null && end == null) return '全部';
    for (final label in ['本月', '上月', '今年', '去年', _crossYearLabel]) {
      final r = _quickRange(label);
      if (_rangeEquals(start, end, r.start, r.end)) return label;
    }
    return null;
  }

  /// 点快捷项：仅填充起止日期并点亮，面板保持打开
  void _fillQuick(String label) {
    setState(() {
      if (label == '全部') {
        _start = null;
        _end = null;
      } else {
        final r = _quickRange(label);
        _start = r.start;
        _end = r.end;
      }
      _quick = label;
    });
  }

  /// 手动选起止日期：仅更新暂存值，并熄灭快捷高亮（已非预设区间）
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
    if (result == null || !mounted) return;
    final picked = result.$1;
    setState(() {
      if (isStart) {
        _start = picked;
        // 开始晚于截止时清掉旧截止，避免倒挂区间
        if (_end != null && picked.isAfter(_end!)) _end = null;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = null;
      }
      _quick = _matchQuick(_start, _end);
    });
  }

  /// 打开分类树多选弹层：直接内嵌通用 [CategoryTreeSelector] 多选模式。
  ///
  /// 弹层内一切改动只写入本地暂存集合 [draft]，点"确定"才回写筛选
  /// 面板的已选集合；点"取消"或下滑关闭则整体丢弃
  Future<void> _pickCategories() async {
    // 复制一份暂存：选择器直接在该集合上增删，取消即丢弃、不污染面板
    final draft = Set<int>.from(_selectedCategoryIds);
    // 确定按钮上的数量随选择实时更新（选择器内部渲染由其自管 setState）
    final count = ValueNotifier<int>(draft.length);
    // 初始展开第一个"组内有选中"的一级；全无选中则不展开
    int? initialExpandedId;
    for (final root in _typeCategories.where((c) => c.parentId == null)) {
      final groupIds = [
        root.id,
        ..._typeCategories
            .where((c) => c.parentId == root.id)
            .map((c) => c.id),
      ];
      if (groupIds.any(draft.contains)) {
        initialExpandedId = root.id;
        break;
      }
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.75,
          child: Column(
            children: [
              // 标题行：选择分类 ｜ 取消（取消丢弃暂存）
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Text(
                      '选择分类',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CategoryTreeSelector(
                  mode: CategoryTreeMode.multi,
                  categories: _typeCategories,
                  selectedIds: draft,
                  initialExpandedId: initialExpandedId,
                  onMultiChanged: (ids) => count.value = ids.length,
                ),
              ),
              // 底部确定：确认后由外层把暂存回写到筛选面板状态
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(64, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: ValueListenableBuilder<int>(
                      valueListenable: count,
                      builder: (context, n, _) => Text(
                        n == 0 ? '确定' : '确定（$n）',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    count.dispose();
    if (confirmed == true && mounted) {
      setState(() => _selectedCategoryIds
        ..clear()
        ..addAll(draft));
    }
  }

  /// 点搜索：统一应用全部暂存条件并关闭面板（始终可点：
  /// 无条件 = 清除全部筛选回到全部账单）
  void _apply() {
    widget.onApply(
      (start: _start, end: _end),
      _keywordCtrl.text.trim(),
      Set<int>.from(_selectedTagIds),
      Set<int>.from(_selectedCategoryIds),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKeywordField(),
              const SizedBox(height: 20),
              _sectionTitle('账单日期'),
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
                    _QuickChip(
                      label: label,
                      selected: _quick == label,
                      onTap: () => _fillQuick(label),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildRangeRow(),
              const SizedBox(height: 20),
              _buildCategorySection(),
              if (_allTags.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionTitle('标签'),
                const SizedBox(height: 10),
                _buildTagWrap(),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(64, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    '搜索',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 分区标题
  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      );

  /// 关键词输入框
  Widget _buildKeywordField() {
    return TextField(
      controller: _keywordCtrl,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索备注、地点、分类',
        hintStyle:
            const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        prefixIcon: const Icon(
          Icons.search,
          size: 20,
          color: AppColors.textSecondary,
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
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
              onPressed: () => _keywordCtrl.clear(),
            );
          },
        ),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
        filled: true,
        fillColor: AppColors.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
      cursorColor: AppColors.primary,
    );
  }

  /// 起止日期行
  Widget _buildRangeRow() {
    return Row(
      children: [
        Expanded(
          child: _DateChip(
            text: _start == null
                ? '开始日期'
                : '${_start!.year}/${_start!.month}/${_start!.day}',
            selected: _start != null,
            onTap: () => _pickDate(isStart: true),
            onClear: () => setState(() {
              _start = null;
              _quick = _matchQuick(_start, _end);
            }),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('-', style: TextStyle(color: AppColors.textSecondary)),
        ),
        Expanded(
          child: _DateChip(
            text: _end == null
                ? '截止日期'
                : '${_end!.year}/${_end!.month}/${_end!.day}',
            selected: _end != null,
            onTap: () => _pickDate(isStart: false),
            onClear: () => setState(() {
              _end = null;
              _quick = _matchQuick(_start, _end);
            }),
          ),
        ),
      ],
    );
  }

  /// 分类区：已选按一级聚合回显——
  /// 整组全选 = 实底"交通"（不带数字）；部分选中 = 浅底"交通(3)"；
  /// 点胶囊重新进弹层编辑；点"选择分类"进入
  Widget _buildCategorySection() {
    final roots = _typeCategories.where((c) => c.parentId == null);
    final pills = [
      for (final root in roots) _groupPill(root),
    ].whereType<({String label, Color color, bool full})>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('分类'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in pills)
              _GroupPill(data: p, onTap: _pickCategories),
            _addCategoryPill(),
          ],
        ),
      ],
    );
  }

  /// 计算一级聚合回显数据；无选中返回 null
  ({String label, Color color, bool full})? _groupPill(Category root) {
    final subs = _typeCategories.where((c) => c.parentId == root.id);
    final ids = [root.id, for (final s in subs) s.id];
    final picked = ids.where(_selectedCategoryIds.contains).length;
    if (picked == 0) return null;
    final color = Color(root.colorValue);
    // 全选不带数字（标签最简洁）；部分选带选中条目数
    return (
      label: picked == ids.length ? root.name : '${root.name}($picked)',
      color: color,
      full: picked == ids.length,
    );
  }

  /// "选择分类"入口胶囊
  Widget _addCategoryPill() {
    return GestureDetector(
      onTap: _pickCategories,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: AppColors.textSecondary),
            SizedBox(width: 2),
            Text(
              '选择分类',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// 标签多选：未选白底彩框、选中实底白字（与标签选择弹层同款）
  Widget _buildTagWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _allTags)
          GestureDetector(
            onTap: () => setState(() => _selectedTagIds.contains(t.id)
                ? _selectedTagIds.remove(t.id)
                : _selectedTagIds.add(t.id)),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _selectedTagIds.contains(t.id)
                    ? Color(t.color)
                    : Colors.white,
                borderRadius:
                    BorderRadius.circular(AppDimens.radiusCard),
                border: Border.all(color: Color(t.color)),
              ),
              child: Text(
                t.name,
                style: TextStyle(
                  fontSize: 13,
                  color: _selectedTagIds.contains(t.id)
                      ? Colors.white
                      : Color(t.color),
                  fontWeight: _selectedTagIds.contains(t.id)
                      ? FontWeight.w500
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 快捷日期胶囊：选中浅蓝底蓝字，否则浅灰底
class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 起止日期胶囊：选中浅蓝底蓝字+尾部×，未选浅灰底
class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.text,
    required this.selected,
    required this.onTap,
    required this.onClear,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            // 文字区占满剩余宽居中；x 独立贴右缘（居中不再拖着 x 一起挪）
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            if (selected) ...[
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

/// 已选分类的聚合胶囊：全选=实底白字，部分选=浅底彩字；
/// 点击整体进分类弹层编辑
class _GroupPill extends StatelessWidget {
  const _GroupPill({required this.data, required this.onTap});

  final ({String label, Color color, bool full}) data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: data.full ? data.color : data.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
        child: Text(
          data.label,
          style: TextStyle(
            fontSize: 13,
            color: data.full ? Colors.white : data.color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
