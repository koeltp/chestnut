/// 账单类型枚举
///
/// 用 int 枚举而非字符串存储，保证数据库存储紧凑且类型安全。
enum BillType {
  /// 支出
  expense,

  /// 收入
  income,

  /// 转账（账户间划转 / 信用卡还款）：不计收支、无分类；
  /// assetId = 转出账户，toAssetId = 转入账户
  transfer;

  /// 中文名称，用于 UI 展示
  String get label => switch (this) {
    BillType.expense => '支出',
    BillType.income => '收入',
    BillType.transfer => '转账',
  };
}

/// 资产 / 负债类型枚举（与 BillType 同口径：int 枚举存储）
enum AssetKind {
  /// 资产（现金存款、房产、理财等）
  asset,

  /// 负债（房贷、车贷、借款等）
  liability;

  /// 中文名称，用于 UI 展示
  String get label => this == AssetKind.asset ? '资产' : '负债';
}

/// 借条方向枚举（与 BillType 同口径：int 枚举存储）
enum DebtDirection {
  /// 借出：钱借给了别人，别人欠我（计入我的资产）
  lendOut,

  /// 借入：别人借给了我，我欠别人（计入我的负债）
  borrowIn;

  /// 中文名称，用于 UI 展示
  String get label => this == DebtDirection.lendOut ? '借出' : '借入';
}

/// 账单图片上传状态
///
/// 双写架构下图片先落本地、再异步上传云端；失败不入后台队列，
/// 由每次启动的静默补传与详情页手动重传兜底。
enum BillImageUploadState {
  /// 待上传（本地已有，云端还没有）
  pending,

  /// 上传中
  uploading,

  /// 已上传
  done,

  /// 上传失败（网络/配置异常），等待补传
  failed,
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
