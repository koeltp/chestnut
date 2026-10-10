import 'dart:io';
import 'dart:typed_data';

import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/asset_repository.dart';
import 'package:chestnut/data/repositories/debt_note_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/services/photo_staging_service.dart';
import 'package:chestnut/services/s3_compatible_client.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

/// 建一张 v8 时代的 bills 表（category_id NOT NULL、无账户列）。
/// v9 起迁移会触碰 bills（加 assetId/toAssetId 并改 categoryId 可空），
/// 旧迁移测试的手工旧库需补齐最小骨架供迁移执行
void _createV8BillsTable(Database raw) {
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
}

/// 资产数据层回归测试：增改写入、快照落库、净值聚合与借条并账口径
///
/// 核心保障：净值曲线的数据全部来自快照表（只增不删），聚合规则
/// （每日取最后一条 / 负债取负 / 归档不删历史 / includeInNet 开关 /
/// 借条并入两侧）一旦走样，用户看到的资产数字与曲线就会自相矛盾。
void main() {
  late AppDatabase db;
  late AssetRepository repo;
  late DebtNoteRepository debtRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssetRepository(db);
    debtRepo = DebtNoteRepository(db);
    // 触发建库（含迁移与预置分类）
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  Future<int> insertAssetWithSnapshot(
    int assetId,
    String day,
    int valueCents,
  ) => db
      .into(db.assetSnapshots)
      .insert(
        AssetSnapshotsCompanion.insert(
          assetId: assetId,
          day: day,
          valueCents: valueCents,
        ),
      );

  test('新增资产：写入资产表并落一条初始快照', () async {
    await repo.insertAsset(
      name: '招行储蓄卡',
      kind: AssetKind.asset,
      category: '银行卡',
      valueCents: 10000,
    );
    final active = await repo.watchActive().first;
    expect(active, hasLength(1));
    expect(active.single.valueCents, 10000);
    // 初始快照：净值曲线从创建当天就有数据点
    final snaps = await db.select(db.assetSnapshots).get();
    expect(snaps, hasLength(1));
    expect(snaps.single.valueCents, 10000);
  });

  test('连续新增同类型资产：sortOrder 递增且不抛 Too many elements', () async {
    // 回归：排序权重查询曾缺 limit(1)，同类型已有两条以上时
    // getSingleOrNull 撞上多行结果直接炸（保存资产报 Bad state）
    for (var i = 0; i < 3; i++) {
      await repo.insertAsset(
        name: '股票账户$i',
        kind: AssetKind.asset,
        category: '股票',
        valueCents: 1000 + i,
      );
    }
    final active = await repo.watchActive().first;
    expect(active, hasLength(3));
    expect(
      active.map((a) => a.sortOrder),
      [0, 1, 2],
    );
  });

  test('新增信用卡资产：额度/出账日/还款日与净值开关一并写入', () async {
    await repo.insertAsset(
      name: '招行信用卡',
      kind: AssetKind.liability,
      category: '信用卡',
      valueCents: 3000,
      creditLimitCents: 50000,
      billDay: 5,
      repayDay: 23,
      includeInNet: false,
    );
    final card = (await repo.watchActive().first).single;
    expect(card.creditLimitCents, 50000);
    expect(card.billDay, 5);
    expect(card.repayDay, 23);
    expect(card.includeInNet, isFalse);
  });

  test('更新市值：资产表与快照同步更新', () async {
    await repo.insertAsset(
      name: '婚房',
      kind: AssetKind.asset,
      category: '房产',
      valueCents: 1000000,
    );
    final asset = await repo.watchActive().first;
    await repo.updateValue(asset.single, 1200000);
    final after = await repo.watchActive().first;
    expect(after.single.valueCents, 1200000);
    // 原始快照保留：1 条初始 + 1 条更新
    final snaps = await db.select(db.assetSnapshots).get();
    expect(snaps, hasLength(2));
  });

  test('净值历史聚合：每日取最后一条快照、负债取负、今天的点被过滤', () async {
    await repo.insertAsset(
      name: '招行储蓄卡',
      kind: AssetKind.asset,
      category: '现金',
      valueCents: 10000,
    );
    final a = (await repo.watchActive().first).single;
    await repo.insertAsset(
      name: '房贷',
      kind: AssetKind.liability,
      category: '房贷',
      valueCents: 5000,
    );
    final b = (await repo.watchActive().first).last;

    // 昨天两条快照（同日两条取最后一条）：A 8000 -> 9000；B 4000
    await insertAssetWithSnapshot(a.id, '2026-10-08', 8000);
    await insertAssetWithSnapshot(a.id, '2026-10-08', 9000);
    await insertAssetWithSnapshot(b.id, '2026-10-08', 4000);

    // 昨天净值 = 9000 − 4000 = 5000；今天的快照不入历史序列
    final history = await repo.watchNetHistory().first;
    expect(history, hasLength(1));
    expect(history.single.$1, '2026-10-08');
    expect(history.single.$2, 5000);

    // 汇总口径：资产合计 10000、负债合计 5000、快照净值 5000
    final summary = await repo.watchSummary().first;
    expect(summary.assetCents, 10000);
    expect(summary.liabilityCents, 5000);
    expect(summary.snapshotNetCents, 5000);
  });

  test('归档资产：退出汇总统计，历史快照保留参与曲线聚合', () async {
    await repo.insertAsset(
      name: '旧车',
      kind: AssetKind.asset,
      category: '车辆',
      valueCents: 8000,
    );
    final asset = (await repo.watchActive().first).single;
    await insertAssetWithSnapshot(asset.id, '2026-10-08', 7000);

    await repo.setArchived(asset, archived: true);
    // 汇总为空：归档后不计净值
    final summary = await repo.watchSummary().first;
    expect(summary.netCents, 0);
    // 历史点仍在：曲线不回溯断层
    final history = await repo.watchNetHistory().first;
    expect(history.single.$2, 7000);
    // 归档列表可见且可恢复
    final archived = await repo.watchArchived().first;
    expect(archived.single.id, asset.id);
    await repo.setArchived(archived.single, archived: false);
    expect((await repo.watchActive().first), hasLength(1));
  });

  test('关闭计入总资产：账户仅展示，不参与净值与项数统计', () async {
    await repo.insertAsset(
      name: '闲置卡',
      kind: AssetKind.asset,
      category: '现金',
      valueCents: 5000,
      includeInNet: false,
    );
    await repo.insertAsset(
      name: '现金',
      kind: AssetKind.asset,
      category: '现金',
      valueCents: 10000,
    );
    final summary = await repo.watchSummary().first;
    // 只有计入开关打开的账户参与聚合
    expect(summary.assetCents, 10000);
    expect(summary.assetCount, 1);
    expect(summary.netCents, 10000);

    // 再打开开关后立即参与
    final idle = (await repo.watchActive().first)
        .firstWhere((a) => a.name == '闲置卡');
    await repo.updateInfo(idle, name: '闲置卡', category: '现金', includeInNet: true);
    final after = await repo.watchSummary().first;
    expect(after.assetCents, 15000);
    expect(after.assetCount, 2);
  });

  test('信息更新：名称/分类/备注可改且不产生新快照', () async {
    await repo.insertAsset(
      name: '招行储蓄卡',
      kind: AssetKind.asset,
      category: '现金',
      valueCents: 10000,
      note: '工资卡',
    );
    final asset = (await repo.watchActive().first).single;
    await repo.updateInfo(asset, name: '招行卡', category: '其它理财', note: null);
    final after = (await repo.watchActive().first).single;
    expect(after.name, '招行卡');
    expect(after.category, '其它理财');
    expect(after.note, isNull);
    // 只有创建时的一条快照
    final snaps = await db.select(db.assetSnapshots).get();
    expect(snaps, hasLength(1));
  });

  test('借条并账：借出并入资产侧、借入并入负债侧，负债率随之变化', () async {
    await repo.insertAsset(
      name: '现金',
      kind: AssetKind.asset,
      category: '现金',
      valueCents: 10000,
    );
    await debtRepo.insertDebtNote(
      direction: DebtDirection.lendOut,
      personName: '老王',
      amountCents: 3000,
      borrowedAt: DateTime(2026, 10, 1),
    );
    await debtRepo.insertDebtNote(
      direction: DebtDirection.borrowIn,
      personName: '老李',
      amountCents: 2000,
      borrowedAt: DateTime(2026, 10, 2),
    );
    final summary = await repo.watchSummary().first;
    // 总资产 = 10000 + 借出 3000；总负债 = 借入 2000
    expect(summary.totalAssetCents, 13000);
    expect(summary.totalLiabilityCents, 2000);
    expect(summary.netCents, 11000);
    expect(summary.lendOutAllCents, 3000);
    expect(summary.borrowInAllCents, 2000);
  });

  test('借条开关与全部口径：关闭计入的借条只进"全部"统计', () async {
    await debtRepo.insertDebtNote(
      direction: DebtDirection.lendOut,
      personName: '老王',
      amountCents: 3000,
      borrowedAt: DateTime(2026, 10, 1),
    );
    await debtRepo.insertDebtNote(
      direction: DebtDirection.lendOut,
      personName: '老张',
      amountCents: 5000,
      borrowedAt: DateTime(2026, 10, 2),
      includeInTotal: false,
    );
    final summary = await repo.watchSummary().first;
    // 计入口径只含第一笔；台账口径两笔都算
    expect(summary.lendOutCents, 3000);
    expect(summary.lendOutAllCents, 8000);
    expect(summary.totalAssetCents, 3000);

    // 借条 CRUD：更新与删除实时反映到聚合流
    final all = await debtRepo.watchAll().first;
    await debtRepo.updateDebtNote(
      all.last,
      personName: '老王',
      amountCents: 4000,
      borrowedAt: DateTime(2026, 10, 1),
      includeInTotal: true,
    );
    final afterUpdate = await repo.watchSummary().first;
    expect(afterUpdate.lendOutCents, 4000);
    await debtRepo.deleteDebtNote((await debtRepo.watchAll().first).last);
    final afterDelete = await repo.watchSummary().first;
    expect(afterUpdate.lendOutCents - afterDelete.lendOutCents, 4000);
  });

  test('借据照片双写：多图保存落 objectKey，上传后转 done，删除清云端', () async {
    // 照片流转走真实文件系统：把应用支持目录重定向到本次测试的临时目录
    final tempDir = await Directory.systemTemp.createTemp('debt_photo_test');
    final originalProvider = PathProviderPlatform.instance;
    addTearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    PathProviderPlatform.instance = _FakePathProvider(tempDir);

    // 暂存走共享服务（压缩对非法图片必然失败 → 退回原图，无需真 JPEG）
    final staged1 =
        await PhotoStagingService(dirName: 'debt_photos')
            .stage(Uint8List.fromList([1, 2, 3]));
    final staged2 =
        await PhotoStagingService(dirName: 'debt_photos')
            .stage(Uint8List.fromList([4, 5, 6]));
    final note = await debtRepo.insertDebtNote(
      direction: DebtDirection.lendOut,
      personName: '老王',
      amountCents: 3000,
      borrowedAt: DateTime(2026, 10, 1),
      stagedPhotoPaths: [staged1, staged2],
    );
    // 转正后照片行成对出现，objectKey 指向该借条目录
    var photos = await debtRepo.getPhotosByNoteId(note.id);
    expect(photos, hasLength(2));
    expect(photos[0].objectKey, startsWith('chestnut/debt_photos/${note.id}/'));
    expect(photos[0].uploadState, BillImageUploadState.pending);

    // 上传成功：假客户端收到 PUT，状态转 done
    final client = _FakeS3();
    await debtRepo.uploadPhotos(photos, client);
    expect(client.putKeys, containsAll(photos.map((p) => p.objectKey)));
    photos = await debtRepo.getPhotosByNoteId(note.id);
    expect(
      photos.map((p) => p.uploadState),
      everyElement(BillImageUploadState.done),
    );

    // 删除借条：本地文件与云端对象一并清理
    final current = (await debtRepo.watchAll().first).first;
    await debtRepo.deleteDebtNote(current, client: client);
    expect(client.deletedKeys, containsAll(photos.map((p) => p.objectKey)));
    for (final p in photos) {
      expect(await File(p.localPath).exists(), isFalse);
    }
    expect(await debtRepo.getPhotosByNoteId(note.id), isEmpty);
  });

  test('借据照片：上传失败标 failed；本地文件丢失作废照片记录保留借条', () async {
    final tempDir = await Directory.systemTemp.createTemp('debt_photo_test');
    final originalProvider = PathProviderPlatform.instance;
    addTearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    PathProviderPlatform.instance = _FakePathProvider(tempDir);

    final staged =
        await PhotoStagingService(dirName: 'debt_photos')
            .stage(Uint8List.fromList([1, 2, 3]));
    final note = await debtRepo.insertDebtNote(
      direction: DebtDirection.borrowIn,
      personName: '老李',
      amountCents: 2000,
      borrowedAt: DateTime(2026, 10, 2),
      stagedPhotoPaths: [staged],
    );
    var photos = await debtRepo.getPhotosByNoteId(note.id);

    // 上传失败：状态转 failed 等启动补传
    final failing = _FakeS3(failPut: true);
    expect(await debtRepo.uploadOne(photos.single, failing), isFalse);
    photos = await debtRepo.getPhotosByNoteId(note.id);
    expect(photos.single.uploadState, BillImageUploadState.failed);

    // 本地文件丢失后再传：照片记录作废但借条本体保留
    await File(photos.single.localPath).delete();
    expect(await debtRepo.uploadOne(photos.single, _FakeS3()), isFalse);
    expect(await debtRepo.getPhotosByNoteId(note.id), isEmpty);
    final cleared = (await debtRepo.watchAll().first).first;
    expect(cleared.personName, '老李');
  });

  test('借据照片：编辑一次保存同时删旧图加新图', () async {
    final tempDir = await Directory.systemTemp.createTemp('debt_photo_test');
    final originalProvider = PathProviderPlatform.instance;
    addTearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    PathProviderPlatform.instance = _FakePathProvider(tempDir);

    final s1 =
        await PhotoStagingService(dirName: 'debt_photos')
            .stage(Uint8List.fromList([1]));
    final note = await debtRepo.insertDebtNote(
      direction: DebtDirection.lendOut,
      personName: '老王',
      amountCents: 100,
      borrowedAt: DateTime(2026, 10, 1),
      stagedPhotoPaths: [s1],
    );
    final before = await debtRepo.getPhotosByNoteId(note.id);

    // 删旧图 + 加新图一次保存：旧记录/文件/云端对象清掉，新图 pending
    final s2 =
        await PhotoStagingService(dirName: 'debt_photos')
            .stage(Uint8List.fromList([2, 3]));
    final client = _FakeS3();
    await debtRepo.updateDebtNote(
      note,
      personName: '老王',
      amountCents: 100,
      borrowedAt: DateTime(2026, 10, 1),
      includeInTotal: true,
      removedPhotoIds: [before.single.id],
      stagedPhotoPaths: [s2],
      client: client,
    );
    final after = await debtRepo.getPhotosByNoteId(note.id);
    expect(after, hasLength(1));
    expect(after.single.id, isNot(before.single.id));
    expect(after.single.uploadState, BillImageUploadState.pending);
    expect(await File(before.single.localPath).exists(), isFalse);
    expect(client.deletedKeys, contains(before.single.objectKey));
  });

  test('v7 迁移：旧分类名按 kind 映射到新分类体系', () async {
    // 模拟 v6 旧数据（绕过仓储直接写旧分类名）
    final legacy = [
      ('现金存款', AssetKind.asset, '旧现金'),
      ('金融理财', AssetKind.asset, '旧理财'),
      ('其他', AssetKind.asset, '旧其他'),
      ('借款', AssetKind.liability, '旧借款'),
      ('其他', AssetKind.liability, '旧负其他'),
    ];
    for (final (category, kind, name) in legacy) {
      await db.into(db.assets).insert(
            AssetsCompanion.insert(
              name: name,
              kind: kind,
              category: category,
              valueCents: 100,
            ),
          );
    }
    // 手动执行与 v7 迁移相同的映射逻辑（内存库直接建到 v7，
    // 无法走真实迁移路径，此处保证映射规则本身的正确性）
    const assetRenames = <String, String>{
      '现金存款': '现金',
      '金融理财': '其它理财',
      '其他': '其它',
    };
    for (final entry in assetRenames.entries) {
      await db.customUpdate(
        'UPDATE assets SET category = ? WHERE category = ? AND kind = 0',
        variables: [Variable(entry.value), Variable(entry.key)],
      );
    }
    await db.customUpdate(
      "UPDATE assets SET category = '其它负债' WHERE category IN ('借款', '其他') AND kind = 1",
    );

    final rows = await db.select(db.assets).get();
    final byName = {for (final r in rows) r.name: r.category};
    expect(byName['旧现金'], '现金');
    expect(byName['旧理财'], '其它理财');
    expect(byName['旧其他'], '其它');
    expect(byName['旧借款'], '其它负债');
    expect(byName['旧负其他'], '其它负债');
  });

  test('v7 迁移幂等：半迁移中间态（列已存在、版本号未落）自动补齐', () async {
    // 模拟上次迁移半途中断留下的库：assets 已有 include_in_net 列，
    // 但 user_version 仍为 6（重复 ADD COLUMN 会报 duplicate column）
    final halfMigrated = NativeDatabase.memory(
      setup: (raw) {
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
          created_at INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        raw.execute('PRAGMA user_version = 6');
        // v6 结构本就存在的快照表（迁移不动它，但写入链路需要）
        raw.execute('''
          CREATE TABLE asset_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id INTEGER NOT NULL REFERENCES assets (id),
            day TEXT NOT NULL,
            value_cents INTEGER NOT NULL,
            created_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // v6 时代已存在的 bills 表（v9 迁移段会触碰）
        _createV8BillsTable(raw);
      },
    );
    final halfDb = AppDatabase.forTesting(halfMigrated);
    addTearDown(halfDb.close);
    // 触发打开：onUpgrade(6→10) 走幂等路径，不抛 duplicate column
    await halfDb.customSelect('SELECT 1').get();

    // 版本已推进到 10
    final version =
        (await halfDb.customSelect('PRAGMA user_version').get()).single;
    expect(version.data['user_version'], 10);

    // 缺失的三列已补齐、debt_notes 已建
    final cols =
        (await halfDb.customSelect('PRAGMA table_info(assets)').get())
            .map((r) => r.data['name'] as String)
            .toList();
    for (final name in ['credit_limit_cents', 'bill_day', 'repay_day']) {
      expect(cols, contains(name));
    }
    final tables = (await halfDb
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table'",
            )
            .get())
        .map((r) => r.data['name'] as String);
    expect(tables, contains('debt_notes'));
    expect(tables, contains('debt_note_images'));

    // 迁移后的库可正常写入
    final halfRepo = AssetRepository(halfDb);
    await halfRepo.insertAsset(
      name: '现金',
      kind: AssetKind.asset,
      category: '现金',
      valueCents: 100,
    );
    expect(await halfRepo.watchActive().first, hasLength(1));
  });

  test('v8/v10 迁移：v7 库补双写列后归并为多图 debt_note_images', () async {
    // 模拟已升到 v7 的库：debt_notes 尚无 objectKey/uploadState 列
    final v7 = NativeDatabase.memory(
      setup: (raw) {
        raw.execute('''
          CREATE TABLE debt_notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            direction INTEGER NOT NULL,
            person_name TEXT NOT NULL,
            amount_cents INTEGER NOT NULL,
            note TEXT NULL,
            photo_path TEXT NULL,
            related_asset_id INTEGER NULL,
            borrowed_at INTEGER NOT NULL,
            repay_due_at INTEGER NULL,
            include_in_total INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        raw.execute(
          "INSERT INTO debt_notes (direction, person_name, amount_cents, borrowed_at) VALUES (0, '张三', 5000, 0)",
        );
        // 带单张借据照片的旧行：v10 应把 photo_path 迁入 debt_note_images
        // （v7 结构尚无 object_key/upload_state 列，v8 补列后为空/默认）
        raw.execute(
          "INSERT INTO debt_notes (direction, person_name, amount_cents, borrowed_at, photo_path) "
          "VALUES (0, '李四', 2000, 0, '/tmp/old.jpg')",
        );
        // v7 时代已存在的 bills 表（v9 迁移段会触碰）
        _createV8BillsTable(raw);
        raw.execute('PRAGMA user_version = 7');
      },
    );
    final v7Db = AppDatabase.forTesting(v7);
    addTearDown(v7Db.close);
    await v7Db.customSelect('SELECT 1').get();

    final version =
        (await v7Db.customSelect('PRAGMA user_version').get()).single;
    expect(version.data['user_version'], 10);

    // 单图三列已随表重建移除，旧照片数据落入 debt_note_images
    final cols =
        (await v7Db.customSelect('PRAGMA table_info(debt_notes)').get())
            .map((r) => r.data['name'] as String)
            .toList();
    expect(cols, isNot(contains('photo_path')));
    expect(cols, isNot(contains('object_key')));
    expect(cols, isNot(contains('upload_state')));
    final photos = await v7Db.select(v7Db.debtNoteImages).get();
    expect(photos, hasLength(1));
    expect(photos.single.localPath, '/tmp/old.jpg');
    expect(photos.single.objectKey, '');
    expect(photos.single.uploadState, BillImageUploadState.pending);
    // 旧借条本体原样保留
    final notes = await v7Db.select(v7Db.debtNotes).get();
    expect(notes, hasLength(2));
    expect(notes.map((n) => n.personName), containsAll(['张三', '李四']));
  });
}

/// path_provider 假实现：应用支持目录重定向到临时目录，
/// 供借据照片的暂存/转正走真实文件系统
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);

  final Directory dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

/// S3 客户端假实现：只记录调用，不发网络请求；
/// [failPut] 模拟上传失败路径
class _FakeS3 extends S3CompatibleClient {
  _FakeS3({this.failPut = false})
      : super(
          endpoint: 'https://fake.example.com',
          bucket: 'chestnut-test',
          accessKeyId: 'test',
          secretAccessKey: 'test',
        );

  final bool failPut;

  /// 收到过的 PUT 对象键
  final putKeys = <String>[];

  /// 收到过的 DELETE 对象键
  final deletedKeys = <String>[];

  @override
  Future<void> putObject(
    String key,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  }) async {
    if (failPut) throw S3ClientException('模拟网络故障');
    putKeys.add(key);
  }

  @override
  Future<Uint8List> getObject(String key) async => Uint8List.fromList([1]);

  @override
  Future<void> deleteObject(String key) async {
    deletedKeys.add(key);
  }
}
