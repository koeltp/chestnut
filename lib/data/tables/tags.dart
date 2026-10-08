import 'package:drift/drift.dart';

import 'bills.dart';

/// 标签表
///
/// 标签是跨分类的"场景/项目"维度（如旅游、出差），一笔账单可挂多个
/// 标签。颜色用于列表/统计中视觉区分，与分类色独立。
@TableIndex(name: 'tags_name', columns: {#name})
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 标签名（唯一，查重由仓储保证）
  TextColumn get name => text()();

  /// 标签颜色（ARGB 整数），新建时自动按色板循环分配，可在管理页修改
  IntColumn get color => integer()();

  /// 排序权重（越小越靠前），新建时追加到末尾
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 账单-标签关联表（多对多）
///
/// 联合主键 (billId, tagId) 保证同一笔账单的同一标签不重复关联。
class BillTags extends Table {
  IntColumn get billId => integer().references(Bills, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {billId, tagId};
}
