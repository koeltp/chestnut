import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/bill_image_repository.dart';
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

/// 统计页（Tab 页 + 分类管理页独立 push 共用）：查询结果页模型
///
/// 页面只有一份查询参数 [StatsQuery]，渲染、筛选面板回显、返回还原
/// 全部只看这一份数据：
/// - 外部跳入（分类管理/详情）= 带初始参数 push，系统返回退出
/// - 点排行项/环图扇区/明细分类 = 当前参数快照压栈 + 换参数出结果
/// - 漏斗面板搜索 = 快照压栈 + 整组替换参数出结果
/// - 顶栏 ← = 弹栈还原快照；栈空交给系统默认返回（退出页面）
/// - 切月份/分段器 = 当前页内调节，不进栈
///
/// 视图形态由参数推导：categoryId 非空 = 分类视图（汇总卡 + 子分类
/// 环形图 + 明细）；空 = 全部视图（分段器 + 占比环形图 + 排行 + 明细）
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
  /// 当前查询参数：唯一状态源
  StatsQuery _query = StatsQuery(month: DateTime.now());

  /// 参数快照栈：跳转/搜索前的参数整体存档，← 逐级还原
  final List<StatsQuery> _history = [];

  /// 分类字典缓存：标题父名、面板回显派生、条件→视图映射都要查。
  /// build 每帧随流刷新；漏斗面板只能由点击打开，此时缓存必已就绪
  Map<int, Category> _categoriesCache = const {};

  /// 图片标记流及其 bills-id 键缓存：集合不变时复用同一流，
  /// StreamBuilder 不重订阅（换流空窗会让相机角标闪一下）
  Stream<Set<int>>? _imageIdsStream;
  List<int> _imageIdsKey = const [];

  @override
  void initState() {
    super.initState();
    // 外部带条件进入：换算成初始查询参数（带分类 = 分类视图 + 其类型）
    final cat = widget.initialCategory;
    final tag = widget.initialTag;
    if (cat != null || tag != null) {
      _query = StatsQuery(
        month: DateTime.now(),
        type: cat?.type ?? BillType.expense,
        categoryId: cat?.id,
        tagIds: tag == null ? const {} : {tag.id},
      );
    }
  }

  /// 当前视图分类（null = 全部视图）；分类被删后自动退回全部视图
  Category? _viewCategory(Map<int, Category> categories) =>
      _query.categoryId == null ? null : categories[_query.categoryId];

  // ---------------- 导航 ----------------

  /// 点击跳转（排行项/环图扇区/明细分类）：快照压栈 + 进入分类视图
  void _jumpToCategory(Category category) {
    if (_query.categoryId == category.id) return;
    setState(() {
      _history.add(_query);
      _query = _query.copyWith(
        categoryId: category.id,
        // 视图身份即过滤口径，进入分类视图清掉多选条件
        filterCategoryIds: const {},
      );
    });
  }

  /// 顶栏 ←：弹栈还原上一份参数快照；栈空时 leading 为 null，
  /// 由系统默认返回（Tab 页无按钮 / push 页退出）
  void _popView() {
    if (_history.isEmpty) return;
    setState(() => _query = _history.removeLast());
  }

  // ---------------- 筛选 ----------------

  /// 右上角漏斗：快捷范围 + 自定义起止日期 + 关键词搜索 + 标签多选。
  /// 面板回显 = 读当前参数（分类视图预填其分类完整组，全部视图预填
  /// 手动多选条件），所见即所应用
  Future<void> _showFilterSheet() async {
    final cid = _query.categoryId;
    final Set<int> initialCategoryIds;
    if (cid != null) {
      // 分类视图：预填该分类 + 全部子分类（与生效过滤口径一致）
      initialCategoryIds = {
        cid,
        for (final c in _categoriesCache.values)
          if (c.parentId == cid) c.id,
      };
    } else {
      initialCategoryIds = _query.filterCategoryIds;
    }
    if (!mounted) return;
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
        initialRange: _query.userRange,
        initialType: _viewCategory(_categoriesCache)?.type ?? _query.type,
        initialKeyword: _query.keyword,
        initialTagIds: _query.tagIds,
        initialCategoryIds: initialCategoryIds,
        onApply: _applyFilter,
      ),
    );
  }

  /// 漏斗面板应用回调（区间 + 关键词 + 标签 + 分类一并应用）：
  /// 快照压栈 + 整组替换参数出结果（每次搜索都是一次新导航，← 可回退）
  ///
  /// 面板只回传具体日期区间，此处把恰好整月/整年的区间归整回
  /// month/year 模式（标题、柱状图、年月条高亮与普通浏览一致）；
  /// 分类条件映射：恰好勾选"某分类+其全部子类"= 进入该分类视图
  /// （与点排行同效），空集 = 退出分类视图，其余组合 = 全部视图 +
  /// 多选过滤条件
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
      month = _query.month;
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
      month = s == null ? _query.month : DateTime(s.year, s.month);
      custom = range;
    }

    // 分类条件 → 视图身份映射（完整单组归入视图，混合多选作过滤条件）
    final viewCatId = _fullGroupCategoryId(categoryIds);
    setState(() {
      _history.add(_query);
      _query = _query.copyWith(
        period: period,
        month: month,
        custom: custom,
        keyword: keyword,
        tagIds: Set<int>.from(tagIds),
        categoryId: viewCatId,
        filterCategoryIds:
            viewCatId == null ? Set<int>.from(categoryIds) : const {},
      );
    });
  }

  /// 若勾选集合恰好构成"某一级分类 + 其全部子分类"的完整组，
  /// 返回该一级分类 id（即视为进入该分类视图）；否则返回 null
  int? _fullGroupCategoryId(Set<int> ids) {
    if (ids.isEmpty) return null;
    final roots = [
      for (final id in ids)
        if (_categoriesCache[id]?.parentId == null) _categoriesCache[id]!,
    ];
    if (roots.length != 1) return null;
    final root = roots.first;
    final expected = {
      root.id,
      for (final c in _categoriesCache.values)
        if (c.parentId == root.id) c.id,
    };
    return expected.length == ids.length && ids.containsAll(expected)
        ? root.id
        : null;
  }

  /// 顶栏副标题点击：弹出范围选择（与首页同款弹窗）；页内调节不进栈
  Future<void> _pickPeriod() async {
    final result = await PeriodPickerDialog.show(
      context,
      initialMode: _query.period,
      initialMonth: _query.month,
    );
    if (result == null || !mounted) return;
    setState(() {
      _query = _query.copyWith(
        period: result.$1,
        month: result.$2 ?? _query.month,
        custom: null,
      );
    });
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
  /// 当前年只铺到当前月（未来月份无意义），历史年份 12 个月全铺
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

  /// 横滑条点击：点年份统计整年、点月份统计单月；页内调节不进栈
  void _onStripTap(int year, int? month) {
    setState(() {
      _query = _query.copyWith(
        custom: null,
        period: month == null ? HomePeriod.year : HomePeriod.month,
        month: month == null ? DateTime(year) : DateTime(year, month),
      );
    });
  }

  /// 当前视图的账单流：分类视图为该分类流；全部视图恒为全量账单流——
  /// 日期/分类/标签/关键词全部内存过滤。仅参数变化时随 build 换流
  Stream<List<Bill>> _billsStream(BillProvider provider) {
    final cid = _query.categoryId;
    if (cid != null) return provider.categoryBillsStream(cid);
    // 全部视图统一监听全量账单：切换筛选不重订阅全量流、无加载空窗；
    // 个人数据量下无性能压力
    return provider.billsInRangeStream(HomePeriod.all, _query.month);
  }

  /// 去年同期对比流（柱状图灰色背景柱）：按月/按年整体平移一年；
  /// 自定义区间、"全部"与分类视图无对比基准，给同步空流占位
  Stream<List<Bill>> _compareStream(BillProvider provider) {
    final q = _query;
    if (q.categoryId != null || q.custom != null || q.period == HomePeriod.all) {
      return Stream.value(const <Bill>[]);
    }
    final anchor = q.period == HomePeriod.year
        ? DateTime(q.month.year - 1)
        : DateTime(q.month.year - 1, q.month.month);
    return provider.billsInRangeStream(q.period, anchor);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<BillProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      // AppBar 依赖分类字典（标题父名），放进字典流的 builder 内构建
      body: StreamBuilder<Map<int, Category>>(
        stream: context.read<CategoryProvider>().categoriesMapStream(),
        builder: (context, catSnapshot) {
          final categories = catSnapshot.data ?? const <int, Category>{};
          // 缓存供面板回显与条件映射同步查询（见成员注释）
          _categoriesCache = categories;
          final viewCat = _viewCategory(categories);
          final isAllView = viewCat == null;
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              centerTitle: true,
              // 快照栈非空显示 ←（弹栈还原）；栈空时 Tab 页无按钮、
              // push 页由系统默认返回箭头兜底（退出统计页）
              leading: _history.isNotEmpty
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
                      _title(categories, viewCat),
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
                // 漏斗：自定义区间或任一搜索条件生效时主色高亮提示
                //（分类视图身份不算条件，不亮漏斗）
                IconButton(
                  icon: const Icon(Icons.filter_alt_outlined, size: 22),
                  color: (_query.custom != null ||
                          _query.keyword.isNotEmpty ||
                          _query.tagIds.isNotEmpty ||
                          _query.filterCategoryIds.isNotEmpty)
                      ? AppColors.primary
                      : AppColors.textPrimary,
                  onPressed: _showFilterSheet,
                ),
              ],
            ),
            body: StreamBuilder<List<Bill>>(
              stream: _billsStream(provider),
              builder: (context, snapshot) {
                // 换流空窗（筛选变化重订阅 drift 流）显示加载态，
                // 而不是当空列表顶"暂无账单"空态，避免闪现误导
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final bills = snapshot.data!;
                // 图片标记改为订阅流（bill_images 表增删实时刷新角标）；
                // 按当前 bills 的 id 集合缓存流实例，集合不变时 StreamBuilder
                // 不重订阅，避免换流空窗闪一下
                final ids = bills.map((b) => b.id).toList();
                if (!listEquals(ids, _imageIdsKey)) {
                  _imageIdsKey = ids;
                  _imageIdsStream = context
                      .read<BillImageRepository>()
                      .watchBillIdsWithImages(ids);
                }
                // 标签批量加载（既用于条目显示也用于按选中标签过滤）
                return FutureBuilder<Map<int, List<Tag>>>(
                  future: context
                      .read<TagRepository>()
                      .getTagsByBillIds(ids),
                  builder: (context, tagSnapshot) {
                    final tagsByBill = tagSnapshot.data ??
                        const <int, List<Tag>>{};
                    // 标签过滤：账单挂了任一选中标签即保留；未选标签则全部保留
                    final visible = _query.tagIds.isEmpty
                        ? bills
                        : bills
                            .where((b) =>
                                (tagsByBill[b.id] ?? const [])
                                    .any((t) => _query.tagIds.contains(t.id)))
                            .toList();
                    return StreamBuilder<Set<int>>(
                      stream: _imageIdsStream,
                      builder: (context, imgSnapshot) {
                        final imageBillIds =
                            imgSnapshot.data ?? const <int>{};
                        return StreamBuilder<List<Bill>>(
                          stream: _compareStream(provider),
                          builder: (context, prevSnapshot) {
                            return _buildBody(
                              visible,
                              categories,
                              viewCat,
                              isAllView,
                              prevSnapshot.data ?? const <Bill>[],
                              tagsByBill: tagsByBill,
                              imageBillIds: imageBillIds,
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
        },
      ),
    );
  }

  /// 标题：全部视图 = "统计"；分类 = "分类统计-一级名-二级名"
  ///（父名从字典实时查，无需单独同步状态）
  String _title(Map<int, Category> categories, Category? viewCat) {
    if (viewCat == null) return '统计';
    final parent =
        viewCat.parentId == null ? null : categories[viewCat.parentId];
    return '分类统计-${parent == null ? viewCat.name : '${parent.name}-${viewCat.name}'}';
  }

  /// 顶栏副标题：当前查看范围（自定义时显示起止日期，跨年显示"某年-某年"）
  String get _subtitle {
    final custom = _query.custom;
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
    return switch (_query.period) {
      HomePeriod.month =>
        '${_query.month.year}年${_query.month.month}月',
      HomePeriod.year => '${_query.month.year}年',
      HomePeriod.all => '全部',
    };
  }

  /// 页面主体：pinned 头部（类型分段器 + 年月条）+ 汇总/图表/明细
  Widget _buildBody(
    List<Bill> bills,
    Map<int, Category> categories,
    Category? viewCat,
    bool isAllView,
    List<Bill> prevBills, {
    Map<int, List<Tag>> tagsByBill = const {},
    Set<int> imageBillIds = const {},
  }) {
    // 范围过滤（数据层为全量流，内存过滤足够）
    final (start, end) = _query.range;
    var filtered = bills.where((b) {
      if (start != null && b.date.isBefore(start)) return false;
      if (end != null && !b.date.isBefore(end)) return false;
      return true;
    }).toList();
    filtered = applyKeyword(filtered, categories, _query.keyword);

    // 分类过滤：只认账单自身的 categoryId，不做"一级 id 自动展开全部
    // 二级"。分类视图按 视图分类+其全部子分类 命中；全部视图按面板
    // 多选条件精确命中（整组语义由"点一级全选"生成的集合表达）
    final cid = viewCat?.id;
    if (cid != null) {
      final ids = {
        cid,
        for (final c in categories.values)
          if (c.parentId == cid) c.id,
      };
      filtered =
          filtered.where((b) => ids.contains(b.categoryId)).toList();
    } else if (_query.filterCategoryIds.isNotEmpty) {
      filtered = filtered
          .where((b) => _query.filterCategoryIds.contains(b.categoryId))
          .toList();
    }

    // 分段器是整页开关：全部视图下汇总/图表/明细都只展示当前收支
    // 类型的数据；分类视图 typeBills 即 filtered（单分类类型固定）
    final typeBills = isAllView
        ? filtered.where((b) => b.type == _query.type).toList()
        : filtered;
    final isExpense = isAllView
        ? _query.type == BillType.expense
        : viewCat!.type == BillType.expense;
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
    final catEntries = isAllView
        ? aggregateByCategory(typeBills, categories)
        : const <({Category? category, String name, int cents})>[];
    // 子分类构成环形图（分类视图仅一级分类）
    final subEntries = (viewCat != null && viewCat.parentId == null)
        ? pieEntries(filtered, categories, viewCat)
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
    final emptyText =
        _query.keyword.trim().isEmpty ? '该范围内暂无账单' : '未找到匹配账单';
    // 优惠统计（仅支出）：随当前筛选范围/分类视图自动收窄
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
                (isAllView ? StatsHeaderDelegate.segHeight : 0),
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  if (isAllView)
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
                          selected: _query.type,
                          onChanged: (t) =>
                              setState(() => _query = _query.copyWith(type: t)),
                        ),
                      ),
                    ),
                  StatsPeriodStrip(
                    items: _stripItems,
                    period: _query.period,
                    month: _query.month,
                    isCustom: _query.custom != null,
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
        if (_query.custom == null && _query.period != HomePeriod.all)
          SliverToBoxAdapter(
            child: StatsRangeBarChart(
              period: _query.period,
              anchor: _query.month,
              bills: typeBills,
              prevBills:
                  prevBills.where((b) => b.type == _query.type).toList(),
              color: amountColor,
            ),
          ),
        // 分类占比环形图（全部视图）：点扇区跳转到对应分类视图
        if (isAllView)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pagePadding,
                AppDimens.gapSm,
                AppDimens.pagePadding,
                0,
              ),
              child: PieChartCard(
                title: '${_query.type.label}分类占比',
                items: [for (final e in catEntries) (e.name, e.cents)],
                centerLabel: '${_query.type.label}合计',
                centerValue: MoneyUtil.centsToYuanGroupedTrimmed(total),
                centerValueColor: amountColor,
                emptyText: emptyText,
                onSliceTap: (i) {
                  final target = catEntries[i].category;
                  if (target != null) _jumpToCategory(target);
                },
              ),
            ),
          ),
        // 分类排行（全部视图）：点条目跳转到对应分类视图
        if (isAllView)
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
                onTap: _jumpToCategory,
              ),
            ),
          ),
        // 子分类构成环形图（分类视图仅一级分类）：点扇区跳到子分类视图
        if (viewCat != null && viewCat.parentId == null)
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
                  if (target != null) _jumpToCategory(target);
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
                    onCategoryTap: _jumpToCategory,
                    tagsByBill: tagsByBill,
                    imageBillIds: imageBillIds,
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

