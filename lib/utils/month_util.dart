/// 月份工具类
///
/// 预算表以 `yyyy-MM` 字符串为唯一键，此处统一转换逻辑，
/// 避免各处手写格式化导致键不一致。
class MonthUtil {
  MonthUtil._();

  /// 转为预算表使用的月份键，如 DateTime(2026, 9) -> "2026-09"
  static String toKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// 中文展示名，如 "2026年9月"
  static String displayName(DateTime date) => '${date.year}年${date.month}月';
}
