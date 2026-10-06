import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 六位数字九宫格输入组件：锁屏 / 设置 / 验证 / 重置四场景共用
///
/// 输满 6 位回调 [PinPadInput.onCompleted]：返回 true 视为通过（清空圆点继续），
/// 返回 false 视为校验失败（抖动 + 清空重输）。
/// 标题/副标题与阶段切换由使用方（页面）管理，组件只管输入与反馈
class PinPadInput extends StatefulWidget {
  const PinPadInput({
    super.key,
    required this.onCompleted,
    this.onBiometric,
    this.biometricIcon = Icons.fingerprint,
  });

  final Future<bool> Function(String pin) onCompleted;

  /// 底部指纹键回调：null 时该位置空占位（保持 0 居中对齐）
  final VoidCallback? onBiometric;

  /// 指纹键图标（面容设备显示面容图标）
  final IconData biometricIcon;

  @override
  State<PinPadInput> createState() => _PinPadInputState();
}

class _PinPadInputState extends State<PinPadInput>
    with SingleTickerProviderStateMixin {
  final List<int> _digits = [];

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  Future<void> _press(int digit) async {
    if (_digits.length >= 6 || _shake.isAnimating) return;
    HapticFeedback.lightImpact();
    setState(() => _digits.add(digit));
    if (_digits.length < 6) return;
    final ok = await widget.onCompleted(_digits.join());
    if (!mounted) return;
    if (ok) {
      setState(_digits.clear);
    } else {
      // 校验失败：抖动提示后清空重输
      _shake.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 450));
      if (mounted) setState(_digits.clear);
    }
  }

  void _backspace() {
    if (_digits.isEmpty || _shake.isAnimating) return;
    HapticFeedback.lightImpact();
    setState(() => _digits.removeLast());
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 圆点行：实心=已输入，抖动动画提示校验失败
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final dx = _shake.isAnimating
                ? sin(_shake.value * 3 * pi) * 8 * (1 - _shake.value)
                : 0.0;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 6; i++)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _digits.length
                        ? AppColors.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        // 九宫格：3×4 布局，底行三键等分
        SizedBox(
            width: 264,
            child: Column(
              children: [
                // 行间距 16：键面之间留呼吸感，避免上下行挤在一起
                for (final row in const [
                  [1, 2, 3],
                  [4, 5, 6],
                  [7, 8, 9],
                ]) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [for (final d in row) _key(d)],
                  ),
                  const SizedBox(height: 16),
                ],
                // 底行与上三行同用 spaceBetween：边缘键中心严格重合
                // （Expanded 等分会让 0/退格相对 2/5/8、3/6/9 列偏内）；
                // 指纹缺席时以 64 空占位保持键位不变
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    widget.onBiometric != null
                        ? _iconKey(
                            widget.biometricIcon,
                            onTap: widget.onBiometric!,
                          )
                        : const SizedBox(width: 64, height: 64),
                    _key(0),
                    _iconKey(Icons.backspace_outlined, onTap: _backspace),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _key(int digit) {
    return GestureDetector(
      onTap: () => _press(digit),
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.textSecondary.withValues(alpha: 0.06),
        ),
        child: Text(
          '$digit',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 底部圆键（指纹/退格）：与数字键同款 64 灰圆，内容为图标
  Widget _iconKey(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.textSecondary.withValues(alpha: 0.06),
        ),
        child: Icon(icon, size: 26, color: AppColors.textPrimary),
      ),
    );
  }
}
