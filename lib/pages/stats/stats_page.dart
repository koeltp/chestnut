import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../models/enums.dart';
import '../../providers/bill_provider.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/money_util.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/pie_chart_card.dart';
import '../home/period_picker_dialog.dart';
import 'stats_charts.dart';
import 'stats_filter_sheet.dart';
import 'stats_logic.dart';
import 'stats_widgets.dart';

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
  const StatsPage({super.key, this.initialCategory, this.initialTag});

  /// 非空时直接进入该分类视图（分类管理页"查看统计数据"入口）
  final Category? initialCategory;

  /// 非空时按该标签筛选（首页/详情"点标签跳转"入口）
  final Tag? initialTag;

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

  /// 已选标签 id 集合（空 = 不按标签筛选）；多个标签取并集（账单挂了
  /// 任一选中标签即保留）
  final Set<int> _selectedTagIds = {};

  /// 已选分类 id 集合（空 = 不按分类筛选）：
  /// 只按账单自身的 categoryId 精确命中——一级 id 只命中挂在一级
  /// 本身的账单，二级 id 只命中挂在该二级的账单；"整组"语义由
  /// 多选弹层"点一级全选"生成的集合表达
  final Set<int> _selectedCategoryIds = {};

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial != null) _syncCategoryView(initial);
    // 标签筛选初始值（从详情/首页点标签跳转过来）
    final tag = widget.initialTag;
    if (tag != null) _selectedTagIds.add(tag.id);
  }

  /// 取父分类名 + 同步筛选回显：当前查看分类写入 _selectedCategoryIds
  ///（一级须连同全部子分类——分类过滤只认账单自身 categoryId，
  /// 不含子分类则其下账单不命中）。外部跳入/页面内钻取/返回
  /// 都会经过这里，保证漏斗面板所见即当前视图
  Future<void> _syncCategoryView(Category category) async {
    final map = await context
        .read<CategoryProvider>()
        .categoriesMapStream()
        .first;
    // await 期间可能已钻取/返回，过期结果不得覆盖新视图状态
    if (!mounted || _category?.id != category.id) return;
    final ids = <int>{category.id};
    for (final c in map.values) {
      if (c.parentId == category.id) ids.add(c.id);
    }
    setState(() {
      _parentName = map[category.parentId]?.name;
      _selectedCategoryIds
        ..clear()
        ..addAll(ids);
    });
  }

  /// 钻取到分类视图（点排行项/环图扇区）：压栈而非换页，
  /// 当前时间范围与关键词筛选保持不变
  void _drillTo(Category category) {
    if (_category?.id == category.id) return;
    setState(() {
      _stack.add(category);
      _parentName = null;
    });
    _syncCategoryView(category);
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
    if (cur != null) _syncCategoryView(cur);
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

  /// 当前范围的 [start, end) 查询边界。
  /// 口径：开始日与截止日均**含当天**——自定义区间的截止端在内部
  /// +1 天转为排他边界（选 10/31 = 查到 10/31 当天）；
  /// 全部模式与开放端为 null（不限制）
  (DateTime?, DateTime?) get _range {
    final custom = _custom;
    if (custom != null) {
      final s = custom.start;
      final e = custom.end;
      return (
        s == null ? null : DateTime(s.year, s.month, s.day),
        e == null ? null : DateTime(e.year, e.month, e.day + 1),
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

  /// 当前范围的用户语义区间（起止均含当天）：筛选面板据此回显。
  /// period 模式也表达成具体日期，面板内即可统一编辑
  ({DateTime? start, DateTime? end}) get _userRange {
    final custom = _custom;
    if (custom != null) return custom;
    return switch (_period) {
      HomePeriod.month => (
        start: DateTime(_month.year, _month.month, 1),
        end: DateTime(
          _month.year,
          _month.month,
          DateTime(_month.year, _month.month + 1, 0).day,
        ),
      ),
      HomePeriod.year => (
        start: DateTime(_month.year, 1, 1),
        end: DateTime(_month.year, 12, 31),
      ),
      HomePeriod.all => (start: null, end: null),
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

  /// 漏斗面板应用回调（区间 + 关键词 + 标签 + 分类一并应用）。
  ///
  /// 面板只回传具体日期区间，此处把恰好整月/整年的区间归整回
  /// month/year 模式（标题、柱状图、年月条高亮与普通浏览一致），
  /// 其余区间作为 custom 保留
  void _applyFilter(
    ({DateTime? start, DateTime? end}) range,
    String keyword,
    Set<int> tagIds,
    Set<int> categoryIds,
  ) {
    final s = range.start;
    final e = range.end;

    HomePeriod period;
    DateTime month;
    ({DateTime? start, DateTime? end})? custom;

    if (s == null && e == null) {
      period = HomePeriod.all;
      month = _month;
    } else if (s != null &&
        e != null &&
        s.year == e.year &&
        s.month == e.month &&
        s.day == 1 &&
        e.day == DateTime(s.year, s.month + 1, 0).day) {
      // 恰好整月：归整为月模式
      period = HomePeriod.month;
      month = DateTime(s.year, s.month);
    } else if (s != null &&
        e != null &&
        s.year == e.year &&
        s.month == 1 &&
        s.day == 1 &&
        e.month == 12 &&
        e.day == 31) {
      // 恰好整年：归整为年模式
      period = HomePeriod.year;
      month = DateTime(s.year);
    } else {
      // 开放端或任意区间：自定义模式（锚点沿用开始端，无开始端用当前月）
      period = HomePeriod.month;
      month = s == null ? _month : DateTime(s.year, s.month);
      custom = range;
    }

    setState(() {
      _period = period;
      _month = month;
      _custom = custom;
      _keyword = keyword;
      _selectedTagIds
        ..clear()
        ..addAll(tagIds);
      _selectedCategoryIds
        ..clear()
        ..addAll(categoryIds);
    });
  }

  /// 右上角漏斗：快捷范围 + 自定义起止日期 + 关键词搜索 + 标签多选
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
      builder: (_) => StatsFilterSheet(
        initialRange: _userRange,
        initialType: _isAllView ? _type : _category!.type,
        initialKeyword: _keyword,
        initialTagIds: _selectedTagIds,
        initialCategoryIds: _selectedCategoryIds,
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
  /// 全部视图恒为全量账单流——所有筛选内存过滤，切换条件
  /// 不触发重订阅。仅视图栈变化（钻取/返回）时重新订阅
  Stream<List<Bill>> _billsStream(BillProvider provider) {
    final c = _category;
    if (c != null) return provider.categoryBillsStream(c.id);
    // 全部视图统一监听全量账单：日期/分类/标签/关键词全部内存过滤，
    // 切换筛选不再重订阅、无加载空窗；个人数据量下无性能压力
    return provider.billsInRangeStream(HomePeriod.all, _month);
  }

  /// 去年同期对比流（柱状图灰色背景柱）：按月/按年整体平移一年；
  /// 自定义区间、"全部"与分类视图无对比基准，给同步空流占位
  Stream<List<Bill>> _compareStream(BillProvider provider) {
    if (!_isAllView || _isCustom || _period == HomePeriod.all) {
      return Stream.value(const <Bill>[]);
    }
    final anchor = _period == HomePeriod.year
        ? DateTime(_month.year - 1)
        : DateTime(_month.year - 1, _month.month);
    return provider.billsInRangeStream(_period, anchor);
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
            color: (_isCustom ||
                    _keyword.isNotEmpty ||
                    _selectedTagIds.isNotEmpty ||
                    _selectedCategoryIds.isNotEmpty)
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
              final bills = snapshot.data!;
              // 统一批量加载当前 bills 的标签（本地小表，一次查询）：
              // 既用于下方条目显示标签，也用于按选中标签过滤
              return FutureBuilder<Map<int, List<Tag>>>(
                future: context.read<TagRepository>().getTagsByBillIds(
                      bills.map((b) => b.id).toList(),
                    ),
                builder: (context, tagSnapshot) {
                  final tagsByBill = tagSnapshot.data ?? const <int, List<Tag>>{};
                  // 标签过滤：账单挂了任一选中标签即保留；未选标签则全部保留
                  final visible = _selectedTagIds.isEmpty
                      ? bills
                      : bills
                          .where((b) =>
                              (tagsByBill[b.id] ?? const [])
                                  .any((t) => _selectedTagIds.contains(t.id)))
                          .toList();
                  return StreamBuilder<List<Bill>>(
                    stream: _compareStream(provider),
                    builder: (context, prevSnapshot) {
                      return _buildBody(
                        visible,
                        categories,
                        prevSnapshot.data ?? const <Bill>[],
                        tagsByBill: tagsByBill,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// 页面主体：pinned 头部（类型分段器 + 年月条）+ 汇总/图表/明细
  Widget _buildBody(
    List<Bill> bills,
    Map<int, Category> categories,
    List<Bill> prevBills, {
    Map<int, List<Tag>> tagsByBill = const {},
  }) {
    // 范围过滤（数据层为全量流，内存过滤足够）
    final (start, end) = _range;
    var filtered = bills.where((b) {
      if (start != null && b.date.isBefore(start)) return false;
      if (end != null && !b.date.isBefore(end)) return false;
      return true;
    }).toList();
    filtered = applyKeyword(filtered, categories, _keyword);

    // 分类筛选：只认账单自身的 categoryId——选中集合包含什么就命中
    // 什么，不做"一级 id 自动展开全部二级"；整组语义由多选弹层
    // "点一级全选"动作生成的集合表达（避免只选地铁却命中整组交通）
    if (_selectedCategoryIds.isNotEmpty) {
      filtered = filtered
          .where((b) => _selectedCategoryIds.contains(b.categoryId))
          .toList();
    }

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
        ? aggregateByCategory(typeBills, categories)
        : const <({Category? category, String name, int cents})>[];
    // 子分类构成环形图（分类视图仅一级分类）
    final subEntries = (c != null && c.parentId == null)
        ? pieEntries(filtered, categories, c)
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
    // 优惠统计（仅支出）：随当前筛选范围/分类钻取自动收窄
    final discountBills = isExpense
        ? typeBills.where((b) => (b.discountCents ?? 0) > 0).toList()
        : const <Bill>[];
    final discountCount = discountBills.length;
    final discountTotal = discountBills.fold<int>(
      0,
      (sum, b) => sum + b.discountCents!,
    );

    return CustomScrollView(
      slivers: [
        // 固定头部：全部视图多一行收支类型分段器，滚动时整体钉在顶部
        SliverPersistentHeader(
          pinned: true,
          delegate: StatsHeaderDelegate(
            height:
                StatsHeaderDelegate.stripHeight +
                (_isAllView ? StatsHeaderDelegate.segHeight : 0),
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
                          // 等分风格：两项各占一半无缝贴合，
                          // 总宽仍为内容自然宽（窄条居中不变）
                          fit: AppSegmentedFit.equal,
                          options: [
                            for (final t in BillType.values) (t, t.label),
                          ],
                          colors: const [AppColors.expense, AppColors.income],
                          selected: _type,
                          onChanged: (t) => setState(() => _type = t),
                        ),
                      ),
                    ),
                  StatsPeriodStrip(
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
          child: StatsSummaryCard(
            isExpense: isExpense,
            amountColor: amountColor,
            totalCents: total,
            count: count,
            avgPerBillCents: avgPerBill,
            avgPerMonthCents: avgPerMonth,
            discountCount: discountCount,
            discountCents: discountTotal,
          ),
        ),
        // 柱状图：年范围 12 月柱（带金额标注），月范围当月每日柱；
        // 去年同期数据画成灰色背景柱辅助对比（按当前收支类型过滤）
        if (!_isCustom && _period != HomePeriod.all)
          SliverToBoxAdapter(
            child: StatsRangeBarChart(
              period: _period,
              anchor: _month,
              bills: typeBills,
              prevBills: prevBills.where((b) => b.type == _type).toList(),
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
              child: StatsRankingCard(
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
                items: [for (final e in subEntries) (e.name, e.cents)],
                centerLabel: '合计',
                centerValue: MoneyUtil.centsToYuanGroupedTrimmed(total),
                centerValueColor: amountColor,
                emptyText: emptyText,
                onSliceTap: (i) {
                  final target = subEntries[i].category;
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
                  child: StatsDayCard(
                    date: dayBills.first.date,
                    bills: dayBills,
                    categories: categories,
                    onDelete: _confirmDelete,
                    onCategoryTap: _drillTo,
                    tagsByBill: tagsByBill,
                    onTagTap: (tag) => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => StatsPage(initialTag: tag),
                      ),
                    ),
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
