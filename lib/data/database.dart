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
import 'tables/assets.dart';
import 'tables/bill_images.dart';
import 'tables/bills.dart';
import 'tables/budgets.dart';
import 'tables/categories.dart';
import 'tables/debt_note_images.dart';
import 'tables/debt_notes.dart';
import 'tables/tags.dart';

part 'database.g.dart';

/// 当前数据库结构版本
///
/// 开发期历史迁移已在发布前整体重置归一，自 v1 起每次结构
/// 变更 +1；野外用户出现后版本号只增不减、迁移代码只增不删。
const int kSchemaVersion = 10;

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
@DriftDatabase(tables: [
  Categories,
  Bills,
  Budgets,
  Tags,
  BillTags,
  BillImages,
  Assets,
  AssetSnapshots,
  DebtNotes,
  DebtNoteImages,
])
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
    // from < to 的正常升级走 else 分支，逐版本追加列迁移。
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
      } else {
        // 正常升级：迁移只增不删。可空列直接 ADD COLUMN，
        // 旧账单优惠额为 null（未使用优惠）
        if (from < 2) {
          await m.addColumn(bills, bills.discountCents);
        }
        // 钱迹导入：批次号列（可空，手动记账与旧数据均为 null）
        if (from < 3) {
          await m.addColumn(bills, bills.importBatchId);
        }
        // 标签功能：新增 tags 与 bill_tags 两表（多对多关联）
        if (from < 4) {
          await m.createTable(tags);
          await m.createTable(billTags);
        }
        // 账单图片：新增 bill_images 表（小票/发票凭证）。
        // 注意 @TableIndex 声明的索引不随 createTable 创建，需显式建索引
        if (from < 5) {
          await m.createTable(billImages);
          await m.createIndex(billImagesBill);
        }
        // 资产管理：新增 assets 与 asset_snapshots 两表（净资产盘点）。
        // 索引同理需随迁移显式创建
        if (from < 6) {
          await m.createTable(assets);
          await m.createTable(assetSnapshots);
          await m.createIndex(assetSnapshotsAssetDay);
        }
        // 资产管理 v2（钱迹式）：assets 加净值开关与信用卡字段，
        // 新增借条表 debt_notes；旧资产分类名映射到新分类体系。
        // 全部做幂等保护：若上次迁移半途中断（列已加、版本号未落），
        // 重复 ADD COLUMN 会报 duplicate column 导致 App 不可用
        if (from < 7) {
          await _ensureColumn(m, assets, assets.includeInNet);
          await _ensureColumn(m, assets, assets.creditLimitCents);
          await _ensureColumn(m, assets, assets.billDay);
          await _ensureColumn(m, assets, assets.repayDay);
          if (!await _tableExists('debt_notes')) {
            await m.createTable(debtNotes);
          }
          await _migrateLegacyAssetCategories();
        }
        // 借据照片云端双写：debt_notes 补云端对象键与上传状态列。
        // 幂等加列（原生 SQL：这三列已从 drift 表定义移除，
        // v10 借据多图改造后不再由 drift 管理）
        if (from < 8) {
          await _ensureRawColumn(
            'debt_notes',
            'object_key',
            'object_key TEXT NULL',
          );
          await _ensureRawColumn(
            'debt_notes',
            'upload_state',
            'upload_state INTEGER NOT NULL DEFAULT 0',
          );
        }
        // 记账联动账户：bills 加 assetId/toAssetId 两列，categoryId 改可空
        // （转账无分类语义）。SQLite 无法直接改列约束，用 TableMigration
        // 重建 bills 表（索引随迁移一并重建）；加列走幂等 _ensureColumn。
        // 注意 categoryId 不能放 newColumns——那是"旧表不存在的新列"语义，
        // 复制数据时会被填 NULL 而非拷贝旧值；空迁移即按新定义重建并复制全部旧列
        if (from < 9) {
          await _ensureColumn(m, bills, bills.assetId);
          await _ensureColumn(m, bills, bills.toAssetId);
          await m.alterTable(
            // ignore: experimental_member_use
            TableMigration(bills),
          );
        }
        // 借据照片改多图：新增 debt_note_images 表（与 bill_images 同构）。
        // 先把旧单图三列（photo_path/object_key/upload_state）的数据迁入
        // 新表，再重建 debt_notes 去掉这三列（SQLite 无法直接删列）。
        // 注意 TableMigration 按新旧表同名列复制数据，借条主键 id 原样保留
        if (from < 10) {
          await m.createTable(debtNoteImages);
          await m.createIndex(debtNoteImagesNote);
          if (await _tableExists('debt_notes')) {
            // 旧结构才有单图列（当前代码建的表已无 photo_path，直接跳过）
            final noteCols = (await customSelect(
              'PRAGMA table_info([debt_notes])',
            ).get()).map((r) => r.data['name'] as String).toSet();
            if (noteCols.contains('photo_path')) {
              final legacy = await customSelect(
                'SELECT id, photo_path, object_key, upload_state '
                'FROM debt_notes WHERE photo_path IS NOT NULL',
              ).get();
              for (final row in legacy) {
                final state = (row.data['upload_state'] as int?) ?? 0;
                await into(debtNoteImages).insert(
                  DebtNoteImagesCompanion.insert(
                    noteId: row.data['id'] as int,
                    objectKey: (row.data['object_key'] as String?) ?? '',
                    localPath: row.data['photo_path'] as String,
                    uploadState: BillImageUploadState.values[state],
                  ),
                );
              }
            }
            await m.alterTable(
              // ignore: experimental_member_use
              TableMigration(debtNotes),
            );
          } else {
            // 极端情况兜底：库中缺 debt_notes（如测试最小骨架）按新定义补建
            await m.createTable(debtNotes);
          }
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

  /// 列存在才补差量的安全加列：列已在（半迁移中间态）时跳过
  Future<void> _ensureColumn(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final rows = await customSelect(
      'PRAGMA table_info([${table.actualTableName}])',
    ).get();
    final exists = rows.any((r) => r.data['name'] == column.$name);
    if (!exists) {
      await m.addColumn(table, column);
    }
  }

  /// 判断表是否已存在（迁移幂等检查用）
  Future<bool> _tableExists(String name) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable(name)],
    ).get();
    return rows.isNotEmpty;
  }

  /// 列存在才补差量的原生 SQL 加列：列已在（半迁移中间态）时跳过。
  /// 供已从 drift 表定义移除的历史列使用（v10 借据多图改造），
  /// drift 不再认识这些列，只能走原生 DDL
  Future<void> _ensureRawColumn(
    String table,
    String name,
    String definition,
  ) async {
    final rows = await customSelect('PRAGMA table_info([$table])').get();
    final exists = rows.any((r) => r.data['name'] == name);
    if (!exists) {
      await customStatement('ALTER TABLE $table ADD COLUMN $definition');
    }
  }

  /// v7 迁移：旧资产分类名映射到钱迹式新分类体系
  ///
  /// 持久化只存分类名（无分类 ID），分类体系重构后旧数据按 kind 分别
  /// 映射：资产侧旧名 → 新名；负债侧"借款/其他"统一并入"其它负债"
  /// 承接（房贷/车贷新名不变，无需处理）。
  Future<void> _migrateLegacyAssetCategories() async {
    const assetRenames = <String, String>{
      '现金存款': '现金',
      '金融理财': '其它理财',
      '其他': '其它',
    };
    for (final entry in assetRenames.entries) {
      await customUpdate(
        "UPDATE assets SET category = ? WHERE category = ? AND kind = 0",
        variables: [Variable(entry.value), Variable(entry.key)],
      );
    }
    await customUpdate(
      "UPDATE assets SET category = '其它负债' WHERE category IN ('借款', '其他') AND kind = 1",
    );
  }
}