/// 可空字段哨兵：区分 copyWith"不修改"与"置为 null"
const Object _unset = _Unset();

class _Unset {
  const _Unset();
}

/// 统计查询参数（不可变快照）：统计页唯一状态源。
///
/// [_history] 里存的就是本对象的快照，← 还原 = 换回旧快照重新搜索；
/// 视图身份（categoryId）与多选过滤条件（filterCategoryIds）分离：
/// 前者由跳转/完整组搜索产生并决定页面形态，后者是普通筛选条件
class StatsQuery {
  const StatsQuery({
    this.period = HomePeriod.month,
    DateTime? month,
    this.custom,
    this.type = BillType.expense,
    this.categoryId,
    this.filterCategoryIds = const {},
    this.keyword = '',
    this.tagIds = const {},
  })  : assert(month != null || custom != null || true),
        _month = month;

  /// 月/年锚点（period 为 month/year 时生效）；创建时默认当前月
  final DateTime? _month;
  DateTime get month => _month ?? DateTime.now();

  /// 查看范围（按月/按年/全部），与首页口径一致
  final HomePeriod period;

  /// 自定义起止日期（开始含当天、截止排他），两端可只选其一（开放端
  /// 不限制）；非空时优先于 [period] 生效
  final ({DateTime? start, DateTime? end})? custom;

