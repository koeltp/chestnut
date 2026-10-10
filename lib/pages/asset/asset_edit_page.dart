import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/asset_category.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/asset_circle_icon.dart';
import '../../widgets/day_picker_dialog.dart';
import '../../widgets/form_rows.dart';
import 'asset_category_sheet.dart';
import 'bank_picker_sheet.dart';
import 'debt_note_edit_page.dart';

/// 全屏页：添加 / 编辑资产（钱迹式动态表单）
///
/// [category] 为初始分类（新增流程由分类选择弹窗选定）；
/// [existing] 非 null = 编辑态：分类切换限定同 kind 的组（防止改类型
/// 让历史快照的正负语义翻转，净值曲线出现断层）。
/// 表单字段随分类动态变化：信用卡账户组显示总额度/出账日/还款日，
/// 其中"信用卡"分类额外提供银行选择。
Future<void> pushAssetEditPage(
  BuildContext context, {
  required AssetCategoryDef category,
  Asset? existing,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _AssetEditPage(category: category, existing: existing),
    ),
  );
}

/// 分类选中后的统一分流（添加流程的两个 + 入口共用）：
/// 借出/借入是借条入口而非资产分类——不建账户，预选方向进借条
/// 编辑页，保存后主界面的总借出/借入卡才出现；其余进资产编辑表单
Future<void> handleAssetCategoryPicked(
  BuildContext context,
  AssetCategoryDef def,
) {
  final direction = switch (def.name) {
    '借出' => DebtDirection.lendOut,
    '借入' => DebtDirection.borrowIn,
    _ => null,
  };
  if (direction == null) return pushAssetEditPage(context, category: def);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DebtNoteEditPage(initialDirection: direction),
    ),
  );
}

class _AssetEditPage extends StatefulWidget {
  const _AssetEditPage({required this.category, this.existing});

  final AssetCategoryDef category;
  final Asset? existing;

  @override
  State<_AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends State<_AssetEditPage> {
  late AssetCategoryDef _category = widget.existing != null
      ? AssetGroups.categoryOf(widget.existing!.category) ?? widget.category
      : widget.category;

  /// 名称默认值 = 分类名（"信用卡"分类在选完银行后为银行名）。
  /// 切换分类时：名称为空或等于旧默认值则跟随新默认，用户改过则保留
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name,
  );
  late final TextEditingController _value = TextEditingController(
    text: widget.existing == null
        ? ''
        : MoneyUtil.centsToYuanTrimmed(widget.existing!.valueCents),
  );
  late final TextEditingController _creditLimit = TextEditingController(
    text: widget.existing?.creditLimitCents == null
        ? ''
        : MoneyUtil.centsToYuanTrimmed(widget.existing!.creditLimitCents!),
  );

