import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../providers/bill_provider.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/money_util.dart';
import '../../widgets/bill_list_item.dart';
import '../../widgets/pie_chart_card.dart';
import '../../widgets/section_card.dart';
import '../add_bill/add_bill_page.dart';
import '../add_bill/wheel_date_picker.dart';
import '../home/period_picker_dialog.dart';

/// 分类统计详情页：单个分类在所选时间范围内的汇总、月度分布、
/// 子分类构成环形图与账单明细
///
/// 从分类管理页的操作菜单进入（一级/二级分类共用）。一级分类的账单
/// 包含其子分类（数据层口径与统计页归并规则一致）。
/// 时间范围：顶栏副标题弹窗（按月/按年/全部）+ 漏斗面板（快捷范围
/// 与自定义起止日期），与首页口径一致。
class CategoryStatsPage extends StatefulWidget {
  const CategoryStatsPage({super.key, required this.category});

  final Category category;

  @override
  State<CategoryStatsPage> createState() => _CategoryStatsPageState();
}

class _CategoryStatsPageState extends State<CategoryStatsPage> {
  /// 查看范围（按月/按年/全部），与首页口径一致
  HomePeriod _period = HomePeriod.month;
  DateTime _month = DateTime.now();

  /// 自定义起止日期（含当天），两端可只选其一（开放端不限制）；
  /// 非空时优先于 [_period] 生效
  ({DateTime? start, DateTime? end})? _custom;

  /// 是否处于自定义日期区间模式
  bool get _isCustom => _custom != null;

  /// 二级分类的父分类名（标题显示"一级名-二级名"）
  String? _parentName;

  @override
  void initState() {
    super.initState();
    _loadParentName();
  }

  /// 取父分类名：二级分类标题需要"一级名-二级名"，一次性查询即可
  Future<void> _loadParentName() async {
    final pid = widget.category.parentId;
    if (pid == null) return;
    final map = await context
        .read<CategoryProvider>()
        .categoriesMapStream()
        .first;
    if (!mounted) return;
    setState(() => _parentName = map[pid]?.name);
  }

  /// 标题：二级 = "分类统计-一级名-二级名"，一级 = "分类统计-分类名"
  String get _title {
    final name = widget.category.name;
    final parent = _parentName;
    return '分类统计-${parent == null ? name : '$parent-$name'}';
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
      HomePeriod.year => (
        DateTime(_month.year),
        DateTime(_month.year + 1),
      ),
      HomePeriod.all => (null, null),
    };
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

  /// 漏斗面板应用回调
  void _applyFilter(
    HomePeriod period,
    DateTime month,
    ({DateTime? start, DateTime? end})? custom,
  ) {
    setState(() {
      _period = period;
      _month = month;
      _custom = custom;
    });
  }

