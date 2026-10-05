import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../utils/money_util.dart';
import '../utils/month_util.dart';

/// 账单导出服务：全量账单 → CSV 文件
///
/// 导出内容含 BOM 头，保证 Excel 直接打开不乱码；
/// 金额以"元"写入，便于导出后直接查看与核算。
class ExportService {
  ExportService(this._db);

  final AppDatabase _db;

  /// 生成 CSV 并返回文件
  Future<File> exportCsv() async {
    final bills = await _db.select(_db.bills).get();
    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };

    // 按日期正序导出，便于追溯
    bills.sort((a, b) => a.date.compareTo(b.date));

    final rows = <List<dynamic>>[
      ['日期', '类型', '分类', '金额(元)', '备注'],
      ...bills.map(
        (b) => [
          _formatDate(b.date),
          b.type.label,
          categories[b.categoryId]?.name ?? '未知分类',
          MoneyUtil.centsToYuan(b.amountCents),
          b.note ?? '',
        ],
      ),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/chestnut_${MonthUtil.toKey(DateTime.now())}.csv',
    );
    // 字符串首部携带 UTF-8 BOM（\uFEFF），让 Excel 正确识别中文
    return file.writeAsString('\uFEFF$csv', encoding: utf8);
  }
}

/// 日期格式化：yyyy-MM-dd
String _formatDate(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}
