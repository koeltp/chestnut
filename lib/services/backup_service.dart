import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/database.dart';
import '../providers/settings_provider.dart';

/// 历史备份类型（按文件名前缀区分）
///
/// 只含系统自动生成的保险快照；导出文件（chestnut_export_*）是
/// "用完即弃"的临时产物，不属于历史备份。
enum BackupKind {
  /// 正常升级前自动备份
  upgradeBackup,

  /// 降级（装回旧版 App）时的数据留底
  downgradeBackup,

  /// 导入恢复前对当前库的留底
  beforeRestore,

  /// 每日自动备份（用户开启开关后，每天首次启动执行）
  dailyBackup,
}

/// 私有目录中的一份历史备份/留底文件
///
/// App 读自己的私有目录无需任何权限，把工程内部兜底文件变成
/// 用户在"历史备份"里可见可恢复的条目。
class InternalBackup {
  const InternalBackup({
    required this.path,
    required this.kind,
    required this.fileVersion,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String path;
  final BackupKind kind;

  /// 备份文件自身的 user_version；-1 表示文件损坏无法读取
  final int fileVersion;

  final DateTime modifiedAt;
  final int sizeBytes;

  /// 版本倒挂：备份比当前代码版本新，直接恢复会再次触发降级重建，
  /// 必须引导用户先升级 App
  bool get blocked => fileVersion > kSchemaVersion;

  /// 文件损坏（恢复入口交给预检拦截并提示）
  bool get corrupted => fileVersion < 0;
}

/// 备份与恢复服务
///
/// 备份 = VACUUM INTO 生成主库完整快照（单文件、保真、紧凑）；
/// 恢复 = 启动早期用备份文件整体替换主库文件（文件级替换，不做数据
/// 搬运），旧版本备份由 drift 迁移链在下次打开时自动升级。
class BackupService {
  /// 记录上次每日备份日期的 SharedPreferences 键（yyyyMMdd）
  static const _kLastAutoBackupDate = 'auto_backup_last_date';

  /// 每日备份保留份数
  static const kDailyBackupKeep = 7;

  /// 应用文档目录
  Future<Directory> _documentsDir() => getApplicationDocumentsDirectory();

  /// 主库文件
  Future<File> _databaseFile() async {
    final dir = await _documentsDir();
    return File(p.join(dir.path, kDatabaseFileName));
  }

  /// 待恢复文件：存在即视为"下次启动执行恢复"的标记
  Future<File> _pendingRestoreFile() async {
    final dir = await _documentsDir();
    return File(p.join(dir.path, 'chestnut_pending_restore.sqlite'));
  }

  /// 导出当前主库为完整快照，返回生成的备份文件
  ///
  /// 通过 drift 同一连接执行 VACUUM INTO，避免独立连接与运行中的
  /// 写事务撞锁；主库尚未创建时抛出异常由调用方提示。
  Future<File> exportBackup(AppDatabase db) async {
    final dir = await _documentsDir();
    final stamp = _stamp();
    final target = p.join(dir.path, 'chestnut_export_$stamp.sqlite');
    await db.customStatement("VACUUM INTO '$target'");
    return File(target);
  }

  /// 预检待导入文件，返回 null 表示通过，否则返回人话错误提示
  ///
  /// 校验三件事：能以 SQLite 打开（防拷贝一半的损坏文件）、核心表
  /// 存在（防选错文件）、user_version 不高于当前代码版本（防"未来
  /// 备份导进旧 App"导致启动崩溃）。
  Future<String?> validateBackup(String path) async {
    if (!File(path).existsSync()) return '文件不存在，请重新选择';
    Database? raw;
    try {
      raw = sqlite3.open(path, mode: OpenMode.readOnly);
      final integrity = raw.select('PRAGMA integrity_check(1)');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        return '备份文件已损坏，无法导入';
      }
      final version = raw.userVersion;
      if (version > kSchemaVersion) {
        return '该备份来自更新版本的应用，请先升级 App 再导入';
      }
      final tables = raw.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='bills'",
      );
      if (tables.isEmpty) return '不是栗子记账的备份文件';
      return null;
    } catch (e) {
      return '无法读取该文件，请确认选择的是 .sqlite 备份文件';
    } finally {
      raw?.dispose();
    }
  }

  /// 将用户选择的备份文件暂存为待恢复文件，下次启动生效
  Future<void> stageRestore(String sourcePath) async {
    final pending = await _pendingRestoreFile();
    await File(sourcePath).copy(pending.path);
  }

  /// 启动早期执行待定恢复，必须在数据库首次打开前调用
  ///
  /// 流程：留底当前库（VACUUM INTO 会合并 WAL 中的最新数据）→
  /// 删除主库与 WAL 附属文件 → 待恢复文件顶替主库。
  /// 返回是否执行了恢复（用于启动提示）。
  Future<bool> restoreIfNeeded() async {
    final pending = await _pendingRestoreFile();
    if (!await pending.exists()) return false;
    final dir = await _documentsDir();
    final dbFile = await _databaseFile();

    // 1. 留底当前库：每次导入前都把当前数据快照一份（文件名带时间戳，
    //    互不覆盖）——连续导错不丢最早的正确数据，导入后新写的账也
    //    不会没有留底。留底失败不阻断恢复。
    if (await dbFile.exists()) {
      Database? raw;
      try {
        final before = p.join(
          dir.path,
          'chestnut_before_restore_${_stamp()}.sqlite',
        );
        raw = sqlite3.open(dbFile.path);
        raw.execute("VACUUM INTO '$before'");
      } catch (_) {
        // 留底失败不阻断恢复
      } finally {
        raw?.dispose();
      }
    }

    // 2. 删除主库与 WAL 附属文件（只换主文件留旧 WAL 会损坏数据库）
    await _deleteIfExists(dbFile);
    for (final name in kDatabaseSidecarFiles) {
      await _deleteIfExists(File(p.join(dir.path, name)));
    }

    // 3. 待恢复文件顶替主库
    await pending.copy(dbFile.path);
    await pending.delete();
    return true;
  }

