import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 自绘数字键盘（4×4 网格，参考钱迹布局）
///
/// 行 1：1 2 3 退格 ｜ 行 2：4 5 6 清空
/// 行 3：7 8 9 再记 ｜ 行 4：今 0 . 保存
/// "再记"保存后不退出页面，便于连续记账；"今"把日期快捷设为今天。
/// 键位输入约束（小数位数、前导零等）由页面层统一处理。
class NumberKeyboard extends StatelessWidget {
  const NumberKeyboard({
    super.key,
    required this.onKey,
    required this.onDelete,
    required this.onClear,
    required this.onToday,
    required this.onAgain,
    required this.onDone,
  });

  /// 数字与小数点按键回调（值为 '0'-'9' 或 '.'）
  final ValueChanged<String> onKey;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback onToday;
  final VoidCallback onAgain;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    // 白底与页面融为一体，键间以细分割线区隔
    return Column(
      children: [
        Divider(height: 1, thickness: 1, color: AppColors.divider),
        _row([
          _numberKey('1'),
          _numberKey('2'),
          _numberKey('3'),
          _iconKey(Icons.backspace_outlined, onDelete),
        ]),
        _row([
          _numberKey('4'),
          _numberKey('5'),
          _numberKey('6'),
          _textKey('清空', onClear),
        ]),
        _row([
          _numberKey('7'),
          _numberKey('8'),
          _numberKey('9'),
          _textKey('再记', onAgain),
        ]),
        _row([
          _textKey('今', onToday),
          _numberKey('0'),
          _numberKey('.'),
          _saveKey(),
        ]),
      ],
    );
  }

  /// 一行 4 键，键间以细分割线区隔
  Widget _row(List<Widget> keys) {
    return Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) Container(width: 1, height: 40, color: AppColors.divider),
          Expanded(child: keys[i]),
        ],
      ],
    );
  }

  /// 数字 / 小数点键
  Widget _numberKey(String value) {
    return _KeyWrapper(
      onTap: () => onKey(value),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// 图标键（退格）
  Widget _iconKey(IconData icon, VoidCallback onTap) {
    return _KeyWrapper(
      onTap: onTap,
      child: Icon(icon, size: 22, color: AppColors.textPrimary),
    );
  }

  /// 文字功能键（清空 / 再记 / 今）
  Widget _textKey(String label, VoidCallback onTap) {
    return _KeyWrapper(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  /// 保存键：主色实底圆角，视觉重心
  Widget _saveKey() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppDimens.radiusControl),
        child: InkWell(
          onTap: onDone,
          borderRadius: BorderRadius.circular(AppDimens.radiusControl),
          child: const SizedBox(
            height: 40,
            child: Center(
              child: Text(
                '保存',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 键盘按键的水波反馈容器
class _KeyWrapper extends StatelessWidget {
  const _KeyWrapper({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(height: 52, child: Center(child: child)),
      ),
    );
  }
}
