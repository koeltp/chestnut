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

  /// 进入预算页时是否自动沿用上月预算（当月未设时）
  static const _kAutoBudgetCarryEnabled = 'auto_budget_carry_enabled';

  bool get autoBudgetCarryEnabled =>
      _prefs.getBool(_kAutoBudgetCarryEnabled) ?? false;

  /// 切换自动沿用上月预算开关
  Future<void> setAutoBudgetCarryEnabled(bool value) async {
    if (value == autoBudgetCarryEnabled) return;
    await _prefs.setBool(_kAutoBudgetCarryEnabled, value);
    notifyListeners();
  }
}
