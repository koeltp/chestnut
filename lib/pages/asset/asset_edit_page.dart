import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/asset_category.dart';
import '../../models/enums.dart';
import '../../models/institutions.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/asset_circle_icon.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/day_picker_dialog.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/institution_logo.dart';
import 'asset_category_sheet.dart';
import 'asset_delete.dart';
import 'asset_edit_form_rows.dart';
import 'institution_picker_sheet.dart';
import 'debt_note_edit_page.dart';

/// 全屏页：添加 / 编辑资产（钱迹式动态表单）
///
/// [category] 为初始分类（新增流程由分类选择弹窗选定）；
/// [initialInstitution] 为新增流程中先选好的所属机构（卡类的银行、
/// 投资组的券商/平台）；
/// [existing] 非 null = 编辑态：分类切换限定同 kind 的组（防止改类型
/// 让历史快照的正负语义翻转，净值曲线出现断层）。
/// 表单字段随分类动态变化：信用卡账户组显示总额度/出账日/还款日，
/// "信用卡"/"银行卡"分类提供所属银行选择、投资理财组提供券商/平台
/// 选择（统称所属机构，独立存储，改名不影响机构）。
/// 返回 true = 资产已被彻底删除（详情页等上层据此一并退出，避免
/// 停留在已删除资产的页面上）
Future<bool?> pushAssetEditPage(
  BuildContext context, {
  required AssetCategoryDef category,
  Asset? existing,
  String? initialInstitution,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => _AssetEditPage(
        category: category,
        existing: existing,
        initialInstitution: initialInstitution,
      ),
    ),
  );
}

/// 分类选中后的统一分流（添加流程的两个 + 入口共用）：
/// 借出/借入是借条入口而非资产分类——不建账户，预选方向进借条
/// 编辑页，保存后主界面的总借出/借入卡才出现；其余进资产编辑表单。
/// [institution] 为卡类/投资组分类预先选好的所属机构（用户在机构弹层取消则为 null）
Future<void> handleAssetCategoryPicked(
  BuildContext context,
  AssetCategoryDef def, {
  String? institution,
}) {
  final direction = switch (def.name) {
    '借出' => DebtDirection.lendOut,
    '借入' => DebtDirection.borrowIn,
    _ => null,
  };
  if (direction == null) {
    return pushAssetEditPage(
      context,
      category: def,
      initialInstitution: institution,
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DebtNoteEditPage(initialDirection: direction),
    ),
  );
}

class _AssetEditPage extends StatefulWidget {
  const _AssetEditPage({
    required this.category,
    this.existing,
    this.initialInstitution,
  });

  final AssetCategoryDef category;
  final Asset? existing;

  /// 新增流程预选的所属银行
  final String? initialInstitution;

