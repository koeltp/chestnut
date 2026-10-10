import 'package:chestnut/data/database.dart';
import 'package:chestnut/models/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// v8 → v9 迁移回归测试：记账联动账户改造
///
/// v9 变更：bills 加 assetId/toAssetId 两列（可空），categoryId
/// 由 NOT NULL 改为可空（转账无分类语义）。
/// 用手写 v8 结构的内存库验证：真实用户库从 v8 升级后旧数据完整、
/// 新列可用、无分类账单可以插入。
void main() {
  test('v8 → v9：新增账户列、categoryId 改可空、旧数据保留', () async {
    // 手工搭 v8 结构的最小库（v9 迁移只触碰 bills 表，
    // categories/assets 为外键引用目标，建最小骨架即可）
    final v8 = NativeDatabase.memory(
      setup: (raw) {
        raw.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            icon_code INTEGER NOT NULL,
            color_value INTEGER NOT NULL,
            type INTEGER NOT NULL,
            parent_id INTEGER NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        raw.execute('''
          CREATE TABLE assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind INTEGER NOT NULL,
            category TEXT NOT NULL,
            value_cents INTEGER NOT NULL,
            note TEXT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0,
            include_in_net INTEGER NOT NULL DEFAULT 1,
            credit_limit_cents INTEGER NULL,
            bill_day INTEGER NULL,
            repay_day INTEGER NULL,
            created_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // v8 的 bills：category_id NOT NULL、无 asset_id/to_asset_id
        raw.execute('''
          CREATE TABLE bills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type INTEGER NOT NULL,
            amount_cents INTEGER NOT NULL,
            discount_cents INTEGER NULL,
            category_id INTEGER NOT NULL REFERENCES categories (id),
            note TEXT NULL,
            date INTEGER NOT NULL,
            time_minute INTEGER NULL,
            location TEXT NULL,
            location_full TEXT NULL,
            lat REAL NULL,
            lng REAL NULL,
            created_at INTEGER NOT NULL DEFAULT 0,
            import_batch_id INTEGER NULL
          )
        ''');
        // 外键引用目标各一行，转账账单的 assetId/toAssetId 指向资产
        raw.execute(
          "INSERT INTO categories (name, icon_code, color_value, type) "
          "VALUES ('餐饮', 100, 4280394, 0)",
        );
        raw.execute(
          "INSERT INTO assets (name, kind, category, value_cents) "
          "VALUES ('现金钱包', 0, '现金', 10000)",
        );
        // 一笔 v8 旧支出（带分类）
        raw.execute(
          "INSERT INTO bills (type, amount_cents, category_id, date) "
          "VALUES (0, 500, 1, strftime('%s', '2026-09-02'))",
        );
        raw.execute('PRAGMA user_version = 8');
      },
    );

    final db = AppDatabase.forTesting(v8);
    // 惰性打开：任一查询触发建库/迁移
    await db.customSelect('SELECT 1').get();

    // 版本已推进到 10
    final version =
        (await db.customSelect('PRAGMA user_version').get()).single;
    expect(version.data['user_version'], 10);

    // 列结构：两个新列存在，category_id 变为可空
    final cols = await db.customSelect('PRAGMA table_info(bills)').get();
    final names = cols.map((r) => r.data['name'] as String).toList();
    expect(names, containsAll(['asset_id', 'to_asset_id']));
    final catCol = cols.singleWhere((r) => r.data['name'] == 'category_id');
    expect(catCol.data['notnull'], 0);

    // 旧数据完整保留（半迁移中断重跑不丢数据的前提）
    final old = await db.select(db.bills).get();
    expect(old, hasLength(1));
    expect(old.single.amountCents, 500);
    expect(old.single.categoryId, 1);
    expect(old.single.assetId, isNull);
    expect(old.single.toAssetId, isNull);

    // 可空生效：转账账单无分类可正常插入，账户列可写入
    await db.into(db.bills).insert(
      BillsCompanion.insert(
        type: BillType.transfer,
        amountCents: 1000,
        date: DateTime(2026, 10, 10),
        assetId: const Value(1),
        toAssetId: const Value(1),
      ),
    );
    final after = await db.select(db.bills).get();
    expect(after, hasLength(2));
    final transfer = after.last;
    expect(transfer.categoryId, isNull);
    expect(transfer.assetId, 1);
    expect(transfer.toAssetId, 1);

    await db.close();
  });
}