  /// 全部视图的收支类型（分类视图由分类自身类型决定）
  final BillType type;

  /// 分类视图身份（null = 全部视图）
  final int? categoryId;

  /// 面板多选分类过滤条件（仅全部视图生效）；分类视图恒为空
  final Set<int> filterCategoryIds;

  /// 已应用的搜索关键词（空 = 未筛选）：过滤备注/定位完整信息/分类名
  final String keyword;

  /// 已选标签 id 集合（空 = 不按标签筛选）；多个标签取并集
  final Set<int> tagIds;

  /// 当前范围的 [start, end) 查询边界。
  /// 口径：开始日与截止日均**含当天**——自定义区间的截止端在内部
  /// +1 天转为排他边界（选 10/31 = 查到 10/31 当天）；
  /// 全部模式与开放端为 null（不限制）
  (DateTime?, DateTime?) get range {
    final c = custom;
    if (c != null) {
      final s = c.start;
      final e = c.end;
      return (
        s == null ? null : DateTime(s.year, s.month, s.day),
        e == null ? null : DateTime(e.year, e.month, e.day + 1),
      );
    }
    return switch (period) {
      HomePeriod.month => (
          DateTime(month.year, month.month),
          DateTime(month.year, month.month + 1),
        ),
      HomePeriod.year => (
          DateTime(month.year),
          DateTime(month.year + 1),
        ),
      HomePeriod.all => (null, null),
    };
  }

