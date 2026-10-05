/// 账单列表日期分组头工具：点分日期 + 附加标签（近三天相对词/星期）
///
/// 年份按需显示：列表数据跨年时带年份消歧（如 2025.12.31 周三），
/// 同年内省略（如 09.29 周二）——与钱迹明细头一致。
/// 近三天用相对词（今天/昨天/前天）比星期更直觉，更早用星期。
class DateLabelUtil {
  /// 附加标签：近三天相对词，否则星期几
  static String tagOf(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final today = DateTime.now();
    final diff = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    return switch (diff) {
      0 => '今天',
      1 => '昨天',
      2 => '前天',
      _ => weekdays[date.weekday - 1],
    };
  }

  /// 分组头日期全文：跨年带年份（2025.12.31 周三），同年省略（09.29 周二）
  static String headOf(DateTime date, {required bool showYear}) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return "${showYear ? '${date.year}.' : ''}$mm.$dd ${tagOf(date)}";
  }
}
