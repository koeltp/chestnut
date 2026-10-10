import 'package:flutter/material.dart';

import '../../models/asset_category.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// 底部弹窗：选择信用卡银行（钱迹式，搜索 + 银行列表）
///
/// 返回选中的银行名（如"招商银行"）；关闭返回 null。
/// 银行 logo 用首字圆形标（取行首两字更辨识，如"招行"），配色
/// 从内置色板按银行名稳定取色——同名银行每次打开颜色一致。
Future<String?> showBankPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BankPickerSheet(),
  );
}

/// 银行 logo 文字：全称 → 2 字简称（"招商银行"→"招行"）
String bankShortName(String name) {
  if (name.length <= 2) return name;
  // 特例优先：常见全称的简称映射，其余取前两字
  const special = <String, String>{
    '中国银行': '中行',
    '工商银行': '工行',
    '农业银行': '农行',
    '建设银行': '建行',
    '交通银行': '交行',
    '招商银行': '招行',
    '邮政储蓄银行': '邮储',
    '浦发银行': '浦发',
    '中信银行': '中信',
    '兴业银行': '兴业',
    '民生银行': '民生',
    '光大银行': '光大',
    '平安银行': '平安',
    '华夏银行': '华夏',
    '广发银行': '广发',
    '浙商银行': '浙商',
    '微众银行': '微众',
    '网商银行': '网商',
    '其它银行': '其它',
  };
  return special[name] ?? name.substring(0, 2);
}

class _BankPickerSheet extends StatefulWidget {
  const _BankPickerSheet();

  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  String _keyword = '';

  /// 按关键词过滤（包含匹配，大小写不敏感）
  List<String> get _filtered {
    final kw = _keyword.trim().toLowerCase();
    if (kw.isEmpty) return AssetGroups.banks;
    return AssetGroups.banks
        .where((b) => b.toLowerCase().contains(kw))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final banks = _filtered;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppDimens.gapMd),
            child: Text(
              '选择银行',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _keyword = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索银行',
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
            child: banks.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '没有匹配的银行',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: banks.length,
                    itemBuilder: (context, i) {
                      final bank = banks[i];
                      return ListTile(
                        leading: _BankLogo(name: bank),
                        title: Text(
                          bank,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(bank),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 银行首字圆标：简称 + 按名稳定取色
class _BankLogo extends StatelessWidget {
  const _BankLogo({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    // 以银行名做种子取色板下标：同名银行颜色稳定
    final color = AppColors
        .tagPalette[name.hashCode.abs() % AppColors.tagPalette.length];
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(color).withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        bankShortName(name),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(color),
        ),
      ),
    );
  }
}
