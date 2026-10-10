import 'package:drift/drift.dart';

import '../../models/enums.dart';
import 'assets.dart';

/// 借条表：借出 / 借入台账
///
/// 与 assets 表相互独立：assets 记"账户存量"，借条记"人际关系欠款"。
/// 借出（别人欠我）在净值聚合时并入资产侧，借入（我欠别人）并入负债侧，
/// 由 [includeInTotal] 控制单条借条是否参与统计。
/// 借据照片与账单图片同架构（debt_note_images 表，一借条多图）：
/// 本地缓存 + 云端双写（objectKey 指向用户自配的 S3 兼容存储），
/// 读取本地优先，缓存缺失时按 objectKey 拉回。
class DebtNotes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 方向：借出 / 借入
  IntColumn get direction => intEnum<DebtDirection>()();

  /// 借款人姓名（借出 = 对方名字；借入 = 出借人名字）
  TextColumn get personName => text()();

  /// 金额，单位：分（恒为正数，方向由 [direction] 区分）
  IntColumn get amountCents => integer()();

  /// 备注，可为空
  TextColumn get note => text().nullable()();

  /// 关联的资金类账户：借出 = 钱从此账户出（编辑时提示余额变化），
  /// 借入 = 钱累加到此账户；null = 不关联
  IntColumn get relatedAssetId => integer().nullable().references(Assets, #id)();

  /// 借款日期（含时间）
  DateTimeColumn get borrowedAt => dateTime()();

  /// 约定还款日期；null = 未约定
  DateTimeColumn get repayDueAt => dateTime().nullable()();

  /// 是否计入总借出/总借入：false = 仅台账记录，不参与净值统计
  BoolColumn get includeInTotal => boolean().withDefault(const Constant(true))();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 最近一次信息更新时间
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
