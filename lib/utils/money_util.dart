/// 金额工具类
///
/// 全应用统一以"分"（int）存储金额，此处集中处理分与元之间的转换，
/// 避免散落在 UI 中的重复换算与精度问题。
class MoneyUtil {
  MoneyUtil._();

  /// 分转元字符串，如 12345 -> "123.45"；零头为 0 时保留两位小数
  static String centsToYuan(int cents) => _format(cents, grouped: false);

  /// 分转元字符串，零头为 0 时省略小数部分（如 12300 -> "123"、12345
  /// -> "123.45"），跟随用户输入习惯，避免明明输入整数却看到 xxx.00
  static String centsToYuanTrimmed(int cents) =>
      _format(cents, grouped: false, trimFen: true);

  /// 格式化展示金额，带千分位，如 1234567 分 -> "12,345.67"
  static String centsToYuanGrouped(int cents) => _format(cents, grouped: true);

  /// 千分位 + 零头为 0 省略小数，如 1200000 分 -> "12,000"
  static String centsToYuanGroupedTrimmed(int cents) =>
      _format(cents, grouped: true, trimFen: true);

  /// 统一格式化实现：[grouped] 千分位分组；[trimFen] 零头为 0 时省略小数
  static String _format(
    int cents, {
    required bool grouped,
    bool trimFen = false,
  }) {
    final negative = cents < 0;
    final abs = cents.abs();
    final yuan = abs ~/ 100;
    final fen = abs % 100;
    final yuanStr = grouped
        ? yuan.toString().replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+$)'),
            (m) => '${m[1]},',
          )
        : '$yuan';
    if (trimFen && fen == 0) return '${negative ? '-' : ''}$yuanStr';
    final fenStr = fen.toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$yuanStr.$fenStr';
  }

  /// 元字符串转分；输入必须为合法数字（最多两位小数），非法返回 null
  static int? yuanToCents(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value < 0) return null;
    // 乘 100 后四舍五入，规避 double 运算的精度误差
    return (value * 100).round();
  }
}