  /// 右上角漏斗：快捷范围 + 自定义起止日期
  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _FilterSheet(
        initialPeriod: _period,
        initialMonth: _month,
        initialCustom: _custom,
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

  /// 环形图数据（仅一级分类）：按子分类聚合；直接挂一级或分类已不存在
  /// 的账单归并为"未细分"；按金额降序使引导线避让更自然。
  /// 颜色由共享环形图的色板自动分配，这里只出名称与金额。
  List<(String, int)> _pieItems(
    List<Bill> bills,
    Map<int, Category> categories,
  ) {
    final subSums = <int, int>{};
    var direct = 0;
    for (final b in bills) {
      final c = categories[b.categoryId];
      if (c != null && c.parentId == widget.category.id) {
        subSums[b.categoryId] = (subSums[b.categoryId] ?? 0) + b.amountCents;
      } else {
        direct += b.amountCents;
      }
    }
    final items = [
      for (final e in subSums.entries)
        (categories[e.key]?.name ?? '未知分类', e.value),
    ];
    if (direct > 0) items.add(('未细分', direct));
    items.sort((a, b) => b.$2.compareTo(a.$2));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = widget.category.type == BillType.expense;
    final amountColor = isExpense ? AppColors.expense : AppColors.income;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
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
          // 漏斗：自定义区间生效时主色高亮提示
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined, size: 22),
            color: _custom != null ? AppColors.primary : AppColors.textPrimary,
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: StreamBuilder<List<Bill>>(
        stream: context
            .read<BillProvider>()
            .categoryBillsStream(widget.category.id),
        builder: (context, snapshot) {
          final bills = snapshot.data ?? const <Bill>[];
          return StreamBuilder<Map<int, Category>>(
            stream: context.read<CategoryProvider>().categoriesMapStream(),
            builder: (context, mapSnapshot) {
              final categories =
                  mapSnapshot.data ?? const <int, Category>{};
              // 范围过滤（数据层为全量流，内存过滤足够）
              final (start, end) = _range;
              final filtered = bills.where((b) {
                if (start != null && b.date.isBefore(start)) return false;
                if (end != null && !b.date.isBefore(end)) return false;
                return true;
              }).toList();
              final total = filtered.fold<int>(
                0,
                (s, b) => s + b.amountCents,
              );
              final count = filtered.length;
              final avgPerBill = count == 0 ? 0 : total ~/ count;
              // 平均每月：按范围内有账单的月份数均摊
              final months = filtered
                  .map((b) => '${b.date.year}-${b.date.month}')
                  .toSet()
                  .length;
              final avgPerMonth = months == 0 ? 0 : total ~/ months;

              // 按月分组（数据已按日期倒序）
              final monthKeys = <String>[];
              final monthMap = <String, List<Bill>>{};
              for (final bill in filtered) {
                final key = '${bill.date.year}-${bill.date.month}';
                if (!monthMap.containsKey(key)) {
                  monthMap[key] = [];
                  monthKeys.add(key);
                }
                monthMap[key]!.add(bill);
              }
              // 数据横跨多个年份时，月份分组头带上年份（"2025年10月"）
              final crossYear = filtered.isNotEmpty &&
                  filtered.any((b) => b.date.year != filtered.first.date.year);

              return CustomScrollView(
                slivers: [
                  // 标题行下的年月胶囊条：固定在顶部（记一笔式立体效果），
                  // 可滑到 1970 年 1 月
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StripDelegate(
                      child: _PeriodStrip(
                        items: _stripItems,
                        period: _period,
                        month: _month,
                        isCustom: _isCustom,
                        onTap: _onStripTap,
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
                        bills: filtered,
                        color: amountColor,
                      ),
                    ),
                  // 子分类构成环形图：仅一级分类显示（与统计页同款组件）
                  if (widget.category.parentId == null)
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
                          items: _pieItems(filtered, categories),
                          centerLabel: '合计',
                          centerValue: MoneyUtil.centsToYuanGroupedTrimmed(
                            total,
                          ),
                          centerValueColor: amountColor,
                          emptyText: '该范围内暂无账单',
                        ),
                      ),
                    ),
                  if (count == 0)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          '该范围内暂无账单',
                          style: TextStyle(color: AppColors.textSecondary),
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
                        itemCount: monthKeys.length,
                        itemBuilder: (context, index) {
                          final monthBills = monthMap[monthKeys[index]]!;
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppDimens.gapSection,
                            ),
                            child: _MonthCard(
                              month: monthBills.first.date,
                              bills: monthBills,
                              categories: categories,
                              onDelete: _confirmDelete,
                              showYear: crossYear,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
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

/// 固定头部代理：滚动时年月条钉在页面顶部
class _StripDelegate extends SliverPersistentHeaderDelegate {
  _StripDelegate({required this.child});

  final Widget child;

  static const double _height = 51;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      child;

  @override
  bool shouldRebuild(_StripDelegate oldDelegate) => oldDelegate.child != child;
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
/// （日柱密集不标金额，日期标签每 3 天显示一次）
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
      labels = [
        for (var i = 1; i <= days; i++) i % 2 == 0 ? '$i' : '',
      ];
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
            Rect.fromLTWH(cx - barWidth / 2, chartTop + chartHeight - h,
                barWidth, h),
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

/// 按月分组的账单卡：月份头（左月右小计）+ 统一条目列表
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.bills,
    required this.categories,
    required this.onDelete,
    this.showYear = false,
  });

  final DateTime month;
  final List<Bill> bills;
  final Map<int, Category> categories;
  final Future<void> Function(Bill bill) onDelete;

  /// 范围跨年时分组头带年份（"2025年10月"），同一年内只显示"10月"
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
          // 月份分组头
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
                  showYear
                      ? '${month.year}年${month.month}月'
                      : '${month.month}月',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
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
          // 条目与首页明细完全一致（共享 BillListItem）
          for (var i = 0; i < bills.length; i++) ...[
            if (i > 0) const Divider(indent: 68, endIndent: 16),
            Builder(
              builder: (context) {
                final bill = bills[i];
                final category = categories[bill.categoryId];
                return BillListItem(
                  name: category?.name ?? '未知分类',
                  iconCode:
                      category?.iconCode ?? Icons.help_outline.codePoint,
                  colorValue: category?.colorValue ?? 0xFFA8A8A8,
                  type: bill.type,
                  amountCents: bill.amountCents,
                  note: bill.note,
                  location: bill.location,
                  // 月卡内无日分组头，条目自带头几号（年份已由月卡头表达）
                  dateLabel: '${bill.date.month}月${bill.date.day}日',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddBillPage(editBill: bill),
                    ),
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

/// 漏斗筛选面板：快捷范围胶囊 + 自定义起止日期（参考图 2 样式）
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initialPeriod,
    required this.initialMonth,
    required this.initialCustom,
    required this.onApply,
  });

  final HomePeriod initialPeriod;
  final DateTime initialMonth;
  final ({DateTime? start, DateTime? end})? initialCustom;
  final void Function(
    HomePeriod,
    DateTime,
    ({DateTime? start, DateTime? end})?,
  ) onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  /// 当前点亮的快捷项（自定义模式时为 null）
  String? _quick;

  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final custom = widget.initialCustom;
    if (custom == null) {
      _quick = switch (widget.initialPeriod) {
        HomePeriod.month => _isSameMonth(widget.initialMonth, DateTime.now())
            ? '本月'
            : null,
        HomePeriod.year => _isSameYear(widget.initialMonth, DateTime.now())
            ? '今年'
            : null,
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

  void _applyQuick(String label) {
    final now = DateTime.now();
    if (label == _crossYearLabel) {
      // 跨年统计走自定义区间：去年 1/1 ~ 今天（而非整年），范围模式不变。
      // 截止端为排他口径（<end），传"明天 0 点"才能把今天包含进来
      widget.onApply(
        widget.initialPeriod,
        widget.initialMonth,
        (
          start: DateTime(now.year - 1, 1, 1),
          end: DateTime(now.year, now.month, now.day + 1),
        ),
      );
    } else {
      final (period, month) = _quickValue(label);
      widget.onApply(period, month, null);
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

  /// 应用自定义区间（两端至少选了一个），关闭面板
  void _applyCustom() {
    if (_start == null && _end == null) return;
    widget.onApply(
      widget.initialPeriod,
      widget.initialMonth,
      (start: _start, end: _end),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Text(
              '自定义',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _chip(
                    _start == null
                        ? '开始日期'
                        : '${_start!.month}/${_start!.day}',
                    selected: _start != null,
                    fullWidth: true,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('-', style: TextStyle(color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: _chip(
                    _end == null ? '截止日期' : '${_end!.month}/${_end!.day}',
                    selected: _end != null,
                    fullWidth: true,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 确定：至少选了一端才可点；支持只选开始或只选截止（开放区间）
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed:
                    (_start == null && _end == null) ? null : _applyCustom,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.fill,
                  disabledForegroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  '确定',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 胶囊选项：快捷项宽度自适应内容（图 1 样式），日期胶囊撑满整列；
  /// 浅灰底圆角，选中浅蓝底蓝字
  Widget _chip(
    String label, {
    required bool selected,
    VoidCallback? onTap,
    bool fullWidth = false,
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
    );
  }
}