  @override
  State<_AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends State<_AssetEditPage> {
  late AssetCategoryDef _category = widget.existing != null
      ? AssetGroups.categoryOf(widget.existing!.category) ?? widget.category
      : widget.category;

  /// 名称默认值 = 分类名（卡类选完银行后为银行名）。
  /// 新增时直接预填分类名（钱迹式，用户可改）；
  /// 切换分类时：名称为空或等于旧默认值则跟随新默认，用户改过则保留
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ??
        widget.initialInstitution ??
        widget.category.name,
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

  /// 已选所属机构：编辑态取独立 institution 列（与名称互不影响），
  /// 新增态取主流程预选结果
  late String? _institution =
      _editing ? widget.existing!.institution : widget.initialInstitution;

  bool _saving = false;

  bool get _editing => widget.existing != null;

  /// 当前分类所属组（kind 与动态字段都由它决定）
  AssetGroupDef get _group => AssetGroups.groupOf(_category.name);

  bool get _isCreditGroup => _group == AssetGroups.credit;

  /// 是否编辑已归档资产：底部操作区据此切换归档/恢复/删除
  bool get _isArchived => widget.existing?.archived ?? false;

  /// 当前分类是否显示"所属机构"选择：
  /// 信用卡与储蓄卡有发卡行，投资理财组有券商/平台
  bool get _showInstitutionPicker =>
      _category.name == '信用卡' ||
      _category.name == '银行卡' ||
      AssetGroups.investCategories.contains(_category.name);

  /// 当前名称是否等于"默认名"（分类名或当前机构名），用于切换分类/机构时
  /// 判断是否跟随更新——用户起过名字则不打扰
  bool _nameIsDefault() {
    final text = _name.text.trim();
    return text.isEmpty ||
        text == _category.name ||
        (_institution != null && text == _institution);
  }

  /// 金额输入行标签：负债叫欠款、其余叫余额；
  /// 单位不再写进 label，由行尾 CNY 后缀表达币种
  String get _valueLabel => switch (_group.kind) {
    AssetKind.liability => '欠款',
    _ => '余额',
  };

  /// 切换分类：编辑态只允许同 kind 的组（见类注释）；
  /// 名称无条件跟随新分类（用户要求切换即改名），选中"信用卡"/
  /// "银行卡"或投资理财组分类时联动弹机构层（卡类只看银行组，
  /// 投资组隐藏银行组），机构名随后覆盖分类名；
  /// 切到不显示机构行的分类时清掉机构（落库 institution 恒为 null）
  Future<void> _pickCategory() async {
    final groups = _editing
        ? AssetGroups.all.where((g) => g.kind == _group.kind).toList()
        : null;
    final def = await showAssetCategorySheet(context, groups: groups);
    if (def == null || !mounted) return;
    final isCard = def.name == '信用卡' || def.name == '银行卡';
    final isInvest = AssetGroups.investCategories.contains(def.name);
    setState(() {
      _category = def;
      _name.text = def.name;
      if (!isCard && !isInvest) {
        _institution = null;
      }
    });
    if (isCard || isInvest) await _pickInstitution();
  }

  /// 机构弹层显示的分组：卡类只看银行组，投资组隐藏银行组（券商/平台/
  /// 其他机构跨组可选，券商组排最前天然即首屏）
  Set<String> get _institutionSections =>
      _category.name == '信用卡' || _category.name == '银行卡'
          ? kBankSectionFilter
          : kInvestSectionFilter;

  /// 选择所属机构：选完更新独立 institution 字段；
  /// 名称为空或仍是默认名（分类名/旧机构名）时跟随填入新机构名
  Future<void> _pickInstitution() async {
    final institution = await showInstitutionPickerSheet(
      context,
      sections: _institutionSections,
    );
    if (institution == null || !mounted) return;
    setState(() {
      _institution = institution;
      if (_nameIsDefault()) _name.text = institution;
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
    // 非机构类分类恒不落机构（切分类残留值在这里收口）
    final institution = _showInstitutionPicker ? _institution : null;
    // 总额度必填：额度是信用卡额度使用率/负债统计的基数，缺了没法算
    if (_isCreditGroup && creditLimit == null) {
      showAppToast(context, '请填写总额度');
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
          institution: institution,
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
            repayDay != existing.repayDay ||
            institution != existing.institution;
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
            institution: institution,
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
    final confirmed = await showConfirmDialog(
      context,
      title: '归档资产',
      content: '归档后「${existing.name}」不再计入净值，历史快照保留，可随时恢复。',
      confirmText: '归档',
    );
    if (!confirmed) return;
    if (!mounted) return;
    await context.read<AssetProvider>().setArchived(existing, archived: true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 取消归档（已归档资产进编辑页时的「归档」按钮变恢复语义）
  Future<void> _unarchive() async {
    await context
        .read<AssetProvider>()
        .setArchived(widget.existing!, archived: false);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 彻底删除（仅已归档资产在编辑页暴露）：确认删除后 pop(true)
  /// 通知详情页一并退出
  Future<void> _delete() async {
    final deleted = await confirmDeleteAsset(context, widget.existing!);
    if (deleted && mounted) Navigator.of(context).pop(true);
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
              // 归档仅编辑态提供：新增场景无"归档"语义。
              // 已归档资产：按钮变「取消归档」，并额外暴露红色「删除」
              if (_editing) ...[
                TextButton(
                  onPressed: _saving
                      ? null
                      : (_isArchived ? _unarchive : _archive),
                  child: Text(
                    _isArchived ? '取消归档' : '归档',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                if (_isArchived) ...[
                  const SizedBox(width: AppDimens.gapMd),
                  TextButton(
                    onPressed: _saving ? null : _delete,
                    child: const Text(
                      '删除',
                      style: TextStyle(color: AppColors.expense),
                    ),
                  ),
                ],
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
            // 账户类型行（钱迹式）：所属机构并进本行展示——选了机构的
            // 分类显示机构名 + logo（如"招商银行"），机构吸收分类身份；
            // 无机构分类显示分类名 + 分类图标。点击换分类，选中带机构的
            // 分类后联动弹机构选择层
            FormRow(
              label: '账户类型',
              onTap: _pickCategory,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _showInstitutionPicker && institutionHasLogo(_institution)
                      ? InstitutionLogo(name: _institution!, size: 32)
                      : AssetCircleIcon(category: _category.name, size: 32),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _showInstitutionPicker && _institution != null
                          ? _institution!
                          : _category.name,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
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
              inputFormatters: MoneyUtil.amountInputFormatters,
              textInputAction: TextInputAction.next,
              suffix: 'CNY',
            ),
            if (_isCreditGroup) ...[
              FormInputRow(
                label: '总额度',
                controller: _creditLimit,
                hint: '如 50000',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: MoneyUtil.amountInputFormatters,
                textInputAction: TextInputAction.next,
                suffix: 'CNY',
              ),
              AssetDayRow(
                label: '出账日',
                day: _billDay,
                onPick: () => _pickDay(isBillDay: true),
                onClear: () => setState(() => _billDay = null),
              ),
              AssetDayRow(
                label: '还款日',
                day: _repayDay,
                onPick: () => _pickDay(isBillDay: false),
                onClear: () => setState(() => _repayDay = null),
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
