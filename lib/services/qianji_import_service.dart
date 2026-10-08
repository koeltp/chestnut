import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/database.dart';
import '../data/repositories/tag_repository.dart';
import '../models/enums.dart';

/// 钱迹导入流程异常（message 可直接展示给用户）
class QianjiImportException implements Exception {
  const QianjiImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析后的单笔钱迹账单（只含本应用支持的支出/收入）
class QianjiBill {
  const QianjiBill({
    required this.dateTime,
    required this.type,
    required this.cat1,
    required this.cat2,
    required this.note,
    required this.amountCents,
    this.tags = const [],
  });

  /// 账单时间（精确到秒；写入时拆成 date + timeMinute）
  final DateTime dateTime;
  final BillType type;

  /// 钱迹一级分类（原始值，如"吃"）
  final String cat1;

  /// 钱迹二级分类（原始值，无二级为空串）
  final String cat2;

  /// 钱迹备注（原始值，可能为空串）
  final String note;
  final int amountCents;

  /// 钱迹标签名列表（原始值，可能为空）
  final List<String> tags;
}

/// 文件解析结果
class QianjiParseResult {
  const QianjiParseResult({
    required this.bills,
    required this.unsupportedByType,
    required this.badCount,
  });

  /// 支出/收入账单（可导入部分）
  final List<QianjiBill> bills;

  /// 本应用不支持类型的笔数统计（如 退款:28 / 转账:19），导入结果页展示
  final Map<String, int> unsupportedByType;

  /// 金额或时间无法解析的行数（跳过，不导入）
  final int badCount;
}

/// 映射分组：映射页一行 = 钱迹的一个 (类型, 一级, 二级) 组合
class QianjiGroup {
  const QianjiGroup({
    required this.key,
    required this.type,
    required this.cat1,
    required this.cat2,
    required this.count,
    required this.totalCents,
    required this.bills,
    required this.autoMatch,
  });

  /// 分组键（手动映射 Map 的 key）
  final String key;
  final BillType type;

  /// 钱迹一级分类名（原始）
  final String cat1;

  /// 钱迹二级分类名（原始，无二级为空串）
  final String cat2;
  final int count;
  final int totalCents;
  final List<QianjiBill> bills;

  /// 自动归级结果（同名命中的一级或二级分类）；null = 落"其它"
  final Category? autoMatch;
}

/// 导入执行结果
class QianjiImportResult {
  const QianjiImportResult({
    required this.batchId,
    required this.importedCount,
    required this.expenseCount,
    required this.incomeCount,
    required this.fallbackCount,
    required this.unsupportedCount,
    required this.badCount,
  });

  /// 本次导入批次号（整批撤销用）
  final int batchId;
  final int importedCount;
  final int expenseCount;
  final int incomeCount;

  /// 落入"其它"分类的笔数
  final int fallbackCount;

  /// 不支持类型跳过的笔数
  final int unsupportedCount;

  /// 解析失败跳过的笔数
  final int badCount;
}

/// 钱迹 xlsx 账单导入服务
///
/// 三段式流程，UI 层逐步调用：
/// 1. [parseFile] 解析 xlsx，得到可导入账单与不支持类型的统计；
/// 2. [buildGroups] 按 (类型, 一级, 二级) 分组并计算自动归级；
/// 3. [importBills] 留底 + 单事务整批写入（带批次号），支持 [deleteBatch]
///    整批撤销。
///
/// 分类映射策略（与产品定稿一致）：
/// · 手动映射 > 自动归级 > 兜底"其它"；
/// · 自动归级只做同名匹配：二级跨一级全局同名 → 一级同名（"其它"≡"其他"）；
/// · 钱迹的退款/转账/还款/债务/报销类型本应用没有对应概念，不导入。
abstract final class QianjiImportService {
  /// 钱迹类型列中可直接导入的类型名
  static const _supportedTypes = {'支出', '收入'};

  /// 兜底"其它"分类的统一名称与外观（与收入侧预置"其他"一致）
  static const _fallbackName = '其他';
  static const _fallbackColor = 0xFFA8A8A8;

  // ---------------- 解析 ----------------

