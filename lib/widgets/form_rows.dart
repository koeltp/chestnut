import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'section_card.dart';

/// 钱迹式行式表单卡片：白卡内多行"左标签右值"，行间自动插分割线
///
/// 用 [FormRow] / [FormInputRow] / [FormSwitchRow] 组成 rows 传入，
/// 卡片负责补齐行间分割线，保证各编辑页视觉一致。
class FormRowsCard extends StatelessWidget {
  const FormRowsCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const Divider(height: 1));
      children.add(rows[i]);
    }
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

/// 表单行：左标签 + 右内容；[onTap] 非空时整行可点（水波反馈）
class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.cardPadding),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppDimens.gapLg),
            Expanded(child: child),
          ],
        ),
      ),
    );
    if (onTap == null) return padded;
    return InkWell(onTap: onTap, child: padded);
  }
}

/// 文本输入行：右侧无边框透明底输入框，默认右对齐（钱迹式）
class FormInputRow extends StatelessWidget {
  const FormInputRow({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLength,
    this.inputFormatters,
    this.textInputAction,
    this.textAlign = TextAlign.right,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return FormRow(
      label: label,
      child: Center(
        child: TextField(
          controller: controller,
          textAlign: textAlign,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            isDense: true,
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

/// 开关行：左标签（可带灰色副标题说明），右侧 Switch
class FormSwitchRow extends StatelessWidget {
  const FormSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 副标题说明小字（灰色，位于标签下方）
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 右侧留出 Switch 自身边距，避免整行过宽
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
