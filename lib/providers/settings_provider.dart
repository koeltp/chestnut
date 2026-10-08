import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置状态管理
///
/// 持久化到 SharedPreferences 的轻量开关集合；
/// main 启动时预加载实例，避免 UI 读取时异步等待。
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs);

  final SharedPreferences _prefs;

  /// 记一笔页是否显示定位功能
  static const _kBillLocationEnabled = 'bill_location_enabled';

  bool get billLocationEnabled =>
      _prefs.getBool(_kBillLocationEnabled) ?? false;

  /// 切换记账定位开关
  Future<void> setBillLocationEnabled(bool value) async {
    if (value == billLocationEnabled) return;
    await _prefs.setBool(_kBillLocationEnabled, value);
    notifyListeners();
  }

  /// 是否开启每日自动备份（公开常量：BackupService 启动时读同一键）
  static const kAutoBackupEnabled = 'auto_backup_enabled';

  bool get autoBackupEnabled => _prefs.getBool(kAutoBackupEnabled) ?? false;

  /// 切换每日自动备份开关
  Future<void> setAutoBackupEnabled(bool value) async {
    if (value == autoBackupEnabled) return;
    await _prefs.setBool(kAutoBackupEnabled, value);
    notifyListeners();
  }

  /// 预算模式：沿用上月预算 | 按上月消费（两种策略互斥）
  static const _kBudgetMode = 'budget_mode';

  /// 预算模式；null = 未选（清空预算后回到此状态：分段器两段都不
  /// 选中、进页面不自动填充，直到用户点选某个模式）。
  /// 新装用户无存储值时默认"按上月消费"，保留开箱即用体验
  BudgetMode? get budgetMode {
    final raw = _prefs.getInt(_kBudgetMode);
    if (raw == null) return BudgetMode.lastMonthSpend;
    // -1 哨兵值 = 未选；越界值兜底同样视为未选
    if (raw < 0 || raw >= BudgetMode.values.length) return null;
    return BudgetMode.values[raw];
  }

  /// 切换预算模式；传 null 表示置为"未选"（清空预算时调用）
  Future<void> setBudgetMode(BudgetMode? value) async {
    if (value == budgetMode) return;
    // 用 -1 存"未选"而非移除键——移除会被 getter 当作新装默认值
    await _prefs.setInt(_kBudgetMode, value?.index ?? -1);
    notifyListeners();
  }

  // ===== 密码保护 =====

  /// 是否启用密码锁（6 位数字 PIN）
  static const _kPasscodeEnabled = 'passcode_enabled';

  bool get passcodeEnabled => _prefs.getBool(_kPasscodeEnabled) ?? false;

  /// PIN 的随机盐与哈希（明文不可逆，盐随 PIN 一起生成）
  static const _kPasscodeSalt = 'passcode_salt';
  static const _kPasscodeHash = 'passcode_hash';

  String? get passcodeSalt => _prefs.getString(_kPasscodeSalt);

  String? get passcodeHash => _prefs.getString(_kPasscodeHash);

  /// 安全问题（忘记密码兜底）
  static const _kSecurityQuestion = 'security_question';
  static const _kSecurityAnswerHash = 'security_answer_hash';

  String? get securityQuestion => _prefs.getString(_kSecurityQuestion);

  String? get securityAnswerHash => _prefs.getString(_kSecurityAnswerHash);

  /// 后台返回锁的超时秒数：0 立即 / 60 / 300（默认 1 分钟）
  static const _kLockTimeoutSeconds = 'lock_timeout_seconds';

  int get lockTimeoutSeconds => _prefs.getInt(_kLockTimeoutSeconds) ?? 60;

  /// 是否允许指纹/面容快捷解锁（设备支持为前提）
  static const _kBiometricEnabled = 'biometric_enabled';

  bool get biometricEnabled => _prefs.getBool(_kBiometricEnabled) ?? false;

  /// 首次开启：一次性写入 PIN 与安全问题并启用
  Future<void> savePasscode({
    required String salt,
    required String hash,
    required String question,
    required String answerHash,
  }) async {
    await _prefs.setString(_kPasscodeSalt, salt);
    await _prefs.setString(_kPasscodeHash, hash);
    await _prefs.setString(_kSecurityQuestion, question);
    await _prefs.setString(_kSecurityAnswerHash, answerHash);
    await _prefs.setBool(_kPasscodeEnabled, true);
    notifyListeners();
  }

  /// 修改 PIN（保留原安全问题）
  Future<void> updatePasscode(String salt, String hash) async {
    await _prefs.setString(_kPasscodeSalt, salt);
    await _prefs.setString(_kPasscodeHash, hash);
    notifyListeners();
  }

  /// 修改安全问题
  Future<void> updateSecurityQuestion(String question, String answerHash) async {
    await _prefs.setString(_kSecurityQuestion, question);
    await _prefs.setString(_kSecurityAnswerHash, answerHash);
    notifyListeners();
  }

  /// 设置后台返回锁超时（秒）
  Future<void> setLockTimeoutSeconds(int seconds) async {
    if (seconds == lockTimeoutSeconds) return;
    await _prefs.setInt(_kLockTimeoutSeconds, seconds);
    notifyListeners();
  }

  /// 切换生物识别快捷解锁
  Future<void> setBiometricEnabled(bool value) async {
    if (value == biometricEnabled) return;
    await _prefs.setBool(_kBiometricEnabled, value);
    notifyListeners();
  }

  /// 关闭密码保护：清除全部密码相关数据（指纹快捷开关一并复位，
  /// 重开时需重新开启，避免"门锁拆了快捷方式还留着"的脏状态）
  Future<void> clearPasscode() async {
    await _prefs.remove(_kPasscodeSalt);
    await _prefs.remove(_kPasscodeHash);
    await _prefs.remove(_kSecurityQuestion);
    await _prefs.remove(_kSecurityAnswerHash);
    await _prefs.setBool(_kPasscodeEnabled, false);
    await _prefs.setBool(_kBiometricEnabled, false);
    notifyListeners();
  }
}

/// 预算模式
enum BudgetMode {
  /// 沿用上月预算：总预算未设时自动沿用上月值，分类预算手动设置
  carryLastMonth,

  /// 按上月消费：分类预算取上月实际消费，总预算为各分类预算合计
  lastMonthSpend,
}