  /// 解析钱迹导出的 xlsx 文件
  ///
  /// 列按表头名定位（时间/分类/二级分类/类型/金额/备注），不依赖列序；
  /// 非"支出/收入"类型的行计入 unsupportedByType；金额或时间解析失败
  /// 的行计入 badCount 并跳过。
  static Future<QianjiParseResult> parseFile(String path) async {
    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (_) {
      throw const QianjiImportException('无法读取该文件');
    }
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const QianjiImportException(
        '无法解析该文件，请确认是钱迹导出的 Excel 文件',
      );
    }
    if (excel.tables.isEmpty) {
      throw const QianjiImportException('文件中没有数据表');
    }
    final rows = excel.tables.values.first.rows;
    if (rows.isEmpty) {
      throw const QianjiImportException('文件是空的');
    }

    // 按表头名定位列，任何必需列缺失即认定不是钱迹文件
    final header = [for (final cell in rows.first) _cellText(cell)];
    int col(String name) => header.indexOf(name);
    final iTime = col('时间');
    final iCat = col('分类');
    final iSub = col('二级分类');
    final iType = col('类型');
    final iAmount = col('金额');
    final iNote = col('备注');
    final iTag = col('标签'); // 标签列可选，缺失则全部账单无标签
    if ([iTime, iCat, iSub, iType, iAmount, iNote].any((i) => i < 0)) {
      throw const QianjiImportException('表头缺少必需列，不是钱迹导出的账单文件');
    }

    final bills = <QianjiBill>[];
    final unsupported = <String, int>{};
    var badCount = 0;
    for (final row in rows.skip(1)) {
      final rawType = _cellAt(row, iType).trim();
      if (rawType.isEmpty) continue; // 空行
      if (!_supportedTypes.contains(rawType)) {
        // 退款/转账/还款/债务/报销等：本应用无对应类型，统计后跳过
        unsupported[rawType] = (unsupported[rawType] ?? 0) + 1;
        continue;
      }
      final amount = _amountToCents(_cellAt(row, iAmount));
      final time = _parseTime(_cellAt(row, iTime));
      if (amount == null || time == null) {
        badCount += 1;
        continue;
      }
      bills.add(
        QianjiBill(
          dateTime: time,
          type: rawType == '支出' ? BillType.expense : BillType.income,
          cat1: _cellAt(row, iCat).trim(),
          cat2: _cellAt(row, iSub).trim(),
          note: _cellAt(row, iNote).trim(),
          amountCents: amount,
          // 标签列可选；多标签按逗号/顿号/空格分割，去空去重
          tags: iTag < 0
              ? const []
              : _splitTags(_cellAt(row, iTag)),
        ),
      );
    }
    if (bills.isEmpty && unsupported.isEmpty) {
      throw const QianjiImportException('文件里没有可识别的账单');
    }
    return QianjiParseResult(
      bills: bills,
      unsupportedByType: unsupported,
      badCount: badCount,
    );
  }

  /// 单元格文本（越界与空值安全）
  static String _cellAt(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return _cellText(row[index]);
  }

  static String _cellText(Data? cell) {
    final value = cell?.value;
    return value == null ? '' : value.toString();
  }

  /// 金额文本转分：只接受非负的最多两位小数（钱迹导出均为正数金额）
  ///
  /// 纯字符串拆解，不走 double（避免浮点精度引入 179.999999 之类的偏差）
  static int? _amountToCents(String raw) {
    final text = raw.trim().replaceAll(RegExp(r'[¥￥,]'), '');
    if (text.isEmpty) return null;
    final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (m == null) return null;
    final fen = (m.group(2) ?? '').padRight(2, '0');
    return int.parse(m.group(1)!) * 100 + (fen.isEmpty ? 0 : int.parse(fen));
  }

