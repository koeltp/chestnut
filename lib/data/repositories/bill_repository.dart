import 'package:drift/drift.dart';

import '../database.dart';
import '../../models/enums.dart';
import '../../models/summaries.dart';

/// 账单仓储：封装账单相关的全部数据访问，UI 与 Provider 不直接接触 SQL
class BillRepository {
  BillRepository(this._db);

  final AppDatabase _db;

  /// 查询某月的全部账单（按日期倒序，同日按创建时间倒序）
  Stream<List<Bill>> watchBillsInMonth(DateTime month) {
    return watchBillsBetween(
      DateTime(month.year, month.month),
      DateTime(month.year, month.month + 1),
    );
  }

  /// 查询某年的全部账单（按日期倒序，同日按创建时间倒序）
  Stream<List<Bill>> watchBillsInYear(int year) {
    return watchBillsBetween(DateTime(year), DateTime(year + 1));
  }

  /// 查询全部账单（按日期倒序，同日按创建时间倒序）
  Stream<List<Bill>> watchAllBills() {
    return (_db.select(_db.bills)..orderBy([
          (b) => OrderingTerm.desc(b.date),
          (b) => OrderingTerm.desc(b.createdAt),
        ]))
        .watch();
  }

  /// 某分类（含其全部子分类）的账单流（分类统计详情页）
  ///
  /// 一级分类的账单可能挂在子分类上，用子查询把子分类账单一并取回，
  /// 与统计页"子类金额归并父类"的聚合口径一致。
  Stream<List<Bill>> watchBillsInCategory(int categoryId) {
    final subIds = _db.selectOnly(_db.categories)
      ..addColumns([_db.categories.id])
      ..where(_db.categories.parentId.equals(categoryId));
    return (_db.select(_db.bills)
          ..where(
            (b) =>
                b.categoryId.equals(categoryId) |
                b.categoryId.isInQuery(subIds),
          )
          ..orderBy([
            (b) => OrderingTerm.desc(b.date),
            (b) => OrderingTerm.desc(b.createdAt),
          ]))
        .watch();
  }

  /// 查询时间区间 [start, end) 内的账单（按日期倒序，同日按创建时间倒序）
  ///
  /// 注意不能用 isBetweenValues（闭区间）：上界必须排除，
  /// 否则查 9 月时会把 10 月 1 日的账单（date 为当日 0 点）一并带出。
  Stream<List<Bill>> watchBillsBetween(DateTime start, DateTime end) {
    return (_db.select(_db.bills)
          ..where(
            (b) =>
                b.date.isBiggerOrEqualValue(start) &
                b.date.isSmallerThanValue(end),
          )
          ..orderBy([
            (b) => OrderingTerm.desc(b.date),
            (b) => OrderingTerm.desc(b.createdAt),
          ]))
        .watch();
  }

  /// 某月收支汇总（一条 SQL 按类型分组完成）
  Stream<MonthSummary> watchMonthSummary(DateTime month) {
    return watchSummaryBetween(
      DateTime(month.year, month.month),
      DateTime(month.year, month.month + 1),
    );
  }

  /// 某年收支汇总
  Stream<MonthSummary> watchYearSummary(int year) {
    return watchSummaryBetween(DateTime(year), DateTime(year + 1));
  }

  /// 全部账单收支汇总
  Stream<MonthSummary> watchAllSummary() {
    return watchSummaryBetween(DateTime(1970), DateTime(9999));
  }

  /// 时间区间 [start, end) 收支汇总（月/年/全部共用实现）
  ///
  /// 上界排除（与账单查询一致），避免把下期首日计入本期。
  Stream<MonthSummary> watchSummaryBetween(DateTime start, DateTime end) {
    final sum = _db.bills.amountCents.sum();
    final query = _db.selectOnly(_db.bills)
      ..addColumns([_db.bills.type, sum])
      ..where(
        _db.bills.date.isBiggerOrEqualValue(start) &
            _db.bills.date.isSmallerThanValue(end),
      )
      ..groupBy([_db.bills.type]);

    return query.watch().map((rows) {
      var expense = 0;
      var income = 0;
      for (final row in rows) {
        final total = row.read(sum) ?? 0;
        // intEnum 列在 selectOnly 聚合场景读出的是原始 int，与枚举 index 比较
        if (row.read(_db.bills.type) == BillType.expense.index) {
          expense = total;
        } else {
          income = total;
        }
      }
      return MonthSummary(expenseCents: expense, incomeCents: income);
    });
  }

  /// 按一级分类聚合某月账单金额（统计页）
  ///
  /// 两级分类下账单可能挂在子分类上，统计时通过
  /// `coalesce(parent_id, id)` join 回一级分类，实现子类金额归并到父类。
  Stream<List<CategorySummary>> watchCategorySummary(
    BillType type,
    DateTime month,
  ) => watchCategorySummaryBetween(
    type,
    DateTime(month.year, month.month),
    DateTime(month.year, month.month + 1),
  );

