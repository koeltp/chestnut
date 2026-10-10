import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/asset_repository.dart';
import 'package:chestnut/data/repositories/bill_repository.dart';
import 'package:chestnut/data/repositories/debt_note_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 账单↔账户联动引擎回归测试：余额直改模型的核心不变量
///
/// 模型：账单保存/改/删直接增减账户余额（钱迹式），
/// 编辑做"撤销旧影响 + 应用新影响"的差值修正，删除做纯撤销。
/// 该模型一旦算错方向或漏撤销，用户看到的余额就会与真实流水漂移，
/// 且无法通过重新记账自愈——因此逐场景固化。
void main() {
  late AppDatabase db;
  late AssetRepository assetRepo;
  late BillRepository billRepo;
  late DebtNoteRepository debtRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    assetRepo = AssetRepository(db);
    billRepo = BillRepository(db);
    debtRepo = DebtNoteRepository(db);
    // 触发建库（含迁移与预置分类）
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  /// 建一个资产账户并返回实体（预置分类：资产=现金 / 负债=信用卡）
  Future<Asset> createAsset(
    String name, {
    AssetKind kind = AssetKind.asset,
    int valueCents = 10000,
  }) async {
    await assetRepo.insertAsset(
      name: name,
      kind: kind,
      category: kind == AssetKind.asset ? '现金' : '信用卡',
      valueCents: valueCents,
    );
    final all = await assetRepo.watchActive().first;
    return all.last;
  }

  /// 取一笔预置分类（支出的第一个一级分类）
  Future<Category> anyCategory(BillType type) async {
    final cats = await (db.select(
      db.categories,
    )..where((c) => c.type.equalsValue(type))).get();
    return cats.first;
  }

  /// 建一笔账单（[cat] 为 null = 转账等无分类场景）
  Future<int> addBill(
    BillType type,
    int amountCents, {
    Category? cat,
    int? assetId,
    int? toAssetId,
  }) => billRepo.addBill(
    BillsCompanion.insert(
      type: type,
      amountCents: amountCents,
      categoryId: Value(cat?.id),
      date: DateTime(2026, 10, 10),
      assetId: Value(assetId),
      toAssetId: Value(toAssetId),
    ),
  );

  Future<int> balanceOf(int assetId) async {
    final all = await assetRepo.watchActive().first;
    return all.firstWhere((a) => a.id == assetId).valueCents;
  }

  // ---------- 支出 / 收入联动 ----------

  test('支出账单：付款账户余额减少', () async {
    final asset = await createAsset('现金钱包');
    final cat = await anyCategory(BillType.expense);
    await addBill(BillType.expense, 500, cat: cat, assetId: asset.id);
    expect(await balanceOf(asset.id), 9500);
  });

  test('收入账单：收款账户余额增加', () async {
    final asset = await createAsset('工资卡');
    final cat = await anyCategory(BillType.income);
    await addBill(BillType.income, 3000, cat: cat, assetId: asset.id);
    expect(await balanceOf(asset.id), 13000);
  });

  test('不关联账户的账单：余额不动', () async {
    final asset = await createAsset('现金钱包');
    final cat = await anyCategory(BillType.expense);
    await addBill(BillType.expense, 500, cat: cat);
    expect(await balanceOf(asset.id), 10000);
  });

  test('编辑账单改金额：差值修正（撤销旧影响再应用新影响）', () async {
    final asset = await createAsset('现金钱包');
    final cat = await anyCategory(BillType.expense);
    final id = await addBill(BillType.expense, 500, cat: cat, assetId: asset.id);
    final bill = await (db.select(
      db.bills,
    )..where((b) => b.id.equals(id))).getSingle();
    await billRepo.updateBill(
      Bill(
        id: bill.id,
        type: bill.type,
        amountCents: 800,
        discountCents: bill.discountCents,
        categoryId: bill.categoryId,
        note: bill.note,
        date: bill.date,
        timeMinute: bill.timeMinute,
        location: bill.location,
        locationFull: bill.locationFull,
        lat: bill.lat,
        lng: bill.lng,
        assetId: bill.assetId,
        toAssetId: bill.toAssetId,
        createdAt: bill.createdAt,
      ),
    );
    expect(await balanceOf(asset.id), 9200);
  });

  test('编辑账单换账户：原账户恢复、新账户生效', () async {
    final assetA = await createAsset('现金钱包');
    final assetB = await createAsset('银行卡');
    final cat = await anyCategory(BillType.expense);
    final id = await addBill(BillType.expense, 500, cat: cat, assetId: assetA.id);
    final bill = await (db.select(
      db.bills,
    )..where((b) => b.id.equals(id))).getSingle();
    await billRepo.updateBill(
      Bill(
        id: bill.id,
        type: bill.type,
        amountCents: bill.amountCents,
        discountCents: bill.discountCents,
        categoryId: bill.categoryId,
        note: bill.note,
        date: bill.date,
        timeMinute: bill.timeMinute,
        location: bill.location,
        locationFull: bill.locationFull,
        lat: bill.lat,
        lng: bill.lng,
        assetId: assetB.id,
        toAssetId: bill.toAssetId,
        createdAt: bill.createdAt,
      ),
    );
    expect(await balanceOf(assetA.id), 10000);
    expect(await balanceOf(assetB.id), 9500);
  });

  test('删除账单：余额恢复原值', () async {
    final asset = await createAsset('现金钱包');
    final cat = await anyCategory(BillType.expense);
    final id = await addBill(BillType.expense, 500, cat: cat, assetId: asset.id);
    await billRepo.deleteBill(id);
    expect(await balanceOf(asset.id), 10000);
  });

  // ---------- 信用卡（负债）语义 ----------

  test('信用卡支出：欠款增加；信用卡收入（还款）：欠款减少可溢缴', () async {
    final card = await createAsset(
      '招行信用卡',
      kind: AssetKind.liability,
      valueCents: 3000,
    );
    final expenseCat = await anyCategory(BillType.expense);
    final incomeCat = await anyCategory(BillType.income);
    // 支出 → 欠款增加
    await addBill(BillType.expense, 500, cat: expenseCat, assetId: card.id);
    expect(await balanceOf(card.id), 3500);
    // 收入（如退款/还款）→ 欠款减少，可减至负数（溢缴款）
    await addBill(BillType.income, 6000, cat: incomeCat, assetId: card.id);
    expect(await balanceOf(card.id), -2500);
  });

  // ---------- 转账联动与统计口径 ----------

  test('转账账单：转出减、转入加，总额守恒', () async {
    final from = await createAsset('银行卡');
    final to = await createAsset('现金钱包');
    await addBill(
      BillType.transfer,
      1000,
      assetId: from.id,
      toAssetId: to.id,
    );
    expect(await balanceOf(from.id), 9000);
    expect(await balanceOf(to.id), 11000);
  });

  test('转账不计入收支汇总与月度趋势', () async {
    final from = await createAsset('银行卡');
    final to = await createAsset('现金钱包');
    final expenseCat = await anyCategory(BillType.expense);
    final incomeCat = await anyCategory(BillType.income);
    await addBill(BillType.expense, 500, cat: expenseCat, assetId: from.id);
    await addBill(BillType.income, 200, cat: incomeCat, assetId: to.id);
    await addBill(
      BillType.transfer,
      1000,
      assetId: from.id,
      toAssetId: to.id,
    );
    final summary = await billRepo
        .watchSummaryBetween(DateTime(2026, 10), DateTime(2026, 11))
        .first;
    expect(summary.expenseCents, 500);
    expect(summary.incomeCents, 200);
    // 趋势聚合：转账金额不得混进任一月的收/支
    final trend = await billRepo.watchMonthlyTrend(months: 6).first;
    final total = trend.fold<int>(
      0,
      (s, t) => s + t.expenseCents + t.incomeCents,
    );
    expect(total, 700);
  });

  test('账户流水流：支出/收入按 assetId、转账双向匹配', () async {
    final from = await createAsset('银行卡');
    final to = await createAsset('现金钱包');
    final expenseCat = await anyCategory(BillType.expense);
    await addBill(BillType.expense, 500, cat: expenseCat, assetId: from.id);
    await addBill(
      BillType.transfer,
      1000,
      assetId: from.id,
      toAssetId: to.id,
    );
    final fromBills = await billRepo.watchBillsOfAsset(from.id).first;
    final toBills = await billRepo.watchBillsOfAsset(to.id).first;
    expect(fromBills, hasLength(2)); // 支出 + 转出侧
    expect(toBills, hasLength(1)); // 转入侧
  });

  // ---------- 借条联动 ----------

  test('借条借出：关联账户余额减少；删除借条恢复', () async {
    final asset = await createAsset('现金钱包');
    await debtRepo.insertDebtNote(
      direction: DebtDirection.lendOut,
      personName: '张三',
      amountCents: 800,
      borrowedAt: DateTime(2026, 10, 10),
      relatedAssetId: asset.id,
    );
    expect(await balanceOf(asset.id), 9200);
    final note = (await debtRepo.watchAll().first).single;
    await debtRepo.deleteDebtNote(note);
    expect(await balanceOf(asset.id), 10000);
  });

  test('借条借入：关联账户余额增加；不关联账户则不动', () async {
    final asset = await createAsset('现金钱包');
    await debtRepo.insertDebtNote(
      direction: DebtDirection.borrowIn,
      personName: '李四',
      amountCents: 300,
      borrowedAt: DateTime(2026, 10, 10),
    );
    expect(await balanceOf(asset.id), 10000);
    await debtRepo.insertDebtNote(
      direction: DebtDirection.borrowIn,
      personName: '王五',
      amountCents: 500,
      borrowedAt: DateTime(2026, 10, 10),
      relatedAssetId: asset.id,
    );
    expect(await balanceOf(asset.id), 10500);
  });

  // ---------- 余额不足硬拦截 ----------

  test('支出余额不足：拦截且事务回滚（账单未落库、余额不变）', () async {
    final asset = await createAsset('现金钱包');
    final cat = await anyCategory(BillType.expense);
    await expectLater(
      addBill(BillType.expense, 20000, cat: cat, assetId: asset.id),
      throwsA(isA<InsufficientBalanceException>()),
    );
    expect(await balanceOf(asset.id), 10000);
    expect(await (db.select(db.bills).get()), isEmpty);
  });

  test('支出恰好扣到 0：放行', () async {
    final asset = await createAsset('现金钱包');
    final cat = await anyCategory(BillType.expense);
    await addBill(BillType.expense, 10000, cat: cat, assetId: asset.id);
    expect(await balanceOf(asset.id), 0);
  });

  test('转出余额不足：拦截，双方余额不变', () async {
    final from = await createAsset('银行卡');
    final to = await createAsset('现金钱包');
    await expectLater(
      addBill(BillType.transfer, 20000, assetId: from.id, toAssetId: to.id),
      throwsA(isA<InsufficientBalanceException>()),
    );
    expect(await balanceOf(from.id), 10000);
    expect(await balanceOf(to.id), 10000);
  });

  test('编辑账单使余额穿 0：拦截且整体回滚（旧账单保留原样）', () async {
    final asset = await createAsset('现金钱包');
    final cat = await anyCategory(BillType.expense);
    final id = await addBill(BillType.expense, 500, cat: cat, assetId: asset.id);
    final bill = await (db.select(
      db.bills,
    )..where((b) => b.id.equals(id))).getSingle();
    await expectLater(
      billRepo.updateBill(
        Bill(
          id: bill.id,
          type: bill.type,
          amountCents: 20000,
          discountCents: bill.discountCents,
          categoryId: bill.categoryId,
          note: bill.note,
          date: bill.date,
          timeMinute: bill.timeMinute,
          location: bill.location,
          locationFull: bill.locationFull,
          lat: bill.lat,
          lng: bill.lng,
          assetId: bill.assetId,
          toAssetId: bill.toAssetId,
          createdAt: bill.createdAt,
        ),
      ),
      throwsA(isA<InsufficientBalanceException>()),
    );
    // 整个事务回滚：余额停在旧影响之后，账单保持旧金额
    expect(await balanceOf(asset.id), 9500);
    final after = await (db.select(
      db.bills,
    )..where((b) => b.id.equals(id))).getSingle();
    expect(after.amountCents, 500);
  });

  test('删除收入账单：纠正操作不拦余额（可为负）', () async {
    final asset = await createAsset('现金钱包');
    final incomeCat = await anyCategory(BillType.income);
    final expenseCat = await anyCategory(BillType.expense);
    final incomeId = await addBill(
      BillType.income,
      200,
      cat: incomeCat,
      assetId: asset.id,
    );
    // 余额 10200 - 10100 = 100
    await addBill(BillType.expense, 10100, cat: expenseCat, assetId: asset.id);
    // 撤销收入：100 - 200 = -100，删除属纠正操作放行
    await billRepo.deleteBill(incomeId);
    expect(await balanceOf(asset.id), -100);
  });

  test('手动改值为负：拦截', () async {
    final asset = await createAsset('现金钱包');
    await expectLater(
      assetRepo.updateValue(asset, -1),
      throwsA(isA<InsufficientBalanceException>()),
    );
    expect(await balanceOf(asset.id), 10000);
  });

  test('借条借出余额不足：拦截且借条未落库', () async {
    final asset = await createAsset('现金钱包');
    await expectLater(
      debtRepo.insertDebtNote(
        direction: DebtDirection.lendOut,
        personName: '张三',
        amountCents: 20000,
        borrowedAt: DateTime(2026, 10, 10),
        relatedAssetId: asset.id,
      ),
      throwsA(isA<InsufficientBalanceException>()),
    );
    expect(await balanceOf(asset.id), 10000);
    expect(await debtRepo.watchAll().first, isEmpty);
  });
}