/// 各类历史备份文件的文件名前缀（与 BackupService 的类型识别约定一致）
const _kUpgradeBackupPrefix = 'chestnut_backup_v';
const _kDowngradeBackupPrefix = 'chestnut_downgrade_';

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
        ? '$_kUpgradeBackupPrefix${fileVersion}_$stamp.sqlite'
        : '${_kDowngradeBackupPrefix}v${fileVersion}_$stamp.sqlite';
    raw.execute("VACUUM INTO '${p.join(dir.path, name)}'");
    // 升级前备份：正常升级保留最近 2 份
    pruneBackupsByPrefix(dir, prefix: _kUpgradeBackupPrefix);
    // 降级留底：同样只保留最近 2 份。降级是回退场景，反复装旧版
    // 会让快照无限堆积，限量兜底
    pruneBackupsByPrefix(dir, prefix: _kDowngradeBackupPrefix);
  } catch (_) {
    // 预检/备份失败放行：升级有事务保护，降级仍有重建兜底
  } finally {
    raw?.dispose();
  }
}

/// 按 [prefix] 清理历史备份，只保留最近 [keep] 份
/// （文件名含时间戳，字典序即时间序）。公开供钱迹导入留底复用。
void pruneBackupsByPrefix(Directory dir, {required String prefix, int keep = 2}) {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith(prefix))
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
      _CategorySeed('快餐', Icons.lunch_dining, 0xFFFF9F43, BillType.expense, 5),
      _CategorySeed('零食', Icons.icecream, 0xFFFF9F43, BillType.expense, 6),
      _CategorySeed('饮料', Icons.local_drink, 0xFFFF9F43, BillType.expense, 7),
      _CategorySeed(
        '下馆子',
        Icons.dinner_dining,
        0xFFFF9F43,
        BillType.expense,
        8,
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
      _CategorySeed('电器', Icons.tv, 0xFFFF6B81, BillType.expense, 3),
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
  // 兜底组：归不进前述分类的支出放这里，常驻末位（无子分类）
  _CategorySeed('其他', Icons.more_horiz, 0xFFA8A8A8, BillType.expense, 9),
  // 收入分类
  _CategorySeed('工资', Icons.work, 0xFF4E9E5F, BillType.income, 0),
  _CategorySeed('奖金', Icons.emoji_events, 0xFFF39C12, BillType.income, 1),
  _CategorySeed('理财', Icons.trending_up, 0xFF27AE60, BillType.income, 2),
  _CategorySeed('红包', Icons.currency_yen, 0xFFE74C3C, BillType.income, 3),
  _CategorySeed('其他', Icons.more_horiz, 0xFFA8A8A8, BillType.income, 4),
];
