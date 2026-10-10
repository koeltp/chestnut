import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_label_util.dart';
import '../../utils/money_util.dart';
import '../../widgets/bill_detail_sheet.dart';
import '../../widgets/bill_list_item.dart';
import '../../widgets/category_avatar.dart';
import '../../widgets/section_card.dart';

/// 固定头部代理：滚动时类型分段器与年月条整体钉在页面顶部
class StatsHeaderDelegate extends SliverPersistentHeaderDelegate {
  StatsHeaderDelegate({required this.child, required this.height});

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
  bool shouldRebuild(StatsHeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
}

/// 标题行下的年月胶囊条（固定在页面顶部，记一笔式底部立体效果）：
/// 点年份统计整年、点月份统计单月，向右滑动可一直回溯到 1970 年 1 月；
/// 范围由漏斗等外部改变时自动滚动到选中项
class StatsPeriodStrip extends StatefulWidget {
  const StatsPeriodStrip({
    super.key,
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
  State<StatsPeriodStrip> createState() => _StatsPeriodStripState();
}

class _StatsPeriodStripState extends State<StatsPeriodStrip> {
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
  void didUpdateWidget(StatsPeriodStrip oldWidget) {
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
class StatsSummaryCard extends StatelessWidget {
  const StatsSummaryCard({
    super.key,
    required this.isExpense,
    required this.amountColor,
    required this.totalCents,
    required this.count,
    required this.avgPerBillCents,
    required this.avgPerMonthCents,
    this.discountCount = 0,
    this.discountCents = 0,
  });

  final bool isExpense;
  final Color amountColor;
  final int totalCents;
  final int count;
  final int avgPerBillCents;
  final int avgPerMonthCents;

  /// 优惠笔数与节省总额（分）；仅支出视图可能 >0
  final int discountCount;
  final int discountCents;

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
            // 优惠行：仅支出视图且当前筛选范围内存在优惠账单时出现，
            // 数据随筛选（日期范围/分类钻取）自动收窄
            if (isExpense && discountCount > 0) ...[
              const SizedBox(height: AppDimens.gapMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '共优惠 $discountCount 笔，省 ',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '¥${MoneyUtil.centsToYuanGroupedTrimmed(discountCents)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.income,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 按日分组的账单卡：日期头（左日期右小计）+ 统一条目列表，
/// 与首页明细同构（分组头格式见 DateLabelUtil）
class StatsDayCard extends StatelessWidget {
  const StatsDayCard({
    super.key,
    required this.date,
    required this.bills,
    required this.categories,
    required this.onDelete,
    required this.onCategoryTap,
    required this.showYear,
    this.tagsByBill = const {},
    this.imageBillIds = const {},
    this.assets = const {},
    this.onTagTap,
  });

  final DateTime date;
  final List<Bill> bills;
  final Map<int, Category> categories;
  final Future<void> Function(Bill bill) onDelete;

  /// 详情弹窗里点击分类行的跳转（内部钻取，由宿主传入）
  final void Function(Category category) onCategoryTap;

  /// billId → 标签列表（由宿主批量加载后传入，条目与详情共用）
  final Map<int, List<Tag>> tagsByBill;

  /// 挂有图片的账单 id 集合（宿主批量加载，条目显示相机小角标）
  final Set<int> imageBillIds;

  /// id → 资产映射（金额下方账户小字查名用）
  final Map<int, Asset> assets;

  /// 详情弹窗里点击标签的跳转（宿主决定落点）
  final void Function(Tag tag)? onTagTap;

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
                  discountCents: bill.discountCents,
                  note: bill.note,
                  location: bill.location,
                  tags: tagsByBill[bill.id],
                  hasImage: imageBillIds.contains(bill.id),
                  accountLine: billAccountLine(bill, assets),
                  onTap: () => showBillDetailSheet(
                    context,
                    bill: bill,
                    categories: categories,
                    onCategoryTap: onCategoryTap,
                    onTagTap: onTagTap,
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
class StatsRankingCard extends StatelessWidget {
  const StatsRankingCard({
    super.key,
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
                        iconCode:
                            e.category?.iconCode ??
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
