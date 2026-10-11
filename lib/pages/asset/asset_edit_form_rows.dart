import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/form_rows.dart';

/// 机构行的标签文案：卡类叫银行，股票/期货叫券商，基金叫平台，其余叫机构
String assetInstitutionLabel(String categoryName) => switch (categoryName) {
  '信用卡' || '银行卡' => '所属银行',
  '股票' || '期货' => '所属券商',
  '基金' => '所属平台',
  _ => '所属机构',
};

/// 机构行的占位文案（与标签同口径）
String assetInstitutionHint(String categoryName) =>
    switch (assetInstitutionLabel(categoryName)) {
      '所属银行' => '请选择银行',
      '所属券商' => '请选择券商',
      '所属平台' => '请选择平台',
      _ => '请选择机构',
    };

/// 所属机构选择行：卡类=所属银行，投资理财组=券商/平台。
/// 点行重新选择，已选显示 ×（点 × 只清机构，不影响账户名），
/// 未选显示 >；两者同为 22×22 盒子，切换时位置不跳
class AssetInstitutionRow extends StatelessWidget {
  const AssetInstitutionRow({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;

  /// 已选机构名（null = 未选，显示占位文案）
  final String? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return FormRow(
      label: label,
      onTap: onPick,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value ?? assetInstitutionHint(label),
            style: TextStyle(
              fontSize: 15,
              color: value == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
          if (value != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: Icon(
                  Icons.close,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            const Icon(
              Icons.chevron_right,
              size: 22,
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}

/// 出账日/还款日行：点行弹「每月几号」选日，已选显示"每月 X 日"
/// 并带 × 可清除，未选显示占位；尾部图标同为 22×22 盒子，切换不跳位
class AssetDayRow extends StatelessWidget {
  const AssetDayRow({
    super.key,
    required this.label,
    required this.day,
    required this.onPick,
    required this.onClear,
  });

  final String label;

  /// 已选日期（1~31，null = 未填）
  final int? day;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return FormRow(
      label: label,
      onTap: onPick,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _dayText(day),
            style: TextStyle(
              fontSize: 15,
              color: day == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
          _dayTrailing(day, onClear),
        ],
      ),
    );
  }

  /// 显示文案：已选显示"每月 X 日"，未选显示占位
  String _dayText(int? day) =>
      day == null ? '选填，点此选择' : '每月 $day 日';

  /// 行尾图标：已选显示 ×（点清除），未选显示 >；
  /// 两者同为 22×22 盒子，切换时位置不跳
  Widget _dayTrailing(int? day, VoidCallback onClear) {
    if (day == null) {
      return const Icon(
        Icons.chevron_right,
        size: 22,
        color: AppColors.textSecondary,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClear,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: Icon(Icons.close, size: 22, color: AppColors.textSecondary),
      ),
    );
  }
}
