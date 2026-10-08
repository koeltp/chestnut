import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../models/enums.dart';
import '../../models/summaries.dart';
import '../../providers/bill_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/lock_provider.dart';
import '../../services/update_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/date_label_util.dart';
import '../../utils/money_util.dart';
import '../../widgets/bill_detail_sheet.dart';
import '../../widgets/bill_list_item.dart';
import '../../widgets/month_switcher.dart';
import '../../widgets/section_card.dart';
import '../../widgets/update_dialog.dart';
import '../settings/backup_page.dart';
import '../stats/stats_page.dart';
import 'period_picker_dialog.dart';

/// 首页：当前查看范围（月/年/全部）的收支汇总 + 按日分组的账单卡片列表
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // 数据库为惰性打开：首页账单流订阅即触发打开，降级发生时才写入
    // 标记，延迟 2 秒检查确保标记已落盘
    Future<void>.delayed(const Duration(seconds: 2), _showDowngradeNotice);
    // 自更新检测：再延后 1.5 秒避开启动任务与降级提示，失败完全静默。
    // Dev 包跳过：应用内更新安装的是生产包（包名不同），在 Dev 包里
    // 走下载安装只会多装出一个生产包，纯属误导
    if (kDebugMode) return;
    Future<void>.delayed(const Duration(seconds: 4), _checkAppUpdate);
  }

  /// 启动自动更新检查。
  ///
  /// 打扰纪律：锁屏遮罩展示中 / 已有弹窗（如降级提示）压栈时放弃本次；
  /// 该版本被用户点过"以后再说"不再自动弹（手动检查不受限）。
  /// 网络或服务异常一律静默——自更新绝不能干扰记账主流程。
  Future<void> _checkAppUpdate() async {
    try {
      final service = UpdateService();
      final info = await service.checkForUpdate();
      if (info == null || !mounted) return;
      if (await service.isIgnored(info.versionCode)) return;
      if (!mounted) return;
      // 密码锁屏覆盖中（dialog 会盖到锁屏之上）；降级提示等弹窗正显示
      final locked = context.read<LockProvider>().locked;
      final homeRouteCurrent = ModalRoute.of(context)?.isCurrent ?? false;
      if (locked || !homeRouteCurrent) return;
      final result = await showUpdateDialog(context, info);
      // 用户选择先去备份：跳备份与恢复页，备份方式由用户在页内自选
      if (result == UpdateDialogResult.goBackup && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const BackupPage()),
        );
      }
    } catch (_) {
      // 自动检查保持静默；错误提示只在手动检查时出现
    }
  }

  /// 降级重建后的恢复引导：告知数据已留底、去哪恢复，弹一次即清除
  Future<void> _showDowngradeNotice() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kDowngradeDetectedKey) != true) return;
    await prefs.remove(kDowngradeDetectedKey);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数据已安全备份'),
        content: const Text(
          '检测到应用数据版本异常，您的账单数据已自动备份了一份。\n\n'
          '可在「我的 → 备份与恢复 → 历史备份」中查看与恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // watch：月份/查看模式切换（notifyListeners）时重建，
    // StreamBuilder 随之订阅新范围的流
    final provider = context.watch<BillProvider>();
    // 在 build 中取流：模式或月份变化时重建重新取，避免旧流订阅问题
    final billsStream = provider.homeBillsStream();
    return Column(
      children: [
        _SummaryHeader(provider: provider),
        Expanded(
          child: StreamBuilder<List<Bill>>(
            stream: billsStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<Map<int, Category>>(
                stream: context.read<CategoryProvider>().categoriesMapStream(),
                builder: (context, catSnapshot) {
                  final categories = catSnapshot.data ?? const {};
                  final bills = snapshot.data!;
                  if (bills.isEmpty) {
                    return const _EmptyState();
                  }
                  return _BillList(
                    bills: bills,
                    categories: categories,
                    showAll: provider.period == HomePeriod.all,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 顶部渐变汇总区：显示方式切换 + 支出 / 收入 / 结余
class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.provider});

  final BillProvider provider;

  /// 打开"显示方式"弹窗并应用选择结果（模式 + 基准月份）
  Future<void> _pickPeriod(BuildContext context) async {
    final result = await PeriodPickerDialog.show(
      context,
      initialMode: provider.period,
      initialMonth: provider.selectedMonth,
    );
    if (result == null || !context.mounted) return;
    final (mode, month) = result;
    if (month != null) provider.changeMonth(month);
    provider.changePeriod(mode);
  }

  @override
  Widget build(BuildContext context) {
    // 按查看模式决定顶栏标题与箭头行为：
    // 按月显示 yyyy年M月、按年显示 yyyy年、"全部"隐藏箭头
    final period = provider.period;
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pagePadding,
            AppDimens.gapSm,
            AppDimens.pagePadding,
            AppDimens.gapLg,
          ),
          child: StreamBuilder<MonthSummary>(
            stream: provider.homeSummaryStream(),
            builder: (context, snapshot) {
              final summary = snapshot.data ?? MonthSummary.empty;
              return Column(
                children: [
                  Center(
                    child: MonthSwitcher(
                      month: provider.selectedMonth,
                      onChanged: provider.changeMonth,
                      // 弹窗内已可选年月，顶部左右箭头不再需要
                      showArrows: false,
                      text: switch (period) {
                        HomePeriod.month => null,
                        HomePeriod.year => '${provider.selectedMonth.year}年',
                        HomePeriod.all => '全部',
                      },
                      onTapText: () => _pickPeriod(context),
                    ),
                  ),
                  const SizedBox(height: AppDimens.gapLg),
                  // 上行：流量（支出/收入），下行：结果（优惠节省/结余）
                  Row(
                    children: [
                      _SummaryItem(
                        label: '支出',
                        amount: MoneyUtil.centsToYuanTrimmed(
                          summary.expenseCents,
                        ),
                      ),
                      _divider(),
                      _SummaryItem(
                        label: '收入',
                        amount: MoneyUtil.centsToYuanTrimmed(
                          summary.incomeCents,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.gapMd),
                  // 两行之间贯通横线
                  Container(height: 1, color: AppColors.onHeader(0.2)),
                  const SizedBox(height: AppDimens.gapMd),
                  Row(
                    children: [
                      // 优惠节省是"正反馈"辅助指标：字号小一档、亮度略低，
                      // 避免与支出/收入/结余三个主指标抢视觉权重
                      _SummaryItem(
                        label: '优惠节省',
                        amount: MoneyUtil.centsToYuanTrimmed(
                          summary.discountCents,
                        ),
                        small: true,
                      ),
                      _divider(),
                      _SummaryItem(
                        label: '结余',
                        amount: MoneyUtil.centsToYuanTrimmed(
                          summary.balanceCents,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 汇总列之间的细分隔线
  Widget _divider() {
    return Container(width: 1, height: 26, color: AppColors.onHeader(0.25));
  }
}

/// 汇总单项
class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.amount,
    this.small = false,
  });

  final String label;
  final String amount;

  /// 辅助指标（优惠节省）：字号与亮度小一档
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              color: AppColors.onHeader(small ? 0.65 : 0.75),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: small ? 16 : 19,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: small ? 0.9 : 1),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 按日分组的账单卡片列表：每天一张白色圆角卡片
class _BillList extends StatefulWidget {
  const _BillList({
    required this.bills,
    required this.categories,
    this.showAll = false,
  });

  final List<Bill> bills;
  final Map<int, Category> categories;

  /// "全部"模式：尾部提示文案不带"本月"
  final bool showAll;

  @override
  State<_BillList> createState() => _BillListState();
}

class _BillListState extends State<_BillList> {
  /// billId → 标签列表缓存：bills 变化时批量加载一次
  Map<int, List<Tag>> _tagsByBill = {};

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void didUpdateWidget(covariant _BillList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 账单列表变化（切月/新增/编辑/删除）时重新批量加载标签
    if (oldWidget.bills != widget.bills) _loadTags();
  }

  Future<void> _loadTags() async {
    if (widget.bills.isEmpty) {
      setState(() => _tagsByBill = {});
      return;
    }
    final ids = widget.bills.map((b) => b.id).toList();
    final map = await context.read<TagRepository>().getTagsByBillIds(ids);
    if (!mounted) return;
    setState(() => _tagsByBill = map);
  }

  @override
  Widget build(BuildContext context) {
    // 先按日分组（数据已按日期倒序），再依序生成每日卡片
    final dayKeys = <String>[];
    final dayBillsMap = <String, List<Bill>>{};
    for (final bill in widget.bills) {
      final key = '${bill.date.year}-${bill.date.month}-${bill.date.day}';
      if (!dayBillsMap.containsKey(key)) {
        dayBillsMap[key] = [];
        dayKeys.add(key);
      }
      dayBillsMap[key]!.add(bill);
    }
    // 年份按需显示：列表数据跨年时分组头带年份消歧，同年内省略
    final crossYear = widget.bills.map((b) => b.date.year).toSet().length > 1;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        AppDimens.gapMd,
        AppDimens.pagePadding,
        24,
      ),
      itemCount: dayKeys.length + 1,
      itemBuilder: (context, index) {
        if (index == dayKeys.length) {
          // 列表尾部留白提示
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.gapLg),
            child: Center(
              child: Text(
                widget.showAll ? '· 全部账单到底啦 ·' : '· 本月账单到底啦 ·',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }
        final dayBills = dayBillsMap[dayKeys[index]]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppDimens.gapSection),
          child: _DayCard(
            date: dayBills.first.date,
            dayBills: dayBills,
            categories: widget.categories,
            tagsByBill: _tagsByBill,
            showYear: crossYear,
          ),
        );
      },
    );
  }
}

/// 单日卡片：日期头 + 当日账单条目
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.date,
    required this.dayBills,
    required this.categories,
    required this.tagsByBill,
    required this.showYear,
  });

  final DateTime date;
  final List<Bill> dayBills;
  final Map<int, Category> categories;

  /// billId → 标签列表（由 _BillList 批量加载后传入）
  final Map<int, List<Tag>> tagsByBill;

  /// 分组头是否带年份：列表数据跨年时为 true（年份按需消歧）
  final bool showYear;

  @override
  Widget build(BuildContext context) {
    final expenseCents = dayBills
        .where((b) => b.type == BillType.expense)
        .fold(0, (s, b) => s + b.amountCents);
    final incomeCents = dayBills
        .where((b) => b.type == BillType.income)
        .fold(0, (s, b) => s + b.amountCents);

    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _buildHeader(expenseCents, incomeCents),
          // 条目之间以左对齐分割线区分
          for (var i = 0; i < dayBills.length; i++) ...[
            if (i > 0) const Divider(indent: 68, endIndent: 16),
            _buildItem(context, dayBills[i]),
          ],
        ],
      ),
    );
  }

  /// 日期分组头：左侧点分日期 + 附加标签（近三天相对词/星期），
  /// 右侧当日收支小计。年份按需显示（数据跨年才带年份，见 DateLabelUtil）
  Widget _buildHeader(int expenseCents, int incomeCents) {
    final parts = <String>[
      if (expenseCents > 0) '支 ${MoneyUtil.centsToYuanTrimmed(expenseCents)}',
      if (incomeCents > 0) '收 ${MoneyUtil.centsToYuanTrimmed(incomeCents)}',
    ];
    return Padding(
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
    );
  }

  /// 单条账单（点击弹详情、长按删除）
  Widget _buildItem(BuildContext context, Bill bill) {
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
      onTap: () => showBillDetailSheet(
        context,
        bill: bill,
        categories: categories,
        // 详情里点分类：跳转到该分类的统计页
        onCategoryTap: (c) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StatsPage(initialCategory: c),
          ),
        ),
        // 详情里点标签：跳转到该标签筛选的统计页
        onTagTap: (tag) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StatsPage(initialTag: tag),
          ),
        ),
      ),
      onLongPress: () => _confirmDelete(context, bill),
    );
  }

  /// 长按删除，二次确认防误触
  Future<void> _confirmDelete(BuildContext context, Bill bill) async {
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
    if (confirmed == true && context.mounted) {
      await context.read<BillProvider>().deleteBill(bill.id);
    }
  }
}

/// 空状态引导
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.fill,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.savings_outlined,
              size: 44,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: AppDimens.gapLg),
          const Text(
            '这个月还没有记账',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '点击下方 + 记下第一笔吧',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
