import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/lock_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/passcode_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/pin_pad_input.dart';
import '../../widgets/section_card.dart';

/// 密码保护设置页：开启（PIN → 确认 → 安全问题）/ 修改 / 关闭
///
/// 页内状态机切换流程界面（不 push 子页）：verifyOld 验证当前密码后
/// 再进入对应操作，PIN 输入复用锁屏的 PinPadInput 组件
class PasscodeSettingsPage extends StatefulWidget {
  const PasscodeSettingsPage({super.key, this.startSetup = false});

  /// true = 进入页面立即开始"设置新密码"流程
  /// （未设密码时点"密码保护"直达，跳过半空的未设置态主界面）
  final bool startSetup;

  @override
  State<PasscodeSettingsPage> createState() => _PasscodeSettingsPageState();
}

/// 页内流程：主界面 / 输新密码 / 确认新密码 / 验证当前密码 / 设置安全问题
enum _Flow { none, setNew, setNewConfirm, verifyOld, editQuestion }

class _PasscodeSettingsPageState extends State<PasscodeSettingsPage> {
  /// 预设安全问题（固定三选，不支持自定义，降低设置摩擦）
  static const _questions = ['您母亲的姓名是？', '您的第一所学校是？', '您出生的城市是？'];

  _Flow _flow = _Flow.none;

  /// 第一遍输入的新 PIN（确认阶段比对用）
  String? _pendingPin;

  /// verifyOld 通过后要执行的动作：changePin / editQuestion / disable
  String? _pendingAction;

  /// 是否处于首次开启流程（开启 = 新 PIN + 安全问题一次性写入）
  bool _enabling = false;

  String? _errorText;
  int _selectedQuestionIndex = 0;
  final _answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 探测本机生物识别可用性（LockProvider 缓存，锁屏页共用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 探测本机生物识别可用性（LockProvider 缓存，锁屏页共用）
      context.read<LockProvider>().ensureBiometricChecked();
      // 未设密码直达：跳过主界面直接进设置流程
      if (widget.startSetup) {
        setState(() {
          _enabling = true;
          _pendingPin = null;
          _flow = _Flow.setNew;
        });
      }
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _resetFlow() {
    setState(() {
      _flow = _Flow.none;
      _pendingPin = null;
      _pendingAction = null;
      _errorText = null;
    });
  }

  void _showToast(String message) {
    showAppToast(context, message);
  }

  // ===== 主界面动作 =====

  Future<void> _onMainSwitch(bool value) async {
    if (value) {
      // 开启：进入"设置新密码"流程
      setState(() {
        _enabling = true;
        _pendingPin = null;
        _flow = _Flow.setNew;
      });
      return;
    }
    // 关闭：先验证当前密码
    setState(() {
      _pendingAction = 'disable';
      _flow = _Flow.verifyOld;
    });
  }

  /// 进入需要验证当前密码的操作
  void _requireVerifyThen(String action) {
    setState(() {
      _pendingAction = action;
      _flow = _Flow.verifyOld;
    });
  }

  // ===== PIN 输入流程 =====

  Future<bool> _onPinCompleted(String pin) async {
    final settings = context.read<SettingsProvider>();
    switch (_flow) {
      case _Flow.verifyOld:
        final salt = settings.passcodeSalt;
        final hash = settings.passcodeHash;
        final ok = salt != null &&
            hash != null &&
            PasscodeUtil.verify(salt, pin, hash);
        if (!ok) return false;
        switch (_pendingAction) {
          case 'changePin':
            setState(() {
              _enabling = false;
              _pendingPin = null;
              _flow = _Flow.setNew;
            });
          case 'editQuestion':
            setState(() => _flow = _Flow.editQuestion);
          case 'disable':
            await settings.clearPasscode();
            if (!mounted) return true;
            // 关闭后不留在未设置态主界面，直接退回我的页面
            _showToast('密码保护已关闭');
            Navigator.of(context).pop();
        }
        return true;
      case _Flow.setNew:
        // 记住第一遍，进入确认阶段
        setState(() {
          _pendingPin = pin;
          _errorText = null;
          _flow = _Flow.setNewConfirm;
        });
        return true;
      case _Flow.setNewConfirm:
        if (pin != _pendingPin) {
          setState(() {
            _errorText = '两次输入不一致，请重新设置';
            _pendingPin = null;
            _flow = _Flow.setNew;
          });
          return false;
        }
        if (_enabling) {
          // 首次开启：接着设置安全问题
          setState(() {
            _errorText = null;
            _flow = _Flow.editQuestion;
          });
          return true;
        }
        // 修改密码：直接生效
        final salt = PasscodeUtil.generateSalt();
        await settings.updatePasscode(salt, PasscodeUtil.hash(salt, pin));
        if (!mounted) return true;
        _resetFlow();
        _showToast('密码已修改');
        return true;
      case _Flow.none:
      case _Flow.editQuestion:
        return false;
    }
  }

  // ===== 安全问题保存 =====

