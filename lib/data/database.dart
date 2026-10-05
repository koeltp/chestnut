import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/enums.dart';
import 'tables/bills.dart';
import 'tables/budgets.dart';
import 'tables/categories.dart';

part 'database.g.dart';

/// 应用数据库
///
/// 单例式入口：负责建库、迁移与首次预置默认分类。
@DriftDatabase(tables: [Categories, Bills, Budgets])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 仅测试使用：注入内存执行器，不落盘
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // 建库时预置内置分类（含子分类），避免新用户面对空分类列表
      await _seedDefaultCategories();
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2：分类表增加两级支持（parentId 列），并补预置子分类
      if (from < 2) {
        await m.addColumn(categories, categories.parentId);
        await _seedDefaultSubCategories();
      }
      // v2 → v3：账单表增加时间列（当日分钟数，可空）
      if (from < 3) {
        await m.addColumn(bills, bills.timeMinute);
      }
      // v3 → v4：账单表增加定位地名列（可空）
      if (from < 4) {
        await m.addColumn(bills, bills.location);
      }
      // v4 → v5：账单表增加定位坐标列（可空），编辑时地图回到原地点
      if (from < 5) {
        await m.addColumn(bills, bills.lat);
        await m.addColumn(bills, bills.lng);
      }
      // v5 → v6：账单表增加定位完整信息列（可空），专供搜索；
      // 历史账单回填现有 location（GPS 逆地理本就是完整地址）
      if (from < 6) {
        await m.addColumn(bills, bills.locationFull);
        await customStatement(
          "UPDATE bills SET location_full = location "
          "WHERE location IS NOT NULL",
        );
      }
      // v6 → v7：预算表支持分类预算——新增 category_id 列（0 = 总预算），
      // 唯一约束由 month 单列改为 (month, category_id) 组合。SQLite
      // 无法直接修改表约束，走"建新表 → 搬数据 → 换名"重建，旧预算
      // 全部作为总预算（category_id = 0）保留
      if (from < 7) {
        await customStatement(
          'CREATE TABLE budgets_new ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'month TEXT NOT NULL, '
          'amount_cents INTEGER NOT NULL, '
          'category_id INTEGER NOT NULL DEFAULT 0, '
          'UNIQUE (month, category_id))',
        );
        await customStatement(
          'INSERT INTO budgets_new (id, month, amount_cents, category_id) '
          'SELECT id, month, amount_cents, 0 FROM budgets',
        );
        await customStatement('DROP TABLE budgets');
        await customStatement('ALTER TABLE budgets_new RENAME TO budgets');
      }
      // v7 → v8：账单表加查询索引——月/年/全部查询按 date 范围
      // 过滤并按 (date, createdAt) 排序，分类详情页按 categoryId 过滤。
      // 纯索引变更无数据改写，建索引即可（onCreate 由 createAll 统一建）
      if (from < 8) {
        await m.createIndex(billsDateCreated);
        await m.createIndex(billsCategory);
      }
    },
  );

  /// 预置默认分类（收支各一套，部分一级分类带子分类）
  Future<void> _seedDefaultCategories() async {
    for (final seed in _defaultCategories) {
      final parentId = await into(categories).insert(
        CategoriesCompanion.insert(
          name: seed.name,
          iconCode: seed.icon.codePoint,
          colorValue: seed.color,
          type: seed.type,
          sortOrder: Value(seed.sortOrder),
        ),
      );
      final childRows = <CategoriesCompanion>[];
      for (var i = 0; i < seed.children.length; i++) {
        final child = seed.children[i];
        // 子分类颜色跟随父分类，保证饼图归并到一级时同色
        childRows.add(
          CategoriesCompanion.insert(
            name: child.name,
            iconCode: child.icon.codePoint,
            colorValue: child.color,
            type: child.type,
            parentId: Value(parentId),
            sortOrder: Value(i),
          ),
        );
      }
      if (childRows.isNotEmpty) {
        // drift 无单条 insertAll，批量插入统一走 batch
        await batch((b) => b.insertAll(categories, childRows));
      }
    }
  }

  /// 为已升级的旧库补充预置子分类（幂等：同父下同名子分类跳过）
  Future<void> _seedDefaultSubCategories() async {
    for (final seed in _defaultCategories) {
      if (seed.children.isEmpty) continue;
      // 按名称匹配旧库中的同名一级分类
      final parents = await (select(
        categories,
      )..where((c) => c.name.equals(seed.name) & c.parentId.isNull())).get();
      for (final parent in parents) {
        final existing = await (select(
          categories,
        )..where((c) => c.parentId.equals(parent.id))).get();
        final names = existing.map((e) => e.name).toSet();
        final rows = <CategoriesCompanion>[];
        for (var i = 0; i < seed.children.length; i++) {
          final child = seed.children[i];
          if (names.contains(child.name)) continue;
          rows.add(
            CategoriesCompanion.insert(
              name: child.name,
              iconCode: child.icon.codePoint,
              colorValue: child.color,
              type: child.type,
              parentId: Value(parent.id),
              sortOrder: Value(i),
            ),
          );
        }
        if (rows.isNotEmpty) {
          await batch((b) => b.insertAll(categories, rows));
        }
      }
    }
  }
}

