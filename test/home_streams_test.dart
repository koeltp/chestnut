import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/bill_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页数据流回归测试：按月/按年/全部三种模式必须都能查到数据
///
/// 背景：用户反馈"点击全部没有任何数据，按年/按月也是"。
/// 本测试直接在内存库上验证仓储层三种模式的查询结果。
void main() {
  late AppDatabase db;
  late BillRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BillRepository(db);
    // 建库（含预置分类）
    await db.customSelect('SELECT 1').get();
    final cat = await (db.select(db.categories)
          ..where((c) => c.type.equalsValue(BillType.expense)))
        .get();
    final categoryId = cat.first.id;
    // 插入 2026-09-02 与 2026-10-01 两笔支出（对应用户场景）
    await repo.addBill(BillsCompanion.insert(
      categoryId: categoryId,
      type: BillType.expense,
      amountCents: 500,
      date: DateTime(2026, 9, 2),
      note: const Value('测试9月'),
    ));
    await repo.addBill(BillsCompanion.insert(
      categoryId: categoryId,
      type: BillType.expense,
      amountCents: 300,
      date: DateTime(2026, 10, 1),
      note: const Value('测试10月'),
    ));
  });

  tearDown(() => db.close());

  test('按月：能查到 2026-09 的账单', () async {
    final bills = await repo.watchBillsInMonth(DateTime(2026, 9)).first;
    expect(bills, hasLength(1));
    expect(bills.first.date.month, 9);
  });

  test('按年：能查到 2026 年全部账单', () async {
    final bills = await repo.watchBillsInYear(2026).first;
    expect(bills, hasLength(2));
  });

  test('全部：能查到所有账单', () async {
    final bills = await repo.watchAllBills().first;
    expect(bills, hasLength(2));
  });

  test('汇总：全部模式支出金额正确', () async {
    final summary = await repo.watchAllSummary().first;
    expect(summary.expenseCents, 800);
  });

  test('汇总：按年模式支出金额正确', () async {
    final summary = await repo.watchYearSummary(2026).first;
    expect(summary.expenseCents, 800);
  });
}
