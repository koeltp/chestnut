import 'package:flutter/material.dart';

import '../../models/institutions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bottom_sheet_scaffold.dart';
import '../../widgets/institution_logo.dart';

/// 底部弹窗：选择所属机构（银行 / 券商 / 基金理财平台等，钱迹式）
///
/// 名单按 [kInstitutionSections] 分段展示，支持关键词过滤（有关键词时
/// 跨组扁平匹配）。[sections] 限定展示的分组（元素为组标签，null = 全部）：
/// 卡类传 [kBankSectionFilter] 只看银行，投资组传 [kInvestSectionFilter]
/// 隐藏银行组。返回选中的机构名（如"招商银行"）；关闭返回 null。
/// 行首图标：机构配置了 svg 品牌 logo 则显示 logo，否则回落为
/// 首字圆形标（取行首两字更辨识，如"招行"），配色按机构名稳定取色。
/// 组件见 [InstitutionLogo]。
Future<String?> showInstitutionPickerSheet(
  BuildContext context, {
  Set<String>? sections,
}) {
  return showBottomSheetScaffold<String>(
    context: context,
    title: '选择所属机构',
    builder: (_) => _InstitutionPickerSheet(sections: sections),
  );
}

/// 弹层列表行：段头或机构条目
sealed class _SheetRow {
  const _SheetRow();
}

/// 段头行：分组标题，或长组内按拼音首字母分段的字母
class _HeaderRow extends _SheetRow {
  _HeaderRow(this.label);

  final String label;
}

/// 机构条目行
class _ItemRow extends _SheetRow {
  _ItemRow(this.def);

  final InstitutionDef def;
}

class _InstitutionPickerSheet extends StatefulWidget {
  const _InstitutionPickerSheet({this.sections});

  /// 限定展示的分组标签（null = 全部）
  final Set<String>? sections;

  @override
  State<_InstitutionPickerSheet> createState() =>
      _InstitutionPickerSheetState();
}

class _InstitutionPickerSheetState extends State<_InstitutionPickerSheet> {
  String _keyword = '';

  /// 本次弹层生效的分组（保持 [kInstitutionSections] 原顺序）
  List<InstitutionSection> get _visibleSections {
    final filter = widget.sections;
    if (filter == null) return kInstitutionSections;
    return [
      for (final s in kInstitutionSections)
        if (filter.contains(s.label)) s,
    ];
  }

  /// 构建列表行：无关键词时按分组展示——组头 + 条目，条目多的组
  /// （>= [kAlphabetThreshold]）再按拼音首字母分段（如银行组的
  /// B/C/G… 段）；有关键词时跨组扁平过滤，无段头
  List<_SheetRow> get _rows {
    final kw = _keyword.trim().toLowerCase();
    if (kw.isNotEmpty) {
      return [
        for (final s in _visibleSections)
          for (final d in s.items)
            if (d.name.toLowerCase().contains(kw)) _ItemRow(d),
      ];
    }
    return [
      for (final s in _visibleSections) ...[
        _HeaderRow(s.label),
        if (s.items.length >= kAlphabetThreshold)
          for (final bucket in groupInstitutionsByInitial(s.items)) ...[
            _HeaderRow(bucket.key.toUpperCase()),
            for (final d in bucket.value) _ItemRow(d),
          ]
        else
          for (final d in s.items) _ItemRow(d),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    // 骨架（拖动条/标题/分隔线）由 bottom_sheet_scaffold 提供，
    // 这里只负责搜索框与列表区
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _keyword = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索机构',
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: AppColors.textSecondary,
              ),
              isDense: true,
              filled: true,
              fillColor: AppColors.fill,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusControl),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        Flexible(
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '没有匹配的机构',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is _HeaderRow) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Text(
                          row.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    final def = (row as _ItemRow).def;
                    return ListTile(
                      leading: InstitutionLogo(
                        name: def.name,
                        size: 36,
                      ),
                      title: Text(
                        def.name,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(def.name),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