/// 数据库连接：后台线程执行 SQLite 操作，避免阻塞 UI 线程
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'chestnut.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// 内置分类种子定义
class _CategorySeed {
  const _CategorySeed(
    this.name,
    this.icon,
    this.color,
    this.type,
    this.sortOrder, {
    this.children = const [],
  });

  final String name;
  final IconData icon;
  final int color;
  final BillType type;
  final int sortOrder;

  /// 子分类定义（颜色跟随父分类，仅在预置时使用）
  final List<_CategorySeed> children;
}

const _defaultCategories = <_CategorySeed>[
  // 支出分类：名称与图标均与编辑页图标库一一对应，子分类按高频排序
  _CategorySeed(
    '餐饮',
    Icons.restaurant,
    0xFFFF9F43,
    BillType.expense,
    0,
    children: [
      _CategorySeed(
        '早餐',
        Icons.free_breakfast,
        0xFFFF9F43,
        BillType.expense,
        0,
      ),
      _CategorySeed('午餐', Icons.rice_bowl, 0xFFFF9F43, BillType.expense, 1),
      _CategorySeed('晚餐', Icons.ramen_dining, 0xFFFF9F43, BillType.expense, 2),
      _CategorySeed(
        '买菜',
        Icons.shopping_basket,
        0xFFFF9F43,
        BillType.expense,
        3,
      ),
      _CategorySeed(
        '外卖',
        Icons.delivery_dining,
        0xFFFF9F43,
        BillType.expense,
        4,
      ),
      _CategorySeed('零食', Icons.icecream, 0xFFFF9F43, BillType.expense, 5),
      _CategorySeed('饮料', Icons.local_drink, 0xFFFF9F43, BillType.expense, 6),
      _CategorySeed(
        '下馆子',
        Icons.dinner_dining,
        0xFFFF9F43,
        BillType.expense,
        7,
      ),
    ],
  ),
  _CategorySeed(
    '交通',
    Icons.directions_subway,
    0xFF54A0FF,
    BillType.expense,
    1,
    children: [
      _CategorySeed(
        '公交',
        Icons.directions_bus,
        0xFF54A0FF,
        BillType.expense,
        0,
      ),
      _CategorySeed(
        '地铁',
        Icons.directions_subway,
        0xFF54A0FF,
        BillType.expense,
        1,
      ),
      _CategorySeed('打车', Icons.local_taxi, 0xFF54A0FF, BillType.expense, 2),
      _CategorySeed('停车', Icons.local_parking, 0xFF54A0FF, BillType.expense, 3),
      _CategorySeed(
        '加油',
        Icons.local_gas_station,
        0xFF54A0FF,
        BillType.expense,
        4,
      ),
      _CategorySeed('充电', Icons.ev_station, 0xFF54A0FF, BillType.expense, 5),
      _CategorySeed(
        '洗车',
        Icons.local_car_wash,
        0xFF54A0FF,
        BillType.expense,
        6,
      ),
      _CategorySeed('高速费', Icons.toll, 0xFF54A0FF, BillType.expense, 7),
      _CategorySeed('保养', Icons.build_circle, 0xFF54A0FF, BillType.expense, 8),
      _CategorySeed('单车', Icons.pedal_bike, 0xFF54A0FF, BillType.expense, 9),
      _CategorySeed('火车', Icons.train, 0xFF54A0FF, BillType.expense, 10),
      _CategorySeed('飞机', Icons.flight, 0xFF54A0FF, BillType.expense, 11),
    ],
  ),
  _CategorySeed(
    '购物',
    Icons.shopping_bag,
    0xFFFF6B81,
    BillType.expense,
    2,
    children: [
      _CategorySeed(
        '日用品',
        Icons.shopping_basket,
        0xFFFF6B81,
        BillType.expense,
        0,
      ),
      _CategorySeed('服饰', Icons.checkroom, 0xFFFF6B81, BillType.expense, 1),
      _CategorySeed('数码', Icons.devices, 0xFFFF6B81, BillType.expense, 2),
    ],
  ),
  _CategorySeed(
    '住房',
    Icons.home,
    0xFF8D6E63,
    BillType.expense,
    3,
    children: [
      _CategorySeed('房租', Icons.home, 0xFF8D6E63, BillType.expense, 0),
      _CategorySeed('物业', Icons.home_work, 0xFF8D6E63, BillType.expense, 1),
      _CategorySeed('电费', Icons.bolt, 0xFF8D6E63, BillType.expense, 2),
      _CategorySeed('水费', Icons.water_drop, 0xFF8D6E63, BillType.expense, 3),
      _CategorySeed(
        '天燃气',
        Icons.local_fire_department,
        0xFF8D6E63,
        BillType.expense,
        4,
      ),
      _CategorySeed(
        '房贷',
        Icons.real_estate_agent,
        0xFF8D6E63,
        BillType.expense,
        5,
      ),
    ],
  ),
  _CategorySeed(
    '日常',
    Icons.wb_sunny,
    0xFF0984E3,
    BillType.expense,
    4,
    children: [
      _CategorySeed('理发', Icons.content_cut, 0xFF0984E3, BillType.expense, 0),
      _CategorySeed('话费', Icons.smartphone, 0xFF0984E3, BillType.expense, 1),
      _CategorySeed(
        '快递',
        Icons.local_shipping,
        0xFF0984E3,
        BillType.expense,
        2,
      ),
      _CategorySeed('网费', Icons.wifi, 0xFF0984E3, BillType.expense, 3),
      _CategorySeed(
        '会员订阅',
        Icons.subscriptions,
        0xFF0984E3,
        BillType.expense,
        4,
      ),
    ],
  ),
  _CategorySeed(
    '娱乐',
    Icons.sports_esports,
    0xFF9C88FF,
    BillType.expense,
    5,
    children: [
      _CategorySeed('住宿', Icons.hotel, 0xFF9C88FF, BillType.expense, 0),
      _CategorySeed('景点', Icons.attractions, 0xFF9C88FF, BillType.expense, 1),
      _CategorySeed(
        '游戏',
        Icons.sports_esports,
        0xFF9C88FF,
        BillType.expense,
        2,
      ),
      _CategorySeed(
        '演出',
        Icons.theater_comedy,
        0xFF9C88FF,
        BillType.expense,
        3,
      ),
      _CategorySeed('电影', Icons.theaters, 0xFF9C88FF, BillType.expense, 4),
    ],
  ),
  _CategorySeed(
    '医疗',
    Icons.medical_services,
    0xFF4CD7D0,
    BillType.expense,
    6,
    children: [
      _CategorySeed('药品', Icons.medication, 0xFF4CD7D0, BillType.expense, 0),
      _CategorySeed(
        '医疗',
        Icons.medical_services,
        0xFF4CD7D0,
        BillType.expense,
        1,
      ),
      _CategorySeed(
        '体检',
        Icons.health_and_safety,
        0xFF4CD7D0,
        BillType.expense,
        2,
      ),
      _CategorySeed(
        '门诊',
        Icons.local_hospital,
        0xFF4CD7D0,
        BillType.expense,
        3,
      ),
    ],
  ),
  _CategorySeed(
    '人情',
    Icons.card_giftcard,
    0xFFFF8FAB,
    BillType.expense,
    7,
    children: [
      _CategorySeed(
        '孝敬',
        Icons.volunteer_activism,
        0xFFFF8FAB,
        BillType.expense,
        0,
      ),
      _CategorySeed(
        '份子钱',
        Icons.connect_without_contact,
        0xFFFF8FAB,
        BillType.expense,
        1,
      ),
      _CategorySeed('礼物', Icons.redeem, 0xFFFF8FAB, BillType.expense, 2),
      _CategorySeed('压岁钱', Icons.currency_yen, 0xFFFF8FAB, BillType.expense, 3),
    ],
  ),
  _CategorySeed(
    '教育',
    Icons.school,
    0xFFFDCB6E,
    BillType.expense,
    8,
    children: [
      _CategorySeed('学费', Icons.school, 0xFFFDCB6E, BillType.expense, 0),
      _CategorySeed('书本', Icons.menu_book, 0xFFFDCB6E, BillType.expense, 1),
      _CategorySeed(
        '培训',
        Icons.cast_for_education,
        0xFFFDCB6E,
        BillType.expense,
        2,
      ),
      _CategorySeed('文具', Icons.edit, 0xFFFDCB6E, BillType.expense, 3),
      _CategorySeed('网课', Icons.language, 0xFFFDCB6E, BillType.expense, 4),
    ],
  ),
  // 收入分类
  _CategorySeed('工资', Icons.work, 0xFF4E9E5F, BillType.income, 0),
  _CategorySeed('奖金', Icons.emoji_events, 0xFFF39C12, BillType.income, 1),
  _CategorySeed('理财', Icons.trending_up, 0xFF27AE60, BillType.income, 2),
  _CategorySeed('红包', Icons.currency_yen, 0xFFE74C3C, BillType.income, 3),
  _CategorySeed('其他', Icons.more_horiz, 0xFFA8A8A8, BillType.income, 4),
];
