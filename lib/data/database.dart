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
  int get schemaVersion => 5;

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
        },
      );

  /// 预置默认分类（收支各一套，部分一级分类带子分类）
  Future<void> _seedDefaultCategories() async {
    for (final seed in _defaultCategories) {
      final parentId = await into(categories).insert(CategoriesCompanion.insert(
        name: seed.name,
        iconCode: seed.icon.codePoint,
        colorValue: seed.color,
        type: seed.type,
        sortOrder: Value(seed.sortOrder),
      ));
      final childRows = <CategoriesCompanion>[];
      for (var i = 0; i < seed.children.length; i++) {
        final child = seed.children[i];
        // 子分类颜色跟随父分类，保证饼图归并到一级时同色
        childRows.add(CategoriesCompanion.insert(
          name: child.name,
          iconCode: child.icon.codePoint,
          colorValue: child.color,
          type: child.type,
          parentId: Value(parentId),
          sortOrder: Value(i),
        ));
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
      final parents = await (select(categories)
            ..where((c) => c.name.equals(seed.name) & c.parentId.isNull()))
          .get();
      for (final parent in parents) {
        final existing = await (select(categories)
              ..where((c) => c.parentId.equals(parent.id)))
            .get();
        final names = existing.map((e) => e.name).toSet();
        final rows = <CategoriesCompanion>[];
        for (var i = 0; i < seed.children.length; i++) {
          final child = seed.children[i];
          if (names.contains(child.name)) continue;
          rows.add(CategoriesCompanion.insert(
            name: child.name,
            iconCode: child.icon.codePoint,
            colorValue: child.color,
            type: child.type,
            parentId: Value(parent.id),
            sortOrder: Value(i),
          ));
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
  // 支出分类
  _CategorySeed('餐饮', Icons.restaurant, 0xFFFF9F43, BillType.expense, 0, children: [
    _CategorySeed('早餐', Icons.free_breakfast, 0xFFFF9F43, BillType.expense, 0),
    _CategorySeed('午餐', Icons.lunch_dining, 0xFFFF9F43, BillType.expense, 1),
    _CategorySeed('晚餐', Icons.dinner_dining, 0xFFFF9F43, BillType.expense, 2),
    _CategorySeed('零食饮料', Icons.local_drink, 0xFFFF9F43, BillType.expense, 3),
  ]),
  _CategorySeed('交通', Icons.directions_subway, 0xFF54A0FF, BillType.expense, 1, children: [
    _CategorySeed('公交地铁', Icons.directions_bus, 0xFF54A0FF, BillType.expense, 0),
    _CategorySeed('打车', Icons.local_taxi, 0xFF54A0FF, BillType.expense, 1),
    _CategorySeed('加油', Icons.local_gas_station, 0xFF54A0FF, BillType.expense, 2),
  ]),
  _CategorySeed('购物', Icons.shopping_bag, 0xFFFF6B81, BillType.expense, 2, children: [
    _CategorySeed('日用品', Icons.shopping_basket, 0xFFFF6B81, BillType.expense, 0),
    _CategorySeed('服饰', Icons.checkroom, 0xFFFF6B81, BillType.expense, 1),
    _CategorySeed('数码', Icons.devices, 0xFFFF6B81, BillType.expense, 2),
  ]),
  _CategorySeed('居住', Icons.home, 0xFF8D6E63, BillType.expense, 3),
  _CategorySeed('娱乐', Icons.sports_esports, 0xFF9C88FF, BillType.expense, 4, children: [
    _CategorySeed('电影演出', Icons.movie, 0xFF9C88FF, BillType.expense, 0),
    _CategorySeed('游戏', Icons.videogame_asset, 0xFF9C88FF, BillType.expense, 1),
  ]),
  _CategorySeed('医疗', Icons.medical_services, 0xFF4CD7D0, BillType.expense, 5),
  _CategorySeed('教育', Icons.school, 0xFFFDCB6E, BillType.expense, 6),
  _CategorySeed('人情', Icons.card_giftcard, 0xFFFF8FAB, BillType.expense, 7),
  _CategorySeed('其他', Icons.more_horiz, 0xFFA8A8A8, BillType.expense, 8),
  // 收入分类
  _CategorySeed('工资', Icons.work, 0xFF4E9E5F, BillType.income, 0),
  _CategorySeed('奖金', Icons.emoji_events, 0xFFF39C12, BillType.income, 1),
  _CategorySeed('理财', Icons.trending_up, 0xFF27AE60, BillType.income, 2),
  _CategorySeed('红包', Icons.currency_yen, 0xFFE74C3C, BillType.income, 3),
  _CategorySeed('其他', Icons.more_horiz, 0xFFA8A8A8, BillType.income, 4),
];
