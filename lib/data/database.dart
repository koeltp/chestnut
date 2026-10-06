import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/enums.dart';
import 'tables/bills.dart';
import 'tables/budgets.dart';
import 'tables/categories.dart';

part 'database.g.dart';

/// 当前数据库结构版本
///
/// 开发期 v1~v8 的历史迁移已在发布前整体重置归一，自 v1 起每次结构
/// 变更 +1；野外用户出现后版本号只增不减、迁移代码只增不删。
const int kSchemaVersion = 1;

/// 数据库主文件名（备份服务与启动恢复共用）
const String kDatabaseFileName = 'chestnut.sqlite';

/// WAL 模式附属文件：替换主库文件时必须一并删除，否则旧 WAL 内容
/// 会叠加到新主文件上导致数据库损坏
const List<String> kDatabaseSidecarFiles = [
  'chestnut.sqlite-wal',
  'chestnut.sqlite-shm',
];

/// 降级发生标记（SharedPreferences key）
///
/// 降级重建后 App 内数据被清空，用户极易误以为数据全丢；首页启动
/// 后检测此标记弹恢复引导，读取后即清除（只弹一次）。
const String kDowngradeDetectedKey = 'db_downgrade_detected';

/// 应用数据库
///
/// 单例式入口：负责建库、迁移与首次预置默认分类。
@DriftDatabase(tables: [Categories, Bills, Budgets])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection(kSchemaVersion));

  /// 仅测试使用：注入内存执行器，不落盘
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // 建库时预置内置分类（含子分类），避免新用户面对空分类列表
      await _seedDefaultCategories();
    },
    // 升级与降级统一在此处理（drift 把升降级都送进 onUpgrade）：
    // from > to 即降级——用户装回旧版 App，旧代码无法识别新结构，
    // drift 默认抛异常导致启动崩溃死循环，这里改为重建空库保证可用，
    // 高版本数据已在打开连接前由 _backupBeforeOpen 留底。
    // from < to 的正常升级暂无分支，未来结构变更时在这里追加。
    onUpgrade: (m, from, to) async {
      if (from > to) {
        // 删除所有实体（表/索引/触发器）后按当前代码结构重建
        for (final entity in allSchemaEntities) {
          await m.drop(entity);
        }
        await m.createAll();
        await _seedDefaultCategories();
        // 标记降级已发生，首页据此弹恢复引导（留底文件已在打开前生成）
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(kDowngradeDetectedKey, true);
        } catch (_) {
          // 标记失败只影响提示，不影响重建结果
        }
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
}

/// 数据库连接：后台线程执行 SQLite 操作，避免阻塞 UI 线程
///
/// 打开前先做版本预检（[schemaVersion] 由调用方传入）：升级与降级
/// 都先生成旧库快照，再交给 drift 正常打开。
LazyDatabase _openConnection(int schemaVersion) {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, kDatabaseFileName));
    await _backupBeforeOpen(file, schemaVersion);
    return NativeDatabase.createInBackground(file);
  });
}

/// drift 打开连接前的版本预检与快照备份
///
/// 此时库文件尚未被 drift 占用，VACUUM INTO 不受迁移事务限制：
/// · fileVersion < 代码版本：正常升级，备份旧库（保留最近 2 份），
///   迁移翻车时可回退；
/// · fileVersion > 代码版本：降级（装回旧版 App），高版本数据留底
///   后由 onUpgrade 的降级分支重建空库。
Future<void> _backupBeforeOpen(File file, int schemaVersion) async {
  if (!await file.exists()) return;
  Database? raw;
  try {
    raw = sqlite3.open(file.path);
    final fileVersion = raw.userVersion;
    // 0 = 未初始化的新文件，交给 drift 的 onCreate
    if (fileVersion == schemaVersion || fileVersion == 0) return;
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final name = fileVersion < schemaVersion
        ? 'chestnut_backup_v${fileVersion}_$stamp.sqlite'
        : 'chestnut_downgrade_v${fileVersion}_$stamp.sqlite';
    raw.execute("VACUUM INTO '${p.join(dir.path, name)}'");
    if (fileVersion < schemaVersion) _pruneOldBackups(dir);
  } catch (_) {
    // 预检/备份失败放行：升级有事务保护，降级仍有重建兜底
  } finally {
    raw?.dispose();
  }
}

/// 升级前备份只保留最近 [keep] 份（文件名含时间戳，字典序即时间序）
void _pruneOldBackups(Directory dir, {int keep = 2}) {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('chestnut_backup_v'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.length <= keep) return;
  for (final f in files.take(files.length - keep)) {
    try {
      f.deleteSync();
    } catch (_) {
      // 单个清理失败忽略
    }
  }
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
  _CategorySeed(   '餐饮',    Icons.restaurant,    0xFFFF9F43,    BillType.expense,    0,
    children: [      _CategorySeed(        '早餐',        Icons.free_breakfast,        0xFFFF9F43,        BillType.expense,        0,      ),
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
