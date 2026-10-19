import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../models/enums.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_tree_selector.dart';
import '../add_bill/wheel_date_picker.dart';
import '../settings/tag_manage_page.dart';

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
/// 搜索框 → 账单日期快捷填充 → 起止日期 → 分类/标签二级弹层多选。
/// 快捷日期只是"替用户把起止日期填好"，不独立执行、不关闭面板，
/// 因此可与关键词/分类/标签自由组合。标签弹层内含"管理"入口，
/// 方便临时新建标签。
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

  /// 打开标签多选弹层：结构与分类弹层一致——
  /// 弹层内改动只写暂存集 [draft]，"确定"才回写面板；
  /// "取消"/下滑整体丢弃。弹层内"管理"可临时新建标签
  Future<void> _pickTags() async {
    // 复制一份暂存：选择器直接在该集合上增删，取消即丢弃
    final draft = Set<int>.from(_selectedTagIds);
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
          child: _TagMultiSelector(tags: _allTags, draft: draft),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _selectedTagIds
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
              const SizedBox(height: 20),
              _buildTagSection(),
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
            for (final p in pills) _GroupPill(data: p, onTap: _pickCategories),
            _buildAddPill('选择分类', _pickCategories),
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

  /// 标签区：已选标签实底胶囊（点胶囊同样进弹层编辑）
  /// + "选择标签"入口（空标签时也能进弹层用"管理"新建）
  Widget _buildTagSection() {
    final selectedTags = _allTags
        .where((t) => _selectedTagIds.contains(t.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('标签'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 标签无层级，一个标签一个实底胶囊（复用分类全选胶囊样式）
            for (final t in selectedTags)
              _GroupPill(
                data: (label: t.name, color: Color(t.color), full: true),
                onTap: _pickTags,
              ),
            _buildAddPill('选择标签', _pickTags),
          ],
        ),
      ],
    );
  }

  /// "选择分类/选择标签"入口胶囊（两处共用）
  Widget _buildAddPill(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 2),
            Text(
              label,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
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

/// 标签多选二级弹层（筛选面板专用，与分类弹层结构对齐）
///
/// 直接在外部传入的暂存集 [draft] 上增删——外层据此实现"取消即丢弃"；
/// "管理"进标签管理页，返回后刷新标签并清理已被删除的选中 id
class _TagMultiSelector extends StatefulWidget {
  const _TagMultiSelector({required this.tags, required this.draft});

  /// 打开时的全部标签（管理后在内部刷新）
  final List<Tag> tags;

  /// 暂存选中集（由外层持有引用）
  final Set<int> draft;

  @override
  State<_TagMultiSelector> createState() => _TagMultiSelectorState();
}

class _TagMultiSelectorState extends State<_TagMultiSelector> {
  late List<Tag> _tags = widget.tags;
  late final ValueNotifier<int> _count =
      ValueNotifier<int>(widget.draft.length);

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  /// 切换选中：直接改暂存集
  void _toggle(int id) {
    setState(() {
      if (widget.draft.contains(id)) {
        widget.draft.remove(id);
      } else {
        widget.draft.add(id);
      }
    });
    _count.value = widget.draft.length;
  }

  /// 进标签管理页：返回后刷新标签，清理已被删除的选中 id
  Future<void> _openManage() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const TagManagePage()),
    );
    if (!mounted) return;
    final tags = await context.read<TagRepository>().getTags();
    if (!mounted) return;
    setState(() {
      _tags = tags;
      widget.draft.removeWhere((id) => !tags.any((t) => t.id == id));
    });
    _count.value = widget.draft.length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 标题行：选择标签 ｜ 管理（临时新建）｜ 取消（丢弃暂存）
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              const Text(
                '选择标签',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _openManage,
                child: const Text('管理'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            // 强制全宽：Expanded 只撑高，水平方向 Column 给的是宽松约束，
            // 不收口会让滚动视口缩成内容宽并整体居中
            child: SizedBox(
              width: double.infinity,
              child: _tags.isNotEmpty
                  ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in _tags)
                        GestureDetector(
                          onTap: () => _toggle(t.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              // 未选白底彩框；选中实底白字
                              color: widget.draft.contains(t.id)
                                  ? Color(t.color)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusCard,
                              ),
                              border: Border.all(color: Color(t.color)),
                            ),
                            child: Text(
                              t.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: widget.draft.contains(t.id)
                                    ? Colors.white
                                    : Color(t.color),
                                fontWeight: widget.draft.contains(t.id)
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '暂无标签，点右上角"管理"创建',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
            ),
          ),
        ),
        // 底部确定：确认后外层把暂存回写到筛选面板
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
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
                valueListenable: _count,
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
    );
  }
}
