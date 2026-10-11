import '../../data/database.dart';
import '../../models/enums.dart';
import '../../services/amap_service.dart';
import '../../utils/money_util.dart';

/// 记一笔页的"值草稿"：只装会被保存进账单的数据（类型/金额文本/分类/
/// 日期时间/账户/标签/备注/定位），不含控制器、流订阅、焦点等"活对象"。
///
/// 独立成类的目的：页面 State 只管生命周期与 UI，字段读写统一走 [_draft]；
/// 将来草稿箱/异常退出恢复等功能落地时，只需在此基础上补 toJson/fromJson，
/// 不必再从 State 里往外抠字段。
///
/// 金额说明：[amountText]/[discountText] 是页面输入态的"元"文本，
/// 保存时经 MoneyUtil 换算为分，全链路金额口径不变
class AddBillDraft {
  AddBillDraft({required this.date, required this.timeMinute});

  /// 账单类型；新建默认支出，编辑/复制由 [fromBill] 覆写
  BillType type = BillType.expense;

  /// 实付金额输入文本（元）；空 = 未输入
  String amountText = '';

  /// 优惠金额输入文本（元）；空 = 未设置优惠。仅支出账单可用
  String discountText = '';

  /// 已选分类 id；null = 未选（转账不计分类）
  int? selectedCategoryId;

  /// 账单日期
  DateTime date;

  /// 账单时间（当日 0..1439 分钟）
  int timeMinute;

  /// 关联账户（支出 = 付款账户，收入 = 收款账户，转账 = 转出账户）；
  /// null = 不关联（纯记账，余额不动）
  int? selectedAssetId;

  /// 转入账户（仅转账账单）：储蓄卡 → 信用卡即还款
  int? toAssetId;

  /// 已选标签 id 集合（空 = 未打标签）
  final Set<int> selectedTagIds = {};

  /// 备注文本；输入框控制器留在 State，用户键入经 onChanged 同步到这里
  String note = '';

  /// 定位地名；null = 未定位
  String? locationName;

  /// 定位完整信息（省市区街道 + 地点名），专供搜索字段 locationFull；
  /// 编辑时读旧账单回显，选点页无法补全时保留旧值兜底
  String? locationFull;

  /// 定位坐标（与地名一起保存，编辑时选点页据此回到原地点）
  Gcj02Point? selectedPoint;

  /// 从已有账单回填草稿：编辑/复制模式共用。
  /// [nowMinute] 兜底旧账单缺时间的情况（timeMinute 为 null 时用当前时刻）
  factory AddBillDraft.fromBill(Bill bill, {required int nowMinute}) {
    return AddBillDraft(date: bill.date, timeMinute: bill.timeMinute ?? nowMinute)
      ..type = bill.type
      // 零头为 0 时省略小数：用户输入整数保存，回填时不显示 xxx.00
      ..amountText = MoneyUtil.centsToYuanTrimmed(bill.amountCents)
      ..discountText = bill.discountCents == null
          ? ''
          : MoneyUtil.centsToYuanTrimmed(bill.discountCents!)
      ..selectedCategoryId = bill.categoryId
      ..note = bill.note ?? ''
      ..locationName = bill.location
      ..locationFull = bill.locationFull
      ..selectedAssetId = bill.assetId
      ..toAssetId = bill.toAssetId
      ..selectedPoint = (bill.lat != null && bill.lng != null)
          ? Gcj02Point(lat: bill.lat!, lng: bill.lng!)
          : null;
  }
}
