/// 全应用统一的年份可选范围
///
/// 记账/统计/日期滚轮等所有年份入口统一引用本常量，
/// 避免各处魔法数字漂移（此前滚轮写死 2010 年起，与其它入口不一致）。
abstract final class AppDate {
  /// 可选的最早年份
  static const int minYear = 1900;

  /// 可选的最晚年份（跟随设备当前日期，跨年后自动扩展）
  static int get maxYear => DateTime.now().year;
}
