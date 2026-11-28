import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/asset_repository.dart';
import '../../data/repositories/debt_note_repository.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/debt_note_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/asset_pick_sheet.dart';
import '../../widgets/category_tree_selector.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/section_card.dart';

/// 全屏页：给借条记一笔还款（借入）/ 收款（借出）
///
/// 借入方向支持把还款额拆出利息（利息生成带分类的支出账单进明细与
/// 统计，本金部分冲减借条余额并扣减关联账户）；借出方向收款整笔
/// 冲减借条余额并回笼关联账户。
/// 分类记忆：默认带出该借条最近一次使用的利息分类，选一次后续免选。
class RepaymentEditPage extends StatefulWidget {
  const RepaymentEditPage({super.key, required this.note});

  /// 还款归属的借条
  final DebtNote note;

  @override
  State<RepaymentEditPage> createState() => _RepaymentEditPageState();
}

class _RepaymentEditPageState extends State<RepaymentEditPage> {
  late final bool _isBorrowIn =
      widget.note.direction == DebtDirection.borrowIn;

  final TextEditingController _amount = TextEditingController();
  final TextEditingController _interest = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _repaidAt = DateTime.now();

  /// 利息支出分类（拆分利息时必选）；初始值带出历史分类
  int? _categoryId;

  /// 历史分类加载完成标记：加载完才渲染分类行，避免先显示"请选择"
  /// 后闪成历史分类
  bool _categoryLoaded = false;

  /// 全部支出分类（分类选择弹窗数据源 + 已选分类名回显）
  List<Category> _expenseCategories = [];

  /// 本次还款实际使用的账户：默认带出借条的关联账户（放款来源），
  /// 可改——放款的卡和还款的卡可以不同
  late int? _repayAssetId = widget.note.relatedAssetId;