  /// 出账日/还款日（1~31，null = 未填）：点行弹日历选择
  late int? _billDay = widget.existing?.billDay;
  late int? _repayDay = widget.existing?.repayDay;
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note,
  );
  late bool _includeInNet = widget.existing?.includeInNet ?? true;

  /// 已选发卡银行（仅"信用卡"分类有值；编辑态回显为账户名）
  late String? _bank = _isCreditCardCategory && _editing
      ? widget.existing!.name
      : null;

  bool _saving = false;

  bool get _editing => widget.existing != null;

  /// 当前分类所属组（kind 与动态字段都由它决定）
  AssetGroupDef get _group => AssetGroups.groupOf(_category.name);

  bool get _isCreditGroup => _group == AssetGroups.credit;

  bool get _isCreditCardCategory => _category.name == '信用卡';

  /// 当前名称是否等于"默认名"（分类名/银行名），用于切换分类时
  /// 判断是否跟随更新——用户起过名字则不打扰
  bool _nameIsDefault() {
    final text = _name.text.trim();
    return text.isEmpty || text == _category.name;
  }

  /// 金额输入行标签：负债叫欠款、大件资产叫市值、其余叫余额
  String get _valueLabel => switch (_group.kind) {
    AssetKind.liability => '欠款（元）',
    _ => _group == AssetGroups.otherAsset ? '市值（元）' : '余额（元）',
  };

  /// 切换分类：编辑态只允许同 kind 的组（见类注释）；
  /// 选中"信用卡"分类时联动选银行，名称默认跟随
  Future<void> _pickCategory() async {
    final groups = _editing
        ? AssetGroups.all.where((g) => g.kind == _group.kind).toList()
        : null;
    final def = await showAssetCategorySheet(context, groups: groups);
    if (def == null || !mounted) return;
    setState(() {
      _category = def;
      if (_nameIsDefault()) _name.text = def.name;
    });
    if (def.name == '信用卡') await _pickBank();
  }

  /// 选择发卡银行：选完填入名称（名称为空或等于默认值时跟随）
  Future<void> _pickBank() async {
    final bank = await showBankPickerSheet(context);
    if (bank == null || !mounted) return;
    setState(() {
      _bank = bank;
      if (_nameIsDefault()) _name.text = bank;
    });
  }

  /// 备注的统一空串归一：与数据库 nullable 口径一致（空串存 null）
  String? get _noteText {
    final text = _note.text.trim();
    return text.isEmpty ? null : text;
  }

  /// 弹「每月几号」网格选日（1~31）：取消 / 关闭返回 null 不改值
  Future<void> _pickDay({required bool isBillDay}) async {
    final current = isBillDay ? _billDay : _repayDay;
    final picked = await showDayPickerDialog(context, initialDay: current);
    if (picked == null || !mounted) return;
    setState(() {
      if (isBillDay) {
        _billDay = picked;
      } else {
        _repayDay = picked;
      }
    });
  }

  /// 出账日/还款日行的显示文案：已选显示"每月 X 日"，未选显示占位
  String _dayText(int? day) =>
      day == null ? '选填，点此选择' : '每月 $day 日';

  /// 出账日/还款日行尾图标：已选显示 ×（点清除），未选显示 >；
  /// 两者同为 22×22 盒子，切换时位置不跳
  Widget _dayTrailing({required bool isBillDay}) {
    final day = isBillDay ? _billDay : _repayDay;
    if (day == null) {
      return const Icon(
        Icons.chevron_right,
        size: 22,
        color: AppColors.textSecondary,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (isBillDay) {
          _billDay = null;
        } else {
          _repayDay = null;
        }
      }),
      child: const SizedBox(
        width: 22,
        height: 22,
        child: Icon(Icons.close, size: 22, color: AppColors.textSecondary),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final cents = MoneyUtil.yuanToCents(_value.text.trim());
    if (name.isEmpty) {
      showAppToast(context, '请填写资产名称');
      return;
    }
    // 金额允许 0：新建空账户 / 未使用的信用卡（欠款 0）都是合法状态
    if (cents == null || cents < 0) {
      showAppToast(context, '请输入正确的金额');
      return;
    }
    final billDay = _isCreditGroup ? _billDay : null;
    final repayDay = _isCreditGroup ? _repayDay : null;
    final creditLimit = _isCreditGroup
        ? MoneyUtil.yuanToCents(_creditLimit.text.trim())
        : null;
    if (_isCreditGroup &&
        _creditLimit.text.trim().isNotEmpty &&
        creditLimit == null) {
      showAppToast(context, '请输入正确的总额度');
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<AssetProvider>();
      final existing = widget.existing;
      if (existing == null) {
        await provider.addAsset(
          name: name,
          kind: _group.kind,
          category: _category.name,
          valueCents: cents,
          note: _noteText,
          includeInNet: _includeInNet,
          creditLimitCents: creditLimit,
          billDay: billDay,
          repayDay: repayDay,
        );
      } else {
        // 市值变化单独走 updateValue：落快照供净值曲线使用
        if (cents != existing.valueCents) {
          await provider.updateValue(existing, cents);
        }
        final infoChanged =
            name != existing.name ||
            _category.name != existing.category ||
            _noteText != existing.note ||
            _includeInNet != existing.includeInNet ||
            creditLimit != existing.creditLimitCents ||
            billDay != existing.billDay ||
            repayDay != existing.repayDay;
        if (infoChanged) {
          await provider.updateInfo(
            existing,
            name: name,
            category: _category.name,
            note: _noteText,
            includeInNet: _includeInNet,
            creditLimitCents: creditLimit,
            billDay: billDay,
            repayDay: repayDay,
          );
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive() async {
    final existing = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档资产'),
        content: Text('归档后「${existing.name}」不再计入净值，历史快照保留，可随时恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<AssetProvider>().setArchived(existing, archived: true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 顶栏标题带分类名（钱迹式，如"添加支付宝"）
      appBar: AppBar(
        title: Text(_editing ? '编辑${_category.name}' : '添加${_category.name}'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              // 归档仅编辑态提供：新增场景无"归档"语义
              if (_editing) ...[
                TextButton(
                  onPressed: _saving ? null : _archive,
                  child: const Text(
                    '归档',
                    style: TextStyle(color: AppColors.expense),
                  ),
                ),
                const SizedBox(width: AppDimens.gapMd),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusControl,
                      ),
                    ),
                  ),
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, AppDimens.gapSection, 16, 24),
        children: [
          // 基本信息：账户类型 / 名称 / 金额（信用卡组追加动态字段）
          FormRowsCard(rows: [
            // 账户类型行：点击换分类（编辑态限定同 kind 组）
            FormRow(
              label: '账户类型',
              onTap: _pickCategory,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      '${_group.name} · ${_category.name}',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.gapSm),
                  AssetCircleIcon(category: _category.name),
                  const Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            FormInputRow(
              label: '资产名称',
              controller: _name,
              hint: _category.name,
              maxLength: 20,
              textInputAction: TextInputAction.next,
            ),
            FormInputRow(
              label: _valueLabel,
              controller: _value,
              hint: '0.00',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // 最多两位小数：金额按分入库，防输入超精度小数
              inputFormatters: MoneyUtil.amountInputFormatters,
              textInputAction: TextInputAction.next,
            ),
            // "信用卡"分类额外提供银行选择
            if (_isCreditCardCategory)
              FormRow(
                label: '所属银行',
                onTap: _pickBank,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _bank ?? '请选择银行',
                      style: TextStyle(
                        fontSize: 15,
                        color: _bank == null
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
            if (_isCreditGroup) ...[
              FormInputRow(
                label: '总额度（元）',
                controller: _creditLimit,
                hint: '选填，如 50000',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: MoneyUtil.amountInputFormatters,
                textInputAction: TextInputAction.next,
              ),
              FormRow(
                label: '出账日',
                onTap: () => _pickDay(isBillDay: true),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _dayText(_billDay),
                      style: TextStyle(
                        fontSize: 15,
                        color: _billDay == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    _dayTrailing(isBillDay: true),
                  ],
                ),
              ),
              FormRow(
                label: '还款日',
                onTap: () => _pickDay(isBillDay: false),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _dayText(_repayDay),
                      style: TextStyle(
                        fontSize: 15,
                        color: _repayDay == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    _dayTrailing(isBillDay: false),
                  ],
                ),
              ),
            ],
          ]),
          const SizedBox(height: AppDimens.gapMd),
          // 计入总资产开关：关闭后仅展示，不参与净值/占比统计
          FormRowsCard(rows: [
            FormSwitchRow(
              label: '计入总资产',
              subtitle: '关闭后仅在列表展示，不参与净值统计',
              value: _includeInNet,
              onChanged: (v) => setState(() => _includeInNet = v),
            ),
          ]),
          const SizedBox(height: AppDimens.gapMd),
          // 备注独立一张卡
          FormRowsCard(rows: [
            FormInputRow(label: '备注', controller: _note, hint: '选填', maxLength: 50),
          ]),
        ],
      ),
    );
  }
}