  /// 时间解析：兼容字符串（"2026-10-07 10:21:08"）与 Excel 原生日期
  static DateTime? _parseTime(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  /// 标签分割：钱迹多标签以逗号/顿号/空格分隔，去空去重保序
  static List<String> _splitTags(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    final parts = text
        .split(RegExp(r'[、,，\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // 去重保序
    final seen = <String>{};
    return parts.where((s) => seen.add(s)).toList();
  }

  // ---------------- 分组与自动归级 ----------------

  /// 分组键（页面手动映射 Map 与分组对象共用）
  static String groupKey(BillType type, String cat1, String cat2) =>
      '${type.index}|$cat1|$cat2';

  /// 按 (类型, 一级, 二级) 分组并计算自动归级，组按笔数降序
  static List<QianjiGroup> buildGroups(
    List<QianjiBill> bills,
    List<Category> categories,
  ) {
    final byKey = <String, List<QianjiBill>>{};
    for (final bill in bills) {
      final list = byKey.putIfAbsent(
        groupKey(bill.type, bill.cat1, bill.cat2),
        () => [],
      );
      list.add(bill);
    }
    final keys = byKey.keys.toList()
      ..sort((a, b) => byKey[b]!.length.compareTo(byKey[a]!.length));
    return [
      for (final key in keys)
        QianjiGroup(
          key: key,
          type: byKey[key]!.first.type,
          cat1: byKey[key]!.first.cat1,
          cat2: byKey[key]!.first.cat2,
          count: byKey[key]!.length,
          totalCents: byKey[key]!.fold(0, (s, b) => s + b.amountCents),
          bills: byKey[key]!,
          autoMatch: _autoMatch(byKey[key]!.first, categories),
        ),
    ];
  }

  /// 自动归级：二级跨一级全局同名 → 一级同名（"其它"≡"其他"）→ null
  static Category? _autoMatch(QianjiBill bill, List<Category> categories) {
    final sameType = categories
        .where((c) => c.type == bill.type)
        .toList(growable: false);
    final cat2 = bill.cat2.trim();
    if (cat2.isNotEmpty) {
      for (final c in sameType) {
        if (c.parentId != null && c.name.trim() == cat2) return c;
      }
    }
    final cat1 = bill.cat1.trim() == '其它' ? '其他' : bill.cat1.trim();
    for (final c in sameType) {
      if (c.parentId == null && c.name.trim() == cat1) return c;
    }
    return null;
  }

  // ---------------- 写入与撤销 ----------------

  /// 执行导入：确保兜底"其它"分类存在 → 单批事务写入全部账单
  ///
  /// [manualTargets] 为映射页用户手动指定的分组映射（key = [groupKey]，
  /// value = 目标分类 id）；未指定的分组按 autoMatch，再无则落"其它"。
  /// 备注规则：手动映射与落"其它"的账单写"原分类:xx/yy"，纯同名自动
  /// 命中的不写；所有导入账单都带"来源:钱迹"。
  static Future<QianjiImportResult> importBills(
    AppDatabase db, {
    required List<QianjiGroup> groups,
    required Map<String, int> manualTargets,
    required int unsupportedCount,
    required int badCount,
  }) async {
    final batchId = DateTime.now().millisecondsSinceEpoch;
    final fallback = <BillType, Category>{};
    final companions = <BillsCompanion>[];
    var fallbackCount = 0;
    var expenseCount = 0;
    var incomeCount = 0;

    // 收集所有账单的标签名（去重），批量创建标签
    final tagNames = <String>{};
    for (final group in groups) {
      for (final bill in group.bills) {
        tagNames.addAll(bill.tags);
      }
    }
    final tagNameToId = <String, int>{};
    for (final name in tagNames) {
      // 复用 TagRepository 的幂等创建（同名返回已有 id）
      tagNameToId[name] = await TagRepository(db).addTag(name);
    }

    for (final group in groups) {
      final manual = manualTargets[group.key];
      Category? target;
      var withOriginCategory = false;
      if (manual != null) {
        target = await _categoryById(db, manual);
        withOriginCategory = true;
      } else if (group.autoMatch != null) {
        target = group.autoMatch;
      } else {
        target = fallback[group.type] ??= await _ensureOtherCategory(
          db,
          group.type,
        );
        withOriginCategory = true;
        fallbackCount += group.count;
      }

      final origin = group.cat2.isEmpty
          ? group.cat1
          : '${group.cat1}/${group.cat2}';
      for (final bill in group.bills) {
        companions.add(
          BillsCompanion.insert(
            type: bill.type,
            amountCents: bill.amountCents,
            categoryId: target!.id,
            note: Value(_buildNote(bill.note, origin, withOriginCategory)),
            date: DateTime(
              bill.dateTime.year,
              bill.dateTime.month,
              bill.dateTime.day,
            ),
            timeMinute: Value(bill.dateTime.hour * 60 + bill.dateTime.minute),
            importBatchId: Value(batchId),
          ),
        );
        if (bill.type == BillType.expense) {
          expenseCount += 1;
        } else {
          incomeCount += 1;
        }
      }
    }

    // batch 内部即单事务，全部成功或全部回滚
    await db.batch((b) => b.insertAll(db.bills, companions));

    // 关联标签：查出本批次全部账单 id，按顺序与 group.bills 对齐，
    // 批量写入 bill_tags（batch 单事务）
    if (tagNameToId.isNotEmpty) {
      final batchBills = await (db.select(db.bills)
            ..where((b) => b.importBatchId.equals(batchId))
            ..orderBy([(b) => OrderingTerm.asc(b.id)]))
          .get();
      // 按 groups 顺序展开所有 bill.tags，与 batchBills 按插入顺序对齐
      final allTags = [
        for (final g in groups)
          for (final b in g.bills) b.tags,
      ];
      final tagRows = <BillTagsCompanion>[];
      for (var i = 0; i < batchBills.length && i < allTags.length; i++) {
        for (final name in allTags[i]) {
          final tagId = tagNameToId[name];
          if (tagId != null) {
            tagRows.add(
              BillTagsCompanion.insert(
                billId: batchBills[i].id,
                tagId: tagId,
              ),
            );
          }
        }
      }
      if (tagRows.isNotEmpty) {
        await db.batch((b) => b.insertAll(db.billTags, tagRows));
      }
    }

    return QianjiImportResult(
      batchId: batchId,
      importedCount: companions.length,
      expenseCount: expenseCount,
      incomeCount: incomeCount,
      fallbackCount: fallbackCount,
      unsupportedCount: unsupportedCount,
      badCount: badCount,
    );
  }

  /// 备注拼接："原备注｜原分类:x/y｜来源:钱迹"，各段按需省略
  static String _buildNote(String note, String origin, bool withOrigin) {
    final buffer = StringBuffer();
    if (note.isNotEmpty) buffer.write(note);
    if (withOrigin) {
      if (buffer.isNotEmpty) buffer.write('｜');
      buffer.write('原分类:$origin');
    }
    if (buffer.isNotEmpty) buffer.write('｜');
    buffer.write('来源:钱迹');
    return buffer.toString();
  }

  /// 查询单个分类（手动映射的目标）
  static Future<Category> _categoryById(AppDatabase db, int id) async {
    final row = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const QianjiImportException('目标分类不存在，请刷新映射页后重试');
    }
    return row;
  }

  /// 确保该收支类型下存在"其他"一级分类（幂等；支出侧预置没有则创建）
  static Future<Category> _ensureOtherCategory(
    AppDatabase db,
    BillType type,
  ) async {
    // drift 只 show 导入时布尔扩展不可用，用两次 where 叠加表达 AND
    final roots =
        await (db.select(db.categories)
              ..where((c) => c.type.equalsValue(type))
              ..where((c) => c.parentId.isNull()))
            .get();
    for (final c in roots) {
      if (c.name.trim() == _fallbackName) return c;
    }
    final id = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: _fallbackName,
            iconCode: Icons.more_horiz.codePoint,
            colorValue: _fallbackColor,
            type: type,
          ),
        );
    return Category(
      id: id,
      name: _fallbackName,
      iconCode: Icons.more_horiz.codePoint,
      colorValue: _fallbackColor,
      type: type,
      parentId: null,
      sortOrder: 0,
    );
  }

  /// 整批撤销：删除某次导入的全部账单，返回删除条数
  static Future<int> deleteBatch(AppDatabase db, int batchId) =>
      (db.delete(db.bills)..where((bl) => bl.importBatchId.equals(batchId)))
          .go();

  /// 导入前留底：当前库快照存为"钱迹导入前备份"（幂等失败不阻断）
  ///
  /// 与恢复备份的留底同为文件级 VACUUM INTO 快照，进入备份页历史列表；
  /// 失败静默——整批撤销是主兜底，不因留底失败阻断导入。
  static Future<void> backupBeforeImport() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dir.path, kDatabaseFileName));
      if (!await dbFile.exists()) return;
      Database? raw;
      try {
        raw = sqlite3.open(dbFile.path);
        raw.execute(
          "VACUUM INTO '${p.join(dir.path, 'chestnut_before_qianji_${_stamp()}.sqlite')}'",
        );
      } finally {
        raw?.dispose();
      }
    } catch (_) {
      // 留底失败不阻断导入
    }
  }

  /// 时间戳（留底文件名用，形如 20261007_183000）
  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}'
        '_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