  /// 按一级分类聚合账单金额（统计页），[start]/[end] 为左闭右开区间，
  /// 传 null 表示该侧不限（按年传全年区间，全部传双 null）
  Stream<List<CategorySummary>> watchCategorySummaryBetween(
    BillType type,
    DateTime? start,
    DateTime? end,
  ) {
    final sum = _db.bills.amountCents.sum();
    final parent = _db.alias(_db.categories, 'parent');
    final rootId = coalesce([_db.categories.parentId, _db.categories.id]);
    final query =
        _db.selectOnly(_db.bills).join([
            innerJoin(
              _db.categories,
              _db.categories.id.equalsExp(_db.bills.categoryId),
            ),
            innerJoin(parent, parent.id.equalsExp(rootId)),
          ])
          ..addColumns([
            parent.id,
            parent.name,
            parent.iconCode,
            parent.colorValue,
            sum,
          ])
          ..where(
            // 日期条件按需拼接：null 表示该侧不限，避免恒真表达式
            _db.bills.type.equals(type.index) &
                (start == null
                    ? const Constant(true)
                    : _db.bills.date.isBiggerOrEqualValue(start)) &
                (end == null
                    ? const Constant(true)
                    : _db.bills.date.isSmallerThanValue(end)),
          )
          ..groupBy([parent.id])
          ..orderBy([OrderingTerm.desc(sum)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return CategorySummary(
          categoryId: row.read(parent.id)!,
          name: row.read(parent.name)!,
          iconCode: row.read(parent.iconCode)!,
          colorValue: row.read(parent.colorValue)!,
          type: type,
          totalCents: row.read(sum) ?? 0,
        );
      }).toList();
    });
  }

  /// 近 [months] 个月的收支趋势（统计页折线图）
  ///
  /// 数据量在个人记账场景下很小，直接取明细后在 Dart 端按月聚合，
  /// 避免依赖数据库方言的日期函数。
  Stream<List<MonthlyTrend>> watchMonthlyTrend({int months = 6}) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - (months - 1));
    return (_db.select(_db.bills)
          ..where(
            (b) =>
                b.date.isBiggerOrEqualValue(start) &
                b.date.isSmallerThanValue(now),
          )
          ..orderBy([(b) => OrderingTerm.asc(b.date)]))
        .watch()
        .map((list) {
          // 以月份为 key 聚合
          final map = <String, MonthlyTrend>{};
          // 先补齐没有账单的月份，保证折线连续
          for (var i = 0; i < months; i++) {
            final m = DateTime(now.year, now.month - (months - 1) + i);
            final key = '${m.year}-${m.month}';
            map[key] = MonthlyTrend(
              year: m.year,
              month: m.month,
              expenseCents: 0,
              incomeCents: 0,
            );
          }
          for (final bill in list) {
            final key = '${bill.date.year}-${bill.date.month}';
            final old = map[key];
            if (old == null) continue;
            if (bill.type == BillType.expense) {
              map[key] = MonthlyTrend(
                year: old.year,
                month: old.month,
                expenseCents: old.expenseCents + bill.amountCents,
                incomeCents: old.incomeCents,
              );
            } else {
              map[key] = MonthlyTrend(
                year: old.year,
                month: old.month,
                expenseCents: old.expenseCents,
                incomeCents: old.incomeCents + bill.amountCents,
              );
            }
          }
          return map.values.toList();
        });
  }

  /// 新增账单
  Future<int> addBill(BillsCompanion entry) =>
      _db.into(_db.bills).insert(entry);

  /// 更新账单（返回受影响行数）
  ///
  /// 必须用显式 Companion 而非直接 write(bill)：drift 的
  /// DataClass.toCompanion(true) 会把 null 字段转为 absent（UPDATE SET
  /// 不含该列），导致编辑账单清除位置（location/lat/lng 置 NULL）静默失效
  Future<int> updateBill(Bill bill) =>
      (_db.update(_db.bills)..where((b) => b.id.equals(bill.id))).write(
        BillsCompanion(
          type: Value(bill.type),
          amountCents: Value(bill.amountCents),
          categoryId: Value(bill.categoryId),
          note: Value(bill.note),
          date: Value(bill.date),
          timeMinute: Value(bill.timeMinute),
          location: Value(bill.location),
          locationFull: Value(bill.locationFull),
          lat: Value(bill.lat),
          lng: Value(bill.lng),
        ),
      );

  /// 删除账单
  Future<int> deleteBill(int id) =>
      (_db.delete(_db.bills)..where((b) => b.id.equals(id))).go();

  /// 查询全部账单（CSV 导出用）
  Future<List<Bill>> getAllBills() => _db.select(_db.bills).get();
}
