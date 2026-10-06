import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/lock_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/passcode_util.dart';

/// 六位数字九宫格输入组件：锁屏 / 设置 / 验证 / 重置四场景共用
///
/// 输满 6 位回调 [onCompleted]：返回 true 视为通过（清空圆点继续），
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

/// 密码锁屏页：MaterialApp.builder 全屏注入，PopScope 禁止返回绕过
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    final lock = context.read<LockProvider>();
    lock.ensureBiometricChecked();
    // 已开启生物识别且本机可用：进入锁屏直接弹系统验证
    // （系统框即"指纹解锁"的视觉呈现，取消/失败后留在密码键盘）
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoBiometric());
  }

  Future<void> _autoBiometric() async {
    final settings = context.read<SettingsProvider>();
    final lock = context.read<LockProvider>();
    if (!settings.biometricEnabled || !lock.biometricAvailable) return;
    await _biometric();
  }

  Future<void> _biometric() async {
    final ok = await context.read<LockProvider>().authenticateWithBiometrics();
    if (ok && mounted) context.read<LockProvider>().unlock();
  }

  Future<bool> _verify(String pin) async {
    final lock = context.read<LockProvider>();
    final ok = lock.verifyPasscode(pin);
    if (ok) lock.unlock();
    return ok;
  }

  /// 当前视图：pin 密码键盘 / security 安全问题验证 / reset 重设新密码。
  /// 忘记密码流程在锁屏内切换视图而非走路由——LockGate 盖在 Navigator
  /// 之上，从锁屏 push 的新页面会被锁屏遮罩挡住（表现为"点击没反应"）
  String _view = 'pin';

  /// 子视图骨架：顶部返回行 + 内容区（忘记密码流程共用）
  Widget _subView({
    required String title,
    required VoidCallback onBack,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        Expanded(child: child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<LockProvider>();
    final settings = context.watch<SettingsProvider>();
    final showBiometric = settings.biometricEnabled && lock.biometricAvailable;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: switch (_view) {
          'security' => _subView(
            title: '找回密码',
            onBack: () => setState(() => _view = 'pin'),
            child: SecurityVerifyBody(
              onPassed: () => setState(() => _view = 'reset'),
            ),
          ),
          'reset' => _subView(
            title: '设置新密码',
            onBack: () => setState(() => _view = 'security'),
            child: ResetPasscodeBody(
              onFinished: () => setState(() => _view = 'pin'),
            ),
          ),
          _ => Column(
            children: [
              const Spacer(flex: 2),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 56,
                  height: 56,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '输入密码',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              PinPadInput(
                onCompleted: _verify,
                onBiometric: showBiometric ? _biometric : null,
                biometricIcon: lock.usesFace ? Icons.face : Icons.fingerprint,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _view = 'security'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '忘记密码？',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        },
      ),
    );
  }
}

/// 安全问题验证（忘记密码兜底）：答对后回调 [onPassed] 进入重设密码流程。
/// 锁屏页内嵌使用，不走路由（LockGate 盖在 Navigator 之上，
/// 从锁屏 push 的页面会被锁屏遮罩挡住）
class SecurityVerifyBody extends StatefulWidget {
  const SecurityVerifyBody({super.key, required this.onPassed});

  final VoidCallback onPassed;

  @override
  State<SecurityVerifyBody> createState() => _SecurityVerifyBodyState();
}

class _SecurityVerifyBodyState extends State<SecurityVerifyBody> {
  final _controller = TextEditingController();

  bool get _hasQuestion =>
      context.read<SettingsProvider>().securityQuestion != null;

  Future<void> _submit() async {
    final settings = context.read<SettingsProvider>();
    final salt = settings.passcodeSalt;
    final answerHash = settings.securityAnswerHash;
    final question = settings.securityQuestion;
    if (salt == null || answerHash == null || question == null) return;
    final ok = PasscodeUtil.verify(
      salt,
      _controller.text.trim(),
      answerHash,
    );
    if (!mounted) return;
    if (ok) {
      widget.onPassed();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('答案不正确，请重试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppDimens.pagePadding),
      children: [
        Text(
          _hasQuestion
              ? context.read<SettingsProvider>().securityQuestion!
              : '未设置安全问题',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: '输入安全问题答案',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('确认', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

/// 重设新 PIN（答对安全问题后）：两遍输入确认，完成后更新 PIN 并解锁。
/// 锁屏页内嵌使用，不走路由
class ResetPasscodeBody extends StatefulWidget {
  const ResetPasscodeBody({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<ResetPasscodeBody> createState() => _ResetPasscodeBodyState();
}

class _ResetPasscodeBodyState extends State<ResetPasscodeBody> {
  String? _firstPin;
  String? _errorText;

  Future<bool> _onCompleted(String pin) async {
    final settings = context.read<SettingsProvider>();
    if (_firstPin == null) {
      // 阶段一：记住第一遍，进入确认阶段
      setState(() {
        _firstPin = pin;
        _errorText = null;
      });
      return true;
    }
    // 阶段二：两遍一致才生效
    if (pin != _firstPin) {
      setState(() {
        _errorText = '两次输入不一致，请重新设置';
        _firstPin = null;
      });
      return false;
    }
    final salt = PasscodeUtil.generateSalt();
    await settings.updatePasscode(salt, PasscodeUtil.hash(salt, pin));
    if (!mounted) return true;
    // 新密码生效即解锁，锁屏遮罩随之消失
    context.read<LockProvider>().unlock();
    widget.onFinished();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final settingFirst = _firstPin == null;
    return Column(
      children: [
        const SizedBox(height: 32),
        Text(
          settingFirst ? '请输入新的 6 位密码' : '请再次输入确认',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.expense,
            ),
          ),
        ],
        const SizedBox(height: 24),
        PinPadInput(
          key: ValueKey(settingFirst),
          onCompleted: _onCompleted,
        ),
      ],
    );
  }
}
