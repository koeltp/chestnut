import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../providers/bill_provider.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_label_util.dart';
import '../../utils/money_util.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/bill_detail_sheet.dart';
import '../../widgets/bill_list_item.dart';
import '../../widgets/category_avatar.dart';
import '../../widgets/pie_chart_card.dart';
import '../../widgets/section_card.dart';
import '../add_bill/wheel_date_picker.dart';
import '../home/period_picker_dialog.dart';

/// 统计页（Tab 页 + 分类管理页独立 push 共用）：两态视图合一
///
/// - 全部视图（无分类）：收支类型分段器 + 汇总卡 + 柱状图 +
///   分类占比环形图 + 分类排行 + 账单明细
/// - 分类视图（有分类）：单分类汇总卡 + 柱状图 +
///   子分类构成环形图（仅一级分类）+ 账单明细
///
/// 钻取闭环：全部视图点排行项/环图扇区 → 同页切到分类视图，
/// 顶栏返回按钮逐级退回；分类管理页带初始分类进入时栈底即该分类。
/// 时间范围：顶栏副标题弹窗（按月/按年/全部）+ 漏斗面板（快捷范围、
/// 自定义起止日期与关键词搜索），与首页口径一致。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.initialCategory});

  /// 非空时直接进入该分类视图（分类管理页"查看统计数据"入口）
  final Category? initialCategory;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  /// 视图栈：null = 全部视图，非 null = 分类视图；栈底为入口视图，
  /// 顶栏返回逐级弹栈，栈底时交给系统默认返回（退出页面）
  late final List<Category?> _stack = [widget.initialCategory];

  Category? get _category => _stack.last;
  bool get _isAllView => _category == null;

  /// 查看范围（按月/按年/全部），与首页口径一致
  HomePeriod _period = HomePeriod.month;
  DateTime _month = DateTime.now();

  /// 自定义起止日期（开始含当天、截止排他），两端可只选其一（开放端
  /// 不限制）；非空时优先于 [_period] 生效
  ({DateTime? start, DateTime? end})? _custom;

  /// 是否处于自定义日期区间模式
  bool get _isCustom => _custom != null;

  /// 已应用的搜索关键词（空 = 未筛选）：漏斗面板输入并确定后生效，
  /// 过滤备注/定位完整信息/分类名
  String _keyword = '';

  /// 全部视图的收支类型（分类视图由分类自身类型决定）
  BillType _type = BillType.expense;

  /// 分类视图标题的父分类名（二级分类标题需要"一级名-二级名"）
  String? _parentName;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial != null) _loadParentName(initial);
  }

  /// 取父分类名：一次性查询即可（分类层级极少变动）
  Future<void> _loadParentName(Category category) async {
    final pid = category.parentId;
    if (pid == null) return;
    final map = await context
        .read<CategoryProvider>()
        .categoriesMapStream()
        .first;
    if (!mounted) return;
    setState(() => _parentName = map[pid]?.name);
  }

  /// 钻取到分类视图（点排行项/环图扇区）：压栈而非换页，
  /// 当前时间范围与关键词筛选保持不变
  void _drillTo(Category category) {
    if (_category?.id == category.id) return;
    setState(() {
      _stack.add(category);
      _parentName = null;
    });
    _loadParentName(category);
  }

  /// 顶栏返回：逐级退回上一视图；栈底时 leading 为 null，
  /// 由系统默认返回（Tab 页无按钮 / push 页退出）
  void _popView() {
    if (_stack.length <= 1) return;
    setState(() {
      _stack.removeLast();
      _parentName = null;
    });
    final cur = _category;
    if (cur != null) _loadParentName(cur);
  }

  /// 标题：全部视图 = "统计"；分类 = "分类统计-一级名-二级名"
  String get _title {
    final c = _category;
    if (c == null) return '统计';
    final parent = _parentName;
    return '分类统计-${parent == null ? c.name : '$parent-${c.name}'}';
  }

  /// 顶栏副标题：当前查看范围（自定义时显示起止日期，跨年显示"某年-某年"）
  String get _subtitle {
    final custom = _custom;
    if (custom != null) {
      final s = custom.start;
      final e = custom.end;
      // 两端齐全：跨年显示年份区间，月/日无意义；同年内显示月/日
      if (s != null && e != null) {
        if (s.year != e.year) return '${s.year}年-${e.year}年';
        return '${s.month}/${s.day} - ${e.month}/${e.day}';
      }
      // 只选一端：开放区间（另一端不限制）
      if (s != null) return '${s.year}/${s.month}/${s.day} 起';
      return '至 ${e!.year}/${e.month}/${e.day}';
    }
    return switch (_period) {
      HomePeriod.month => '${_month.year}年${_month.month}月',
      HomePeriod.year => '${_month.year}年',
      HomePeriod.all => '全部',
    };
  }

  /// 当前范围的 [start, end) 区间。
  /// 口径：开始日**含当天**，截止日**不含当天**（截止 2025/10/1 = 查
  /// <2025/10/1 的所有数据）；全部模式与开放端为 null（不限制）
  (DateTime?, DateTime?) get _range {
    final custom = _custom;
    if (custom != null) {
      final s = custom.start;
      final e = custom.end;
      return (
        s == null ? null : DateTime(s.year, s.month, s.day),
        e == null ? null : DateTime(e.year, e.month, e.day),
      );
    }
    return switch (_period) {
      HomePeriod.month => (
        DateTime(_month.year, _month.month),
        DateTime(_month.year, _month.month + 1),
      ),
      HomePeriod.year => (DateTime(_month.year), DateTime(_month.year + 1)),
      HomePeriod.all => (null, null),
    };
  }

  /// 【临时诊断】当前筛选状态的简短描述（随诊断文案一起删除）
  String get _diagState {
    final c = _custom;
    if (c != null) {
      String side(DateTime? d) =>
          d == null ? '不限' : '${d.year}/${d.month}/${d.day}';
      return '自定义${side(c.start)}~${side(c.end)}';
    }
    return '${_period.name} ${_month.year}/${_month.month}';
  }

  /// 顶栏副标题点击：弹出范围选择（与首页同款弹窗）；自定义区间失效
  Future<void> _pickPeriod() async {
    final result = await PeriodPickerDialog.show(
      context,
      initialMode: _period,
      initialMonth: _month,
    );
    if (result == null || !mounted) return;
    setState(() {
      _period = result.$1;
      _month = result.$2 ?? _month;
      _custom = null;
    });
  }

  /// 漏斗面板应用回调（时间范围 + 关键词一并应用）
  void _applyFilter(
    HomePeriod period,
    DateTime month,
    ({DateTime? start, DateTime? end})? custom,
    String keyword,
  ) {
    setState(() {
      _period = period;
      _month = month;
      _custom = custom;
      _keyword = keyword;
    });
  }

  /// 右上角漏斗：快捷范围 + 自定义起止日期 + 关键词搜索
  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      // 键盘弹起时面板可用高度会被压到半屏以下，必须解除
      // 默认 9/16 屏限制，否则内容(约 380dp)装不下、底部确定按钮溢出
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _FilterSheet(
        initialPeriod: _period,
        initialMonth: _month,
        initialCustom: _custom,
        initialKeyword: _keyword,
        onApply: _applyFilter,
      ),
    );
  }

  /// 长按删除账单（与首页一致的二次确认）
  Future<void> _confirmDelete(Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账单'),
        content: const Text('确定删除这条账单吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<BillProvider>().deleteBill(bill.id);
    }
  }

  /// 年月横滑条数据：从当前年铺到 1970 年（年、月交替）。
  /// 当前年只铺到当前月（未来月份无意义），历史年份 12 个月全铺。
  List<(int, int?)> get _stripItems {
    final now = DateTime.now();
    final items = <(int, int?)>[];
    for (var y = now.year; y >= 1970; y--) {
      items.add((y, null));
      final lastMonth = y == now.year ? now.month : 12;
      for (var m = lastMonth; m >= 1; m--) {
        items.add((y, m));
      }
    }
    return items;
  }

  /// 横滑条点击：点年份统计整年、点月份统计单月；自定义区间失效
  void _onStripTap(int year, int? month) {
    setState(() {
      _custom = null;
      if (month == null) {
        _period = HomePeriod.year;
        _month = DateTime(year);
      } else {
        _period = HomePeriod.month;
        _month = DateTime(year, month);
      }
    });
  }

  /// 当前视图的账单流：分类视图为该分类（含子分类）流；
  /// 全部视图为对应范围的全量流。UI 在 build 中取流，
  /// 范围/月份/视图切换时 StreamBuilder 重新订阅新流
  Stream<List<Bill>> _billsStream(BillProvider provider) {
    final c = _category;
    if (c != null) return provider.categoryBillsStream(c.id);
    return provider.billsInRangeStream(_period, _month);
  }

  /// 关键词过滤：定位完整信息/备注/分类名任一包含（英文统一转小写
  /// 比较，中文不受影响）
  List<Bill> _applyKeyword(List<Bill> bills, Map<int, Category> categories) {
    final kw = _keyword.trim().toLowerCase();
    if (kw.isEmpty) return bills;
    return bills.where((b) {
      return (b.locationFull ?? '').toLowerCase().contains(kw) ||
          (b.note ?? '').toLowerCase().contains(kw) ||
          (categories[b.categoryId]?.name ?? '').toLowerCase().contains(kw);
    }).toList();
  }

  /// 按分类聚合（全部视图环图/排行共用）：金额降序；
  /// 分类已删除的账单归为"未知分类"（category 为 null，不可钻取）
  List<({Category? category, String name, int cents})> _aggregateByCategory(
    List<Bill> bills,
    Map<int, Category> categories,
  ) {
    final sums = <int, int>{};
    for (final b in bills) {
      sums[b.categoryId] = (sums[b.categoryId] ?? 0) + b.amountCents;
    }
    final entries = [
      for (final e in sums.entries)
        (
          category: categories[e.key],
          name: categories[e.key]?.name ?? '未知分类',
          cents: e.value,
        ),
    ]..sort((a, b) => b.cents.compareTo(a.cents));
    return entries;
  }

  /// 子分类构成数据（分类视图仅一级分类）：按子分类聚合；
  /// 直接挂一级或分类已不存在的账单归并为"未细分"（不可钻取）
  List<({Category? category, String name, int cents})> _pieEntries(
    List<Bill> bills,
    Map<int, Category> categories,
    Category parent,
  ) {
    final subSums = <int, int>{};
    var direct = 0;
    for (final b in bills) {
      final c = categories[b.categoryId];
      if (c != null && c.parentId == parent.id) {
        subSums[b.categoryId] = (subSums[b.categoryId] ?? 0) + b.amountCents;
      } else {
        direct += b.amountCents;
      }
    }
    final entries = [
      for (final e in subSums.entries)
        (
          category: categories[e.key],
          name: categories[e.key]?.name ?? '未知分类',
          cents: e.value,
        ),
    ];
    if (direct > 0) entries.add((category: null, name: '未细分', cents: direct));
    entries.sort((a, b) => b.cents.compareTo(a.cents));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<BillProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        // 栈底不显示返回：Tab 页无按钮；push 进入时由系统默认返回箭头兜底
        leading: _stack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _popView,
              )
            : null,
        title: InkWell(
          onTap: _pickPeriod,
          child: Column(
            children: [
              Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                _subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // 漏斗：自定义区间或关键词生效时主色高亮提示
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined, size: 22),
            color: (_isCustom || _keyword.isNotEmpty)
                ? AppColors.primary
                : AppColors.textPrimary,
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: StreamBuilder<Map<int, Category>>(
        stream: context.read<CategoryProvider>().categoriesMapStream(),
        builder: (context, catSnapshot) {
          final categories = catSnapshot.data ?? const <int, Category>{};
          return StreamBuilder<List<Bill>>(
            stream: _billsStream(provider),
            builder: (context, snapshot) {
              // 换流空窗（筛选变化重订阅 drift 流）显示加载态，
              // 而不是当空列表顶"暂无账单"空态，避免闪现误导
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return _buildBody(snapshot.data!, categories);
            },
          );
        },
      ),
    );
  }

  /// 页面主体：pinned 头部（类型分段器 + 年月条）+ 汇总/图表/明细
  Widget _buildBody(List<Bill> bills, Map<int, Category> categories) {
    // 范围过滤（数据层为全量流，内存过滤足够）
    final (start, end) = _range;
    var filtered = bills.where((b) {
      if (start != null && b.date.isBefore(start)) return false;
      if (end != null && !b.date.isBefore(end)) return false;
      return true;
    }).toList();
    filtered = _applyKeyword(filtered, categories);

    final c = _category;
    // 分段器是整页开关：全部视图下汇总/图表/明细都只展示当前收支
    // 类型的数据；分类视图 typeBills 即 filtered（单分类类型固定）
    final typeBills = _isAllView
        ? filtered.where((b) => b.type == _type).toList()
        : filtered;
    final isExpense = _isAllView
        ? _type == BillType.expense
        : c!.type == BillType.expense;
    final amountColor = isExpense ? AppColors.expense : AppColors.income;

    // 汇总：总额/笔数/平均每笔/平均每月（平均每月按有账单的月份数均摊）
    final total = typeBills.fold<int>(0, (s, b) => s + b.amountCents);
    final count = typeBills.length;
    final avgPerBill = count == 0 ? 0 : total ~/ count;
    final months = typeBills
        .map((b) => '${b.date.year}-${b.date.month}')
        .toSet()
        .length;
    final avgPerMonth = months == 0 ? 0 : total ~/ months;

    // 分类占比环形图 + 排行（全部视图共用一份数据）
    final catEntries = _isAllView
        ? _aggregateByCategory(typeBills, categories)
        : const <({Category? category, String name, int cents})>[];
    // 子分类构成环形图（分类视图仅一级分类）
    final pieEntries = (c != null && c.parentId == null)
        ? _pieEntries(filtered, categories, c)
        : const <({Category? category, String name, int cents})>[];

    // 按日分组（数据已按日期倒序），与首页明细同粒度
    final dayKeys = <String>[];
    final dayMap = <String, List<Bill>>{};
    for (final bill in typeBills) {
      final key = '${bill.date.year}-${bill.date.month}-${bill.date.day}';
      if (!dayMap.containsKey(key)) {
        dayMap[key] = [];
        dayKeys.add(key);
      }
      dayMap[key]!.add(bill);
    }
    // 年份按需显示：数据横跨多个年份时分组头带年份消歧
    final crossYear = typeBills.map((b) => b.date.year).toSet().length > 1;
    final emptyText = _keyword.trim().isEmpty ? '该范围内暂无账单' : '未找到匹配账单';

    return CustomScrollView(
      slivers: [
        // 固定头部：全部视图多一行收支类型分段器，滚动时整体钉在顶部
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(
            height:
                _HeaderDelegate.stripHeight +
                (_isAllView ? _HeaderDelegate.segHeight : 0),
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  if (_isAllView)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.pagePadding,
                        vertical: 6,
                      ),
                      child: Center(
                        child: AppSegmented<BillType>(
                          options: [
                            for (final t in BillType.values) (t, t.label),
                          ],
                          colors: const [AppColors.expense, AppColors.income],
                          selected: _type,
                          onChanged: (t) => setState(() => _type = t),
                        ),
                      ),
                    ),
                  _PeriodStrip(
                    items: _stripItems,
                    period: _period,
                    month: _month,
                    isCustom: _isCustom,
                    onTap: _onStripTap,
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _SummaryCard(
            isExpense: isExpense,
            amountColor: amountColor,
            totalCents: total,
            count: count,
            avgPerBillCents: avgPerBill,
            avgPerMonthCents: avgPerMonth,
          ),
        ),
        // 柱状图：年范围 12 月柱（带金额标注），月范围当月每日柱
        if (!_isCustom && _period != HomePeriod.all)
          SliverToBoxAdapter(
            child: _RangeBarChart(
              period: _period,
              anchor: _month,
              bills: typeBills,
              color: amountColor,
            ),
          ),
        // 分类占比环形图（全部视图）：点扇区钻取到对应分类
        if (_isAllView)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pagePadding,
                AppDimens.gapSm,
                AppDimens.pagePadding,
                0,
              ),
              child: PieChartCard(
                title: '${_type.label}分类占比',
                items: [for (final e in catEntries) (e.name, e.cents)],
                centerLabel: '${_type.label}合计',
                centerValue: MoneyUtil.centsToYuanGroupedTrimmed(total),
                centerValueColor: amountColor,
                emptyText: emptyText,
                onSliceTap: (i) {
                  final target = catEntries[i].category;
                  if (target != null) _drillTo(target);
                },
              ),
            ),
          ),
        // 分类排行（全部视图）：点条目钻取到对应分类
        if (_isAllView)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pagePadding,
                AppDimens.gapSm,
                AppDimens.pagePadding,
                0,
              ),
              child: _RankingCard(
                entries: catEntries,
                total: total,
                onTap: _drillTo,
              ),
            ),
          ),
        // 子分类构成环形图（分类视图仅一级分类）：点扇区钻取到子分类
        if (c != null && c.parentId == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pagePadding,
                AppDimens.gapSm,
                AppDimens.pagePadding,
                0,
              ),
              child: PieChartCard(
                title: '子分类构成',
                items: [for (final e in pieEntries) (e.name, e.cents)],
                centerLabel: '合计',
                centerValue: MoneyUtil.centsToYuanGroupedTrimmed(total),
                centerValueColor: amountColor,
                emptyText: emptyText,
                onSliceTap: (i) {
                  final target = pieEntries[i].category;
                  if (target != null) _drillTo(target);
                },
              ),
            ),
          ),
        if (typeBills.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    emptyText,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  // 【临时诊断】排查"首次自定义搜索无数据"：区分流为空
                  // 还是过滤滤光，定位后删除本段
                  const SizedBox(height: 8),
                  Text(
                    '[诊断]流${bills.length}条 筛后${filtered.length}条 '
                    '$_diagState',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSm,
              AppDimens.pagePadding,
              24,
            ),
            sliver: SliverList.builder(
              itemCount: dayKeys.length,
              itemBuilder: (context, index) {
                final dayBills = dayMap[dayKeys[index]]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.gapSection),
                  child: _DayCard(
                    date: dayBills.first.date,
                    bills: dayBills,
                    categories: categories,
                    onDelete: _confirmDelete,
                    onCategoryTap: _drillTo,
                    showYear: crossYear,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 固定头部代理：滚动时类型分段器与年月条整体钉在页面顶部
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  /// 年月条行（含底部 5px 渐变立体条）
  static const double stripHeight = 51;

  /// 收支类型分段器行（分段器高约 39，中文行高略大，留余量取 52）
  static const double segHeight = 52;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(_HeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
}

/// 标题行下的年月胶囊条（固定在页面顶部，记一笔式底部立体效果）：
/// 点年份统计整年、点月份统计单月，向右滑动可一直回溯到 1970 年 1 月；
/// 范围由漏斗等外部改变时自动滚动到选中项
class _PeriodStrip extends StatefulWidget {
  const _PeriodStrip({
    required this.items,
    required this.period,
    required this.month,
    required this.isCustom,
    required this.onTap,
  });

  final List<(int, int?)> items;
  final HomePeriod period;
  final DateTime month;
  final bool isCustom;
  final void Function(int year, int? month) onTap;

  @override
  State<_PeriodStrip> createState() => _PeriodStripState();
}

class _PeriodStripState extends State<_PeriodStrip> {
  final _controller = ScrollController();

  /// 条目定宽（保证自动定位的 offset 计算精确）
  static const double _yearWidth = 84;
  static const double _monthWidth = 64;
  static const double _gap = 10;

  /// 当前选中条目索引（自定义区间无选中）
  int get _selectedIndex {
    if (widget.isCustom) return -1;
    for (var i = 0; i < widget.items.length; i++) {
      final (y, m) = widget.items[i];
      if (m == null) {
        if (widget.period == HomePeriod.year && widget.month.year == y) {
          return i;
        }
      } else {
        if (widget.period == HomePeriod.month &&
            widget.month.year == y &&
            widget.month.month == m) {
          return i;
        }
      }
    }
    return -1;
  }

  /// 选中项的横向偏移（条目定宽，直接累加）
  double _offsetOf(int index) {
    var off = AppDimens.pagePadding;
    for (var i = 0; i < index; i++) {
      off += (widget.items[i].$2 == null ? _yearWidth : _monthWidth) + _gap;
    }
    return off;
  }

  void _scrollToSelected() {
    final idx = _selectedIndex;
    if (idx < 0 || !_controller.hasClients) return;
    final target = (_offsetOf(idx) - 60).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(_PeriodStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period ||
        oldWidget.month != widget.month ||
        oldWidget.isCustom != widget.isCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 46,
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final (year, m) = widget.items[index];
                final selected = index == _selectedIndex;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: _gap),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () => widget.onTap(year, m),
                      child: Container(
                        width: m == null ? _yearWidth : _monthWidth,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          // 选中态：饱满浅蓝胶囊 + 蓝字（钱迹式）
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          m == null ? '$year年' : '$m月',
                          style: TextStyle(
                            fontSize: 14,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 底部向下渐隐的立体条（记一笔顶栏同款，滚动时内容从下方穿过）
          Container(
            height: 5,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x1A000000), Colors.transparent],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 汇总卡：总额、笔数、平均每笔、平均每月（2×2 网格，钱迹式）
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.isExpense,
    required this.amountColor,
    required this.totalCents,
    required this.count,
    required this.avgPerBillCents,
    required this.avgPerMonthCents,
  });

  final bool isExpense;
  final Color amountColor;
  final int totalCents;
  final int count;
  final int avgPerBillCents;
  final int avgPerMonthCents;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        AppDimens.gapSm,
        AppDimens.pagePadding,
        0,
      ),
      child: SectionCard(
        child: Column(
          children: [
            Row(
              children: [
                cell(
                  isExpense ? '总支出' : '总收入',
                  MoneyUtil.centsToYuanGroupedTrimmed(totalCents),
                  color: amountColor,
                ),
                cell('总笔数', '$count'),
              ],
            ),
            const SizedBox(height: AppDimens.gapMd),
            Row(
              children: [
                cell(
                  '平均每笔',
                  MoneyUtil.centsToYuanGroupedTrimmed(avgPerBillCents),
                ),
                cell(
                  '平均每月',
                  MoneyUtil.centsToYuanGroupedTrimmed(avgPerMonthCents),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 柱状图卡片：年范围 12 月柱 + 顶部金额标注；月范围当月每日柱
/// （日柱密集不标金额，日期标签每 2 天显示一次）
class _RangeBarChart extends StatelessWidget {
  const _RangeBarChart({
    required this.period,
    required this.anchor,
    required this.bills,
    required this.color,
  });

  final HomePeriod period;

  /// 年模式取该年；月模式取该月
  final DateTime anchor;
  final List<Bill> bills;
  final Color color;

  /// 金额标注：1.4K / 800 等短格式
  static String _fmtShort(int cents) {
    final yuan = cents / 100;
    if (yuan >= 10000) return '${(yuan / 10000).toStringAsFixed(1)}万';
    if (yuan >= 1000) return '${(yuan / 1000).toStringAsFixed(1)}K';
    return yuan.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    List<int> bars;
    List<String> labels;
    bool showValues;
    if (period == HomePeriod.year) {
      bars = List<int>.filled(12, 0);
      for (final b in bills) {
        if (b.date.year == anchor.year) bars[b.date.month - 1] += b.amountCents;
      }
      labels = [for (var i = 1; i <= 12; i++) '$i月'];
      showValues = true;
    } else {
      final days = DateTime(anchor.year, anchor.month + 1, 0).day;
      bars = List<int>.filled(days, 0);
      for (final b in bills) {
        if (b.date.year == anchor.year && b.date.month == anchor.month) {
          bars[b.date.day - 1] += b.amountCents;
        }
      }
      // 每 2 天显示一次日期标签（2、4、6…），否则挤成一团
      labels = [for (var i = 1; i <= days; i++) i % 2 == 0 ? '$i' : ''];
      showValues = false;
    }
    final maxCents = bars.fold(0, math.max);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        AppDimens.gapSm,
        AppDimens.pagePadding,
        0,
      ),
      child: SectionCard(
        child: SizedBox(
          height: 170,
          child: CustomPaint(
            size: const Size(double.infinity, 170),
            painter: _BarChartPainter(
              bars: bars,
              labels: labels,
              maxCents: maxCents,
              color: color,
              labelFmt: _fmtShort,
              showValues: showValues,
            ),
          ),
        ),
      ),
    );
  }
}

/// 柱状图绘制：柱体 + 顶部金额（年模式）+ 底部标签（空串不画）
class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.bars,
    required this.labels,
    required this.maxCents,
    required this.color,
    required this.labelFmt,
    required this.showValues,
  });

  final List<int> bars;
  final List<String> labels;
  final int maxCents;
  final Color color;
  final String Function(int cents) labelFmt;
  final bool showValues;

  @override
  void paint(Canvas canvas, Size size) {
    const chartTop = 30.0; // 顶部金额标注留白
    const labelHeight = 18.0; // 底部标签高度
    final chartHeight = size.height - chartTop - labelHeight;
    final slot = size.width / bars.length;
    final barWidth = slot * 0.5;

    final paint = Paint()..color = color;
    for (var i = 0; i < bars.length; i++) {
      final cents = bars[i];
      final cx = slot * i + slot / 2;
      final h = maxCents == 0 || cents == 0
          ? 0.0
          : chartHeight * cents / maxCents;
      // 柱体（无数据不画柱，仅画标签）
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              cx - barWidth / 2,
              chartTop + chartHeight - h,
              barWidth,
              h,
            ),
            const Radius.circular(3),
          ),
          paint,
        );
        // 柱顶金额标注
        if (showValues) {
          _text(
            canvas,
            labelFmt(cents),
            Offset(cx, chartTop + chartHeight - h - 16),
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          );
        }
      }
      // 底部标签（空串跳过）：中心落在 labelHeight 区中央，
      // 避免文字上半截侵入柱体区域造成遮挡
      if (labels[i].isNotEmpty) {
        _text(
          canvas,
          labels[i],
          Offset(cx, chartTop + chartHeight + labelHeight / 2),
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center, {
    double fontSize = 10,
    Color color = AppColors.textSecondary,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) =>
      oldDelegate.bars != bars ||
      oldDelegate.maxCents != maxCents ||
      oldDelegate.color != color;
}

/// 按日分组的账单卡：日期头（左日期右小计）+ 统一条目列表，
/// 与首页明细同构（分组头格式见 DateLabelUtil）
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.date,
    required this.bills,
    required this.categories,
    required this.onDelete,
    required this.onCategoryTap,
    required this.showYear,
  });

  final DateTime date;
  final List<Bill> bills;
  final Map<int, Category> categories;
  final Future<void> Function(Bill bill) onDelete;

  /// 详情弹窗里点击分类行的跳转（内部钻取，由宿主传入）
  final void Function(Category category) onCategoryTap;

  /// 列表数据跨年时分组头带年份消歧（2025.09.29 周二），同年省略（09.29 周二）
  final bool showYear;

  @override
  Widget build(BuildContext context) {
    final expenseCents = bills
        .where((b) => b.type == BillType.expense)
        .fold(0, (s, b) => s + b.amountCents);
    final incomeCents = bills
        .where((b) => b.type == BillType.income)
        .fold(0, (s, b) => s + b.amountCents);
    final parts = <String>[
      if (expenseCents > 0) '支 ${MoneyUtil.centsToYuanTrimmed(expenseCents)}',
      if (incomeCents > 0) '收 ${MoneyUtil.centsToYuanTrimmed(incomeCents)}',
    ];

    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 日期分组头
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.cardPadding,
              AppDimens.gapMd,
              AppDimens.cardPadding,
              4,
            ),
            child: Row(
              children: [
                Text(
                  DateLabelUtil.headOf(date, showYear: showYear),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  parts.join('   '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // 条目与首页明细完全一致（共享 BillListItem），日期由组头表达
          for (var i = 0; i < bills.length; i++) ...[
            if (i > 0) const Divider(indent: 68, endIndent: 16),
            Builder(
              builder: (context) {
                final bill = bills[i];
                final category = categories[bill.categoryId];
                return BillListItem(
                  name: category?.name ?? '未知分类',
                  iconCode: category?.iconCode ?? Icons.help_outline.codePoint,
                  colorValue: category?.colorValue ?? 0xFFA8A8A8,
                  type: bill.type,
                  amountCents: bill.amountCents,
                  note: bill.note,
                  location: bill.location,
                  onTap: () => showBillDetailSheet(
                    context,
                    bill: bill,
                    categories: categories,
                    onCategoryTap: onCategoryTap,
                  ),
                  onLongPress: () => onDelete(bill),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 分类排行卡片：金额降序，附占比进度条；点击钻取到对应分类视图
class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.entries,
    required this.total,
    required this.onTap,
  });

  /// (分类, 名称, 金额分)，已按金额降序；分类为 null = 已删除，不可钻取
  final List<({Category? category, String name, int cents})> entries;
  final int total;
  final void Function(Category category) onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '分类排行',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.gapSm),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无数据',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            ...entries.map((e) {
              final color = e.category != null
                  ? Color(e.category!.colorValue)
                  : const Color(0xFFA8A8A8);
              final percent = total > 0 ? e.cents / total : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDimens.gapSm),
                child: InkWell(
                  onTap: e.category == null ? null : () => onTap(e.category!),
                  borderRadius: BorderRadius.circular(AppDimens.radiusControl),
                  child: Row(
                    children: [
                      // 排行头像：与全应用分类头像统一（40/21，文字图标显首字）
                      CategoryAvatar(
                        name: e.name,
                        iconCode: e.category?.iconCode ??
                            Icons.help_outline.codePoint,
                        color: e.category?.colorValue ?? 0xFFA8A8A8,
                      ),
                      const SizedBox(width: AppDimens.gapMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  e.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '¥${MoneyUtil.centsToYuanTrimmed(e.cents)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppDimens.gapSm),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    '${(percent * 100).toStringAsFixed(1)}%',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // 占比进度条
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 4,
                                backgroundColor: AppColors.divider,
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// 漏斗筛选面板：快捷范围胶囊 + 自定义起止日期 + 关键词搜索
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
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
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
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
