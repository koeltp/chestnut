import 'package:drift/drift.dart';

import 'bills.dart';
import 'categories.dart';
import 'debt_notes.dart';

/// 借条还款分笔记录表
///
/// 一条借条可分多笔偿还（银行现金分期按月还、民间借贷分次收），
/// 每记一笔落一行；借条剩余欠款 = 主表 amountCents − Σ(还款额 − 利息)，
/// 纯派生不落库，主表原始金额始终保留。
///
/// 余额联动口径（与借条主表的"保存时联动关联账户"一致）：
/// · 本金部分（还款额 − 利息）：直接增减关联账户余额（借入还款 = 钱出，
///   借出收款 = 钱回），并在删除时做反向撤销；
/// · 利息部分（interestCents 非空时）：生成一条支出账单（挂关联账户、
///   带分类），余额影响与明细展示全部复用账单既有链路，
///   删除还款时级联删账单（interestBillId 反查）。
@TableIndex(name: 'debt_note_repayments_note', columns: {#noteId})
class DebtNoteRepayments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属借条；借条删除时级联删除全部还款记录
  IntColumn get noteId => integer().references(DebtNotes, #id)();

  /// 本次还款总额，单位：分（本金 + 利息；借出方向收款恒等于本金）
  IntColumn get amountCents => integer()();

  /// 其中利息，单位：分；null = 未拆分（整笔都冲借条余额）。
  /// 仅借入方向（还银行分期等）在 UI 上提供拆分，借出收款恒为 null
  IntColumn get interestCents => integer().nullable()();

  /// 利息支出账单的分类；null = 未拆分利息或用户未选
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();

  /// 利息支出账单 id：删除还款时级联删账单（账单联动随之自动撤销）
  IntColumn get interestBillId => integer().nullable().references(Bills, #id)();

  /// 备注，可为空
  TextColumn get note => text().nullable()();

  /// 还款时间（含时刻）：明细混排按此排序与日分组
  DateTimeColumn get repaidAt => dateTime()();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