  /// 当前范围的用户语义区间（起止均含当天）：筛选面板据此回显。
  /// period 模式也表达成具体日期，面板内即可统一编辑
  ({DateTime? start, DateTime? end}) get userRange {
    final c = custom;
    if (c != null) return c;
    return switch (period) {
      HomePeriod.month => (
          start: DateTime(month.year, month.month, 1),
          end: DateTime(
            month.year,
            month.month,
            DateTime(month.year, month.month + 1, 0).day,
          ),
        ),
      HomePeriod.year => (
          start: DateTime(month.year, 1, 1),
          end: DateTime(month.year, 12, 31),
        ),
      HomePeriod.all => (start: null, end: null),
    };
  }

  /// 复制并修改部分字段；可空字段（custom/categoryId）默认不修改，
  /// 传 [_unset] 以外的值即修改（含显式置 null）
  // ignore: library_private_types_in_public_api
  StatsQuery copyWith({
    HomePeriod? period,
    DateTime? month,
    Object? custom = _unset,
    BillType? type,
    Object? categoryId = _unset,
    Set<int>? filterCategoryIds,
    String? keyword,
    Set<int>? tagIds,
  }) {
    return StatsQuery(
      period: period ?? this.period,
      month: month ?? _month,
      custom: custom == _unset
          ? this.custom
          : custom as ({DateTime? start, DateTime? end})?,
      type: type ?? this.type,
      categoryId:
          categoryId == _unset ? this.categoryId : categoryId as int?,
      filterCategoryIds: filterCategoryIds ?? this.filterCategoryIds,
      keyword: keyword ?? this.keyword,
      tagIds: tagIds ?? this.tagIds,
    );
  }
}
