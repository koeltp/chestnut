/// 账单类型枚举
///
/// 用 int 枚举而非字符串存储，保证数据库存储紧凑且类型安全。
enum BillType {
  /// 支出
  expense,

  /// 收入
  income;

  /// 中文名称，用于 UI 展示
  String get label => this == BillType.expense ? '支出' : '收入';
}

/// 首页查看模式（钱迹式"显示方式"）
enum HomePeriod {
  /// 按月查看
  month,

  /// 按年查看
  year,

  /// 全部数据
  all;

  /// 右上角切换入口显示文案
  String get label => switch (this) {
    HomePeriod.month => '按月',
    HomePeriod.year => '按年',
    HomePeriod.all => '全部',
  };
}
