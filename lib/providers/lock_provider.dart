import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

import '../utils/passcode_util.dart';
import 'settings_provider.dart';

/// 密码锁状态管理：冷启动锁 + 后台返回超时锁
///
/// 锁定态全屏盖 LockGate（MaterialApp.builder 注入），任何页面都无法绕过；
/// 超时判定：切后台（hidden）记录时间，回到前台（resumed）时超过
/// settings.lockTimeoutSeconds 且密码已启用则进入锁定态
class LockProvider extends ChangeNotifier with WidgetsBindingObserver {
  LockProvider(this._settings) {
    WidgetsBinding.instance.addObserver(this);
    // 冷启动：密码已启用则直接进入锁定态（首次解锁前一直锁着）
    _locked = _settings.passcodeEnabled;
  }

  final SettingsProvider _settings;

  final LocalAuthentication _auth = LocalAuthentication();

  bool _locked = false;

  /// 当前是否处于锁定态
  bool get locked => _locked;

  DateTime? _hiddenAt;

  /// 本机生物识别是否可用（设备支持且已录入）；
  /// 异步探测一次后缓存，锁屏页据此决定是否显示指纹按钮
  bool _biometricAvailable = false;
  bool _biometricChecked = false;

  bool get biometricAvailable => _biometricAvailable;

  /// 是否以面容为主要生物识别方式。
  /// 解锁调用走系统 BiometricPrompt，本身就是"面容 > 指纹"自动选择；
  /// 这里只影响锁屏页快捷按钮的图标显示
  bool _usesFace = false;

  bool get usesFace => _usesFace;

  /// 探测本机生物识别可用性（锁屏页与设置页共用）
  Future<void> ensureBiometricChecked() async {
    if (_biometricChecked) return;
    _biometricChecked = true;
    try {
      _biometricAvailable =
          await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
      if (_biometricAvailable) {
        final biometrics = await _auth.getAvailableBiometrics();
        _usesFace = biometrics.contains(BiometricType.face);
      }
    } catch (_) {
      // 平台异常（如模拟器无硬件）按不可用处理，走 PIN 降级
      _biometricAvailable = false;
    }
    notifyListeners();
  }

  /// 弹出系统生物识别对话框，返回是否通过
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        // localizedReason 渲染在弹框 description 位（灰色说明行），
        // 传空格避免与 signInTitle（大标题）重复显示"指纹解锁"两次
        localizedReason: ' ',
        // 系统框文案汉化：清掉默认的 Authentication required / 提示行，
        // Cancel 按钮本地化
        authMessages: [
          AndroidAuthMessages(
            biometricHint: '',
            cancelButton: '取消',
            signInTitle: _usesFace ? '面容解锁' : '指纹解锁',
          ),
          const IOSAuthMessages(cancelButton: '取消'),
        ],
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      // 用户取消、多次失败锁定或平台异常一律视为未通过
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden) {
      // hidden = 界面完全不可见（切后台/进分屏），从此刻起算超时
      _hiddenAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  void _onResumed() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    // 密码被关闭时（设置页 clearPasscode）自动解除锁定态
    if (!_settings.passcodeEnabled) {
      if (_locked) {
        _locked = false;
        notifyListeners();
      }
      return;
    }
    // 冷启动锁由构造函数处理，这里只处理后台返回超时
    if (hiddenAt == null) return;
    final elapsed = DateTime.now().difference(hiddenAt);
    if (elapsed.inSeconds >= _settings.lockTimeoutSeconds && !_locked) {
      _locked = true;
      notifyListeners();
    }
  }

  /// 解锁（PIN 校验通过或生物识别通过后调用）
  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  /// 锁屏页校验 PIN
  bool verifyPasscode(String pin) {
    final salt = _settings.passcodeSalt;
    final hash = _settings.passcodeHash;
    if (salt == null || hash == null) return false;
    return PasscodeUtil.verify(salt, pin, hash);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