  /// 活跃账户列表：编辑期间账户不会增删，只查一次后复用
  late final Future<List<Asset>> _activeAssets = context
      .read<AssetProvider>()
      .activeStream()
      .first;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 利息输入变化驱动"利息分类"行的显示/隐藏（FormInputRow 无
    // onChanged，走 controller 监听）
    _interest.addListener(_onInterestChanged);
    _loadLastCategory();
  }

  @override
  void dispose() {
    _amount.dispose();
    _interest.removeListener(_onInterestChanged);
    _interest.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onInterestChanged() {
    if (mounted) setState(() {});
  }

  /// 利息是否输入了有效值（> 0）：驱动"利息分类"行显示/隐藏
  bool get _hasInterestInput {
    final cents = MoneyUtil.yuanToCents(_interest.text.trim());
    return cents != null && cents > 0;
  }

  /// 分类记忆：带出该借条最近一次还款使用的利息分类
  Future<void> _loadLastCategory() async {
    final lastId = await context
        .read<DebtNoteProvider>()
        .latestRepaymentCategoryId(widget.note.id);
    if (mounted) {
      setState(() {
        _categoryId = lastId;
        _categoryLoaded = true;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repaidAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _repaidAt = picked);
  }

  /// 与记一笔同款兜底：无历史分类记忆时默认选中第一个一级分类，
  /// 保证进分类选择器时 selectedId 非空（single 模式断言要求）
  void _ensureDefaultCategory() {
    final fallback = defaultCategoryId(_expenseCategories);
    if (fallback != null && _categoryId == null) {
      setState(() => _categoryId = fallback);
    }
  }

  /// 利息分类选择弹窗：支出分类树单选
  Future<void> _pickCategory() async {
    if (_expenseCategories.isEmpty) return;
    _ensureDefaultCategory();
    final initialExpandedId = initialExpandedCategoryId(
      _expenseCategories,
      _categoryId,
    );
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    const Text(
                      '选择利息分类',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CategoryTreeSelector(
                  mode: CategoryTreeMode.single,
                  categories: _expenseCategories,
                  selectedId: _categoryId,
                  initialExpandedId: initialExpandedId,
                  onSingleChanged: (id) {
                    setState(() => _categoryId = id);
                    // 点二级 = 选中即收（快路径）；点一级 = 挂一级本身
                    // 并展开，弹窗保持打开供继续选二级，确认走"完成"
                    final isParent = _expenseCategories
                        .where((c) => c.id == id)
                        .firstOrNull
                        ?.parentId == null;
                    if (!isParent) {
                      Navigator.pop(sheetContext, id);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  /// 已选分类名回显
  String get _categoryName {
    final id = _categoryId;
    if (id == null) return '请选择';
    for (final c in _expenseCategories) {
      if (c.id == id) return c.name;
    }
    return '请选择';
  }

  /// 选择还款账户：统一账户选择面板（与记借条同风格，支持"不关联"
  /// = 纯台账不联动余额）
  Future<void> _pickRepayAsset() async {
    final assets = await _activeAssets;
    if (!mounted) return;
    final result = await showAssetPickSheet(
      context,
      assets: assets,
      allowNone: true,
    );
    // 下滑关闭等取消操作返回 null，保持原选择不变
    if (result == null || !mounted) return;
    setState(() => _repayAssetId = result.$1?.id);
  }

  /// 还款账户显示名：按 id 从账户流里查（查不到说明已归档/删除）
  Widget _repayAssetName() {
    return FutureBuilder<List<Asset>>(
      future: _activeAssets,
      builder: (context, snapshot) {
        final id = _repayAssetId;
        String text = '不关联';
        if (id != null) {
          final match = snapshot.data?.where((a) => a.id == id).toList();
          text = (match == null || match.isEmpty)
              ? '已删除的账户'
              : match.single.name;
        }
        return Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: id == null ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    // 本金与利息独立录入：amountCents 落库纯本金（余额冲减/剩余计算
    // 的直接口径），拆息时另生成利息支出账单进明细与统计
    final principal = MoneyUtil.yuanToCents(_amount.text.trim());
    if (principal == null || principal <= 0) {
      showAppToast(context, '请输入正确的本金');
      return;
    }
    var interest = _isBorrowIn
        ? MoneyUtil.yuanToCents(_interest.text.trim())
        : null;
    if (interest != null && interest <= 0) interest = null;
    if (interest != null) {
      if (_categoryId == null) {
        showAppToast(context, '请选择利息分类');
        return;
      }
    }
    // 还款日期不能早于借款日期（按自然日比较，借款当天还款合法）
    final borrowedDay = DateTime(
      widget.note.borrowedAt.year,
      widget.note.borrowedAt.month,
      widget.note.borrowedAt.day,
    );
    if (_repaidAt.isBefore(borrowedDay)) {
      showAppToast(context, '还款日期不能早于借款日期');
      return;
    }
    final text = _note.text.trim();
    setState(() => _saving = true);
    try {
      await context.read<DebtNoteProvider>().addRepayment(
        note: widget.note,
        amountCents: principal,
        repaidAt: _repaidAt,
        interestCents: interest,
        categoryId: interest != null ? _categoryId : null,
        repayAssetId: _repayAssetId,
        remark: text.isEmpty ? null : text,
      );
      if (mounted) Navigator.of(context).pop();
    } on RepaymentExceedsException {
      if (mounted) showAppToast(context, '还款金额超过借条剩余欠款');
      return;
    } on InsufficientBalanceException catch (e) {
      if (mounted) showAppToast(context, e.toString());
      return;
    } catch (e) {
      if (mounted) showAppToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    return Scaffold(
      appBar: AppBar(title: Text(_isBorrowIn ? '记还款' : '记收款')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusControl),
              ),
            ),
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ),
      ),
      body: StreamBuilder<List<Category>>(
        stream: context.read<CategoryProvider>().categoriesStream(
          BillType.expense,
        ),
        builder: (context, snapshot) {
          _expenseCategories = snapshot.data ?? const [];
          // 分类列表到达且无记忆分类时，进帧后自动兜底选第一个一级，
          // 分类行直接显示默认分类（与记一笔同款，不再显示"请选择"）
          if (_categoryLoaded &&
              _categoryId == null &&
              _expenseCategories.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _categoryId != null) return;
              _ensureDefaultCategory();
            });
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              AppDimens.gapSection,
              16,
              24,
            ),
            children: [
              SectionCard(
                padding: const EdgeInsets.all(AppDimens.gapMd),
                child: Text(
                  _isBorrowIn
                      ? '还 ${widget.note.personName} 的欠款'
                      : '${widget.note.personName} 的还款',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.gapMd),
              // 金额卡：本金 + 利息拆分（仅借入方向提供，还银行分期等
              // 场景）同卡；拆出的利息生成带分类的支出账单进明细与统计，
              // 本金部分冲减借条余额
              FormRowsCard(
                rows: [
                  FormInputRow(
                    label: '本金',
                    controller: _amount,
                    hint: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: MoneyUtil.amountInputFormatters,
                    suffix: 'CNY',
                    textInputAction: TextInputAction.next,
                  ),
                  if (_isBorrowIn) ...[
                    FormInputRow(
                      label: '利息',
                      controller: _interest,
                      hint: '选填，拆出后计入支出统计',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: MoneyUtil.amountInputFormatters,
                      suffix: 'CNY',
                    ),
                    // 分类行联动显示：利息输入有效值后才出现，不拆息
                    // 不打扰；出现前已兜底选中第一个一级分类
                    if (_hasInterestInput && _categoryLoaded)
                      FormRow(
                        label: '利息分类',
                        onTap: _pickCategory,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _categoryName,
                              style: TextStyle(
                                fontSize: 15,
                                color: _categoryId == null
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 22,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: AppDimens.gapMd),
              FormRowsCard(
                rows: [
                  // 还款账户：默认带出借条关联账户，可改（放款与还款
                  // 的卡可以不同）；本金与利息的余额联动都按这笔的
                  // 落库账户走
                  FormRow(
                    label: _isBorrowIn ? '还款账户' : '收款账户',
                    onTap: _pickRepayAsset,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _repayAssetName(),
                        const Icon(
                          Icons.chevron_right,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  FormRow(
                    label: _isBorrowIn ? '还款日期' : '收款日期',
                    onTap: _pickDate,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          df.format(_repaidAt),
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  FormInputRow(
                    label: '备注',
                    controller: _note,
                    hint: '选填',
                    maxLength: 50,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
