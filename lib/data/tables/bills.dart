import 'package:drift/drift.dart';

import '../../models/enums.dart';
import 'categories.dart';

/// 账单表
///
/// 金额以"分"（整数）存储，从根本上避免浮点精度误差；
/// 展示时统一除以 100 转为元。
class Bills extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 账单类型（支出 / 收入）
  IntColumn get type => intEnum<BillType>()();

  /// 金额，单位：分
  IntColumn get amountCents => integer()();

  /// 所属分类
  IntColumn get categoryId => integer().references(Categories, #id)();

  /// 备注，可为空
  TextColumn get note => text().nullable()();

  /// 账单归属日期（精确到日，统计按此分组）
  DateTimeColumn get date => dateTime()();

  /// 账单时间：当日 0..1439 分钟；null = 未指定（旧数据）
  IntColumn get timeMinute => integer().nullable()();

  /// 定位地名（反地理编码得到，如"广东省 深圳市 南山区 深南大道"）；null = 未定位
  TextColumn get location => text().nullable()();

  /// 定位完整信息（省市区街道 + 地点名全量拼接），专供搜索：
  /// POI 选点保存的 location 可能只有店名，此字段保证任何一段
  /// （省/市/区/街道/店名）都能被搜索命中；null = 未定位或旧数据
  TextColumn get locationFull => text().nullable()();

  /// 定位坐标（GCJ-02 纬度/经度）：编辑账单时让地图回到当时的地点；
  /// null = 未定位或行政区类地名（无精确坐标）
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();

  /// 创建时间，用于同一天内排序
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
