import 'package:drift/drift.dart';

import '../../models/enums.dart';
import 'bills.dart';

/// 账单图片表：小票 / 发票等消费凭证
///
/// 双写架构：拍/选的图先压缩落本地缓存目录（离线可看、秒开），再异步
/// 上传到用户自配的 S3 兼容云存储；本地路径与云端 objectKey 同时持有，
/// 读取永远本地优先，缓存缺失时按 objectKey 从云端拉回。
@TableIndex(name: 'bill_images_bill', columns: {#billId})
class BillImages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属账单：删除账单时由仓储级联清理记录 / 本地文件 / 云端对象
  IntColumn get billId => integer().references(Bills, #id)();

  /// 云端对象键（bucket 内唯一路径），生成规则见 BillImageRepository
  TextColumn get objectKey => text()();

  /// 本地缓存文件绝对路径（应用支持目录 receipts/ 下）
  TextColumn get localPath => text()();

  /// 上传状态
  IntColumn get uploadState => intEnum<BillImageUploadState>()();

  /// 添加时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 同一账单内的展示顺序（按添加先后）
  IntColumn get sort => integer().withDefault(const Constant(0))();
}