  Future<void> _saveQuestion() async {
    final settings = context.read<SettingsProvider>();
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      _showToast('请输入安全问题答案');
      return;
    }
    if (_enabling) {
      final pin = _pendingPin!;
      final salt = PasscodeUtil.generateSalt();
      await settings.savePasscode(
        salt: salt,
        hash: PasscodeUtil.hash(salt, pin),
        question: _questions[_selectedQuestionIndex],
        answerHash: PasscodeUtil.hash(salt, answer),
      );
      if (!mounted) return;
      _resetFlow();
      _showToast('密码保护已开启');
      return;
    }
    await settings.updateSecurityQuestion(
      _questions[_selectedQuestionIndex],
      PasscodeUtil.hash(settings.passcodeSalt ?? '', answer),
    );
    if (!mounted) return;
    _resetFlow();
    _showToast('安全问题已更新');
  }

  // ===== 界面 =====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _flow == _Flow.editQuestion ? '安全问题' : '密码保护',
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_flow) {
      case _Flow.none:
        return _buildMain();
      case _Flow.setNew:
      case _Flow.setNewConfirm:
      case _Flow.verifyOld:
        return _buildPinFlow();
      case _Flow.editQuestion:
        return _buildQuestionSetup();
    }
  }

  /// PIN 输入流程页（输新密码 / 确认 / 验证当前密码共用）
  Widget _buildPinFlow() {
    final title = switch (_flow) {
      _Flow.setNew => '请输入 6 位密码',
      _Flow.setNewConfirm => '请再次输入确认',
      _ => '请输入当前密码',
    };
    return Column(
      children: [
        const SizedBox(height: 32),
        Text(
          title,
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
            style: const TextStyle(fontSize: 13, color: AppColors.expense),
          ),
        ],
        const SizedBox(height: 24),
        PinPadInput(key: ValueKey(_flow), onCompleted: _onPinCompleted),
      ],
    );
  }

  /// 主界面：开关 + 管理项（仅开启后显示）
  Widget _buildMain() {
    final settings = context.watch<SettingsProvider>();
    final lock = context.watch<LockProvider>();
    final enabled = settings.passcodeEnabled;
    final biometricAvailable = lock.biometricAvailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        AppDimens.gapSection,
        AppDimens.pagePadding,
        24,
      ),
      children: [
        SectionCard(
          child: Column(
            children: [
              SwitchListTile(
                value: enabled,
                onChanged: _onMainSwitch,
                title: const Text(
                  '数字密码',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  enabled
                      ? '已设置，打开应用与后台返回时需解锁'
                      : '未设置，开启后每次使用需输入密码',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(indent: 16, endIndent: 16),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  // 指纹是数字密码的快捷解锁方式：数字密码未设置时
                  // 禁用（生物识别失败必须能落到 PIN，否则会被锁在门外）
                  final pinReady = settings.passcodeEnabled;
                  final canToggle = biometricAvailable && pinReady;
                  final subtitle = !biometricAvailable
                      ? '本机不支持生物识别'
                      : !pinReady
                      ? '设置数字密码后，可用指纹/面容快速解锁'
                      : '锁屏页可直接用生物识别解锁';
                  return SwitchListTile(
                    value: settings.biometricEnabled && canToggle,
                    onChanged: canToggle
                        ? (v) => context
                              .read<SettingsProvider>()
                              .setBiometricEnabled(v)
                        : null,
                    title: Text(
                      '指纹/面容快捷解锁',
                      style: TextStyle(
                        fontSize: 15,
                        color: canToggle
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    subtitle: Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: AppDimens.gapSection),
          SectionCard(
            child: Column(
              children: [
                ListTile(
                  title: const Text(
                    '修改密码',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => _requireVerifyThen('changePin'),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: const Text(
                    '修改安全问题',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    settings.securityQuestion ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => _requireVerifyThen('editQuestion'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapSection),
          SectionCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.pagePadding,
              vertical: AppDimens.gapMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '后台返回锁定时机',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                AppSegmented<int>(
                  options: const [(0, '立即'), (60, '1分钟'), (300, '5分钟')],
                  selected: settings.lockTimeoutSeconds,
                  fit: AppSegmentedFit.stretch,
                  onChanged: (v) =>
                      context.read<SettingsProvider>().setLockTimeoutSeconds(v),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 安全问题设置（开启流程最后一步 / 修改安全问题共用）
  Widget _buildQuestionSetup() {
    return ListView(
      padding: const EdgeInsets.all(AppDimens.pagePadding),
      children: [
        const Text(
          '选择安全问题（忘记密码时用于重置）',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _questions[_selectedQuestionIndex],
          isExpanded: true,
          items: [
            for (final q in _questions)
              DropdownMenuItem(
                value: q,
                child: Text(
                  q,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _selectedQuestionIndex = _questions.indexOf(v));
          },
          decoration: const InputDecoration(
            labelText: '安全问题',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _answerController,
          maxLines: 1,
          decoration: const InputDecoration(
            labelText: '答案',
            hintText: '输入问题答案',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saveQuestion,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(
            _enabling ? '完成并开启保护' : '保存',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }
}
