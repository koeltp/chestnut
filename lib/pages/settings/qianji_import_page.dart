import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../services/qianji_import_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/category_tree_selector.dart';
import '../../widgets/section_card.dart';
import 'qianji_import_result_page.dart';

/// 钱迹账单导入映射页
///
/// 流程：解析 xlsx → 按 (类型, 一级, 二级) 分组 → 用户逐组指定目标分类
/// （未指定的走同名自动归级，再落"其他"）→ 强确认 → 导入前留底 →
/// 整批写入（带批次号，结果页可整批撤销）。
class QianjiImportPage extends StatefulWidget {
  const QianjiImportPage({super.key, required this.filePath});

  /// 钱迹导出的 xlsx 文件路径（备份页文件选择器取得）
  final String filePath;

  @override
  State<QianjiImportPage> createState() => _QianjiImportPageState();
}

class _QianjiImportPageState extends State<QianjiImportPage> {
  bool _loading = true;
  String? _error;

  String _fileName = '';
  QianjiParseResult? _parsed;
  List<Category> _categories = [];
  List<QianjiGroup> _groups = [];

  /// 用户手动指定的映射：分组键 -> 目标分类 id；未指定的组走自动归级
  final Map<String, int> _manual = {};

  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 解析文件并构建映射分组（解析与查分类并行，任一失败进入错误态）
  ///
  /// xlsx 解析走 compute 扔到独立 isolate，避免大文件阻塞 UI 线程，
  /// 页面在 push 进来后立刻展示转圈，解析完再渲染。
  Future<void> _load() async {
    try {
      final db = context.read<AppDatabase>();
      final categories = await db.select(db.categories).get();
      categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      // 解析在 isolate 中执行，不卡 UI 线程
      final parsed = await compute(QianjiImportService.parseFile, widget.filePath);

      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _categories = categories;
        _groups = QianjiImportService.buildGroups(parsed.bills, categories);
        _fileName = widget.filePath.replaceAll('\\', '/').split('/').last;
        _loading = false;
      });
    } on QianjiImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '解析失败：$e';
        _loading = false;
      });
    }
  }

  // ---------------- 统计 ----------------

  int get _unsupportedCount {
    final parsed = _parsed;
    if (parsed == null) return 0;
    return parsed.unsupportedByType.values.fold(0, (s, n) => s + n);
  }

  /// 未手动映射且自动归级未命中的笔数（将落入"其他"）
  int get _fallbackCount => _groups
      .where((g) => !_manual.containsKey(g.key) && g.autoMatch == null)
      .fold(0, (s, g) => s + g.count);

  Category? _categoryById(int? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 映射目标显示名："餐饮" 或 "日常/理发"
  String _targetLabel(Category c) {
    if (c.parentId == null) return c.name;
    for (final p in _categories) {
      if (p.id == c.parentId) return '${p.name}/${c.name}';
    }
    return c.name;
  }

  String _groupLabel(QianjiGroup g) =>
      g.cat2.isEmpty ? g.cat1 : '${g.cat1}/${g.cat2}';

  // ---------------- 交互 ----------------

  Future<void> _pickTarget(QianjiGroup group) async {
    final current = _categoryById(_manual[group.key]) ?? group.autoMatch;
    final cats = _categories.where((c) => c.type == group.type).toList();
    int? pickedId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        // 弹层本地状态（StatefulBuilder 重建时保持）：
        // localId 当前高亮项；expandedRootId 当前展开的一级。
        // 有子类的一级第一次点 = 只展开+高亮，再点一次才选用——
        // 不能一点就关弹层，否则用户来不及选二级
        int localId = current?.id ?? -1;
        int? expandedRootId = current?.parentId ?? current?.id;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppDimens.radiusCard),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        '${_groupLabel(group)} · ${group.count} 笔',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '点分类直接选用；有子分类的一级会先展开，再点一次只选用一级',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 组件单选形态内部是 ListView 自滚动，外层不能再套
                    // SingleChildScrollView（无界高度会直接布局崩溃）
                    Flexible(
                      child: Padding(
                        // 内部格子自带 12 横向边距，补 4 与上方标题 16 对齐
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: CategoryTreeSelector(
                          categories: cats,
                          mode: CategoryTreeMode.single,
                          // 无命中时传无效 id -1，组件不高亮任何项
                          selectedId: localId,
                          initialExpandedId: expandedRootId,
                          onSingleChanged: (id) {
                            final cat = cats.firstWhere((c) => c.id == id);
                            final hasSubs = cats.any((c) => c.parentId == id);
                            if (cat.parentId == null &&
                                hasSubs &&
                                expandedRootId != id) {
                              // 有子类的一级首次点击：只展开+高亮
                              setSheetState(() {
                                localId = id;
                                expandedRootId = id;
                              });
                            } else {
                              // 再点已展开一级 / 无子类一级 / 二级：选用并关闭
                              pickedId = id;
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (pickedId == null || !mounted) return;
    setState(() => _manual[group.key] = pickedId!);
  }

  Future<void> _confirmImport() async {
    // async 弹窗前先取好 db，避免跨 async 使用 BuildContext
    final db = context.read<AppDatabase>();
    final fallback = _fallbackCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入钱迹账单'),
        content: Text(
          '将向当前数据追加 ${_parsed!.bills.length} 笔账单'
          '${fallback > 0 ? '，其中 $fallback 笔未匹配分类将计入「其他」' : ''}。\n\n'
          '· 导入前会自动把当前数据备份一份\n'
          '· 导入完成后可立即整批撤销',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _importing = true);
    try {
      await QianjiImportService.backupBeforeImport();
      final result = await QianjiImportService.importBills(
        db,
        groups: _groups,
        manualTargets: _manual,
        unsupportedCount: _unsupportedCount,
        badCount: _parsed!.badCount,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => QianjiImportResultPage(result: result),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '导入失败：$e');
      setState(() => _importing = false);
    }
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(centerTitle: true, title: const Text('导入钱迹账单')),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: AppDimens.gapMd),
                  Text(
                    '正在解析账单文件…',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.pagePadding * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppDimens.gapMd),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.gapLg),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final parsed = _parsed!;
    final expenseGroups = _groups
        .where((g) => g.type == BillType.expense)
        .toList(growable: false);
    final incomeGroups = _groups
        .where((g) => g.type == BillType.income)
        .toList(growable: false);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSection,
              AppDimens.pagePadding,
              24,
            ),
            children: [
              _buildSummaryCard(parsed),
              if (expenseGroups.isNotEmpty) ...[
                const SizedBox(height: AppDimens.gapSection),
                _buildGroupCard('支出分类映射', expenseGroups),
              ],
              if (incomeGroups.isNotEmpty) ...[
                const SizedBox(height: AppDimens.gapSection),
                _buildGroupCard('收入分类映射', incomeGroups),
              ],
              if (parsed.unsupportedByType.isNotEmpty) ...[
                const SizedBox(height: AppDimens.gapSection),
                _buildUnsupportedCard(parsed.unsupportedByType),
              ],
              const SizedBox(height: AppDimens.gapSection),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '点按分组选择目标分类；未选择的分组按同名分类自动匹配，'
                  '匹配不到的计入「其他」。原分类与来源信息会写入账单备注。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  /// 顶部概览卡：文件名与可导入笔数
  Widget _buildSummaryCard(QianjiParseResult parsed) {
    final expense = parsed.bills
        .where((b) => b.type == BillType.expense)
        .fold(0, (s, b) => s + b.amountCents);
    final income = parsed.bills
        .where((b) => b.type == BillType.income)
        .fold(0, (s, b) => s + b.amountCents);
    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '共 ${parsed.bills.length} 笔可导入：'
              '支出 ${MoneyUtil.centsToYuanGroupedTrimmed(expense)} 元 · '
              '收入 ${MoneyUtil.centsToYuanGroupedTrimmed(income)} 元',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 映射分组卡：每行一个 (类型, 一级, 二级) 组合
  Widget _buildGroupCard(String title, List<QianjiGroup> groups) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          for (final (i, group) in groups.indexed) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            _groupTile(group),
          ],
        ],
      ),
    );
  }

  Widget _groupTile(QianjiGroup group) {
    final manualId = _manual[group.key];
    final manual = _categoryById(manualId);
    final auto = group.autoMatch;
    final String stateText;
    final Color stateColor;
    if (manual != null) {
      stateText = '已选：${_targetLabel(manual)}';
      stateColor = AppColors.primary;
    } else if (auto != null) {
      stateText = '自动：${_targetLabel(auto)}';
      stateColor = AppColors.textSecondary;
    } else {
      stateText = '落其他';
      stateColor = AppColors.textSecondary;
    }
    return InkWell(
      onTap: _importing ? null : () => _pickTarget(group),
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
          vertical: 12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _groupLabel(group),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.count} 笔 · '
                    '${MoneyUtil.centsToYuanGroupedTrimmed(group.totalCents)} 元',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              stateText,
              style: TextStyle(fontSize: 13, color: stateColor),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 不支持类型说明卡：退款/转账等本应用没有的概念，列明后跳过
  Widget _buildUnsupportedCard(Map<String, int> unsupported) {
    final entries = unsupported.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: AppColors.warning),
                SizedBox(width: 8),
                Text(
                  '以下类型暂不支持导入',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entries.map((e) => '${e.key} ${e.value} 笔').join('、'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部统计与确认栏
  Widget _buildBottomBar() {
    final total = _parsed?.bills.length ?? 0;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        12,
        AppDimens.pagePadding,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '预计导入 $total 笔',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (_fallbackCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '其中 $_fallbackCount 笔将计入「其他」',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: _importing ? null : _confirmImport,
            child: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('确认导入'),
          ),
        ],
      ),
    );
  }
}