  /// 扫描私有目录中的历史备份与留底文件，按时间倒序（新在前）
  Future<List<InternalBackup>> listInternalBackups() async {
    final dir = await _documentsDir();
    final result = <InternalBackup>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final kind = _classify(p.basename(entity.path));
      if (kind == null) continue;
      final stat = entity.statSync();
      result.add(
        InternalBackup(
          path: entity.path,
          kind: kind,
          fileVersion: _readVersion(entity.path),
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
    result.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return result;
  }

  /// 删除一份历史备份（只接受本服务扫描出的条目，防误删主库）
  Future<void> deleteInternalBackup(InternalBackup backup) async {
    final file = File(backup.path);
    if (await file.exists()) await file.delete();
  }

  /// 按文件名前缀识别类型；主库/待恢复暂存/导出临时文件不进历史备份
  BackupKind? _classify(String name) {
    if (name.startsWith('chestnut_backup_v')) return BackupKind.upgradeBackup;
    if (name.startsWith('chestnut_downgrade_v')) {
      return BackupKind.downgradeBackup;
    }
    if (name.startsWith('chestnut_before_restore')) {
      return BackupKind.beforeRestore;
    }
    if (name.startsWith('chestnut_daily_')) return BackupKind.dailyBackup;
    return null;
  }

  /// 清理上次会话遗留的导出临时文件（chestnut_export_*）
  ///
  /// 导出快照是"用完即弃"的中间产物：分享面板拉起后微信等目标
  /// App 仍从 FileProvider 异步读取，不能当场删；等下次启动时
  /// 统一清理，此时上次会话早已结束。
  Future<void> cleanupExportTemp() async {
    final dir = await _documentsDir();
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (p.basename(entity.path).startsWith('chestnut_export_')) {
        try {
          await entity.delete();
        } catch (_) {
          // 单个清理失败忽略，下次启动再试
        }
      }
    }
  }

  /// 只读健康探测：主库能否以 SQLite 打开并通过完整性检查
  ///
  /// 在 drift 打开连接前调用，只读模式不触发迁移、不建表。
  /// 主库损坏时启动流程走兜底页，而不是白屏或崩溃。
  /// 首次启动主库还不存在时视为健康，交给正常建库流程。
  Future<bool> checkDatabaseHealth() async {
    final dbFile = await _databaseFile();
    if (!await dbFile.exists()) return true;
    Database? raw;
    try {
      raw = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
      final integrity = raw.select('PRAGMA integrity_check(1)');
      return integrity.isNotEmpty && integrity.first.values.first == 'ok';
    } catch (_) {
      return false;
    } finally {
      raw?.dispose();
    }
  }

  /// 每日自动备份：用户开启开关后，每天首次启动时执行一次
  ///
  /// 以只读连接 VACUUM INTO 生成 chestnut_daily_yyyyMMdd.sqlite，
  /// 只保留最近 [kDailyBackupKeep] 份——无人监督的备份也会把坏状态
  /// 备下来，只留最新一份可能在 24 小时内把唯一的好备份覆盖掉；
  /// 单份仅几十 KB，7 份成本可忽略。任何失败都静默跳过，次日再试。
  Future<void> autoBackupIfNeeded(SharedPreferences prefs) async {
    // 开关未开启（含键不存在）则什么都不做
    if (prefs.getBool(SettingsProvider.kAutoBackupEnabled) != true) return;
    final today = _dateStamp();
    // 今天已备过则跳过
    if (prefs.getString(_kLastAutoBackupDate) == today) return;
    final dbFile = await _databaseFile();
    if (!await dbFile.exists()) return;
    final dir = await _documentsDir();
    Database? raw;
    try {
      raw = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
      // 尚未初始化的空库（user_version=0）不值得备份
      if (raw.userVersion == 0) return;
      final target = p.join(dir.path, 'chestnut_daily_$today.sqlite');
      raw.execute("VACUUM INTO '$target'");
      await prefs.setString(_kLastAutoBackupDate, today);
      await _pruneDailyBackups(dir);
    } catch (_) {
      // 自动备份失败不打扰用户，明天再试
    } finally {
      raw?.dispose();
    }
  }

  /// 清理每日备份：按文件名日期倒序，只保留最新若干份
  Future<void> _pruneDailyBackups(Directory dir) async {
    final dailies = <File>[
      for (final entity in dir.listSync())
        if (entity is File &&
            p.basename(entity.path).startsWith('chestnut_daily_'))
          entity,
    ];
    if (dailies.length <= kDailyBackupKeep) return;
    dailies.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final file in dailies.skip(kDailyBackupKeep)) {
      try {
        await file.delete();
      } catch (_) {
        // 单个清理失败忽略，下次启动再试
      }
    }
  }

  /// 日期戳（每日备份文件名用，形如 20261005）
  String _dateStamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}';
  }

  /// 只读读取备份文件自身的 user_version（损坏返回 -1）
  int _readVersion(String path) {
    Database? raw;
    try {
      raw = sqlite3.open(path, mode: OpenMode.readOnly);
      return raw.userVersion;
    } catch (_) {
      return -1;
    } finally {
      raw?.dispose();
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  /// 时间戳（文件名用，形如 20261005_234500）
  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
