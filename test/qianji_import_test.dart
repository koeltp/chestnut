import 'package:chestnut/data/database.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/services/qianji_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 钱迹导入纯逻辑测试：金额解析、时间解析、标签拆分、分组聚合
///
/// 这些函数处理的是外部脏数据，边角 case 多，是最容易在真实导入时翻车的地方。
void main() {
  group('amountToCents', () {
    test('整数与两位小数', () {
      expect(QianjiImportService.amountToCents('123'), 12300);
      expect(QianjiImportService.amountToCents('123.45'), 12345);
      expect(QianjiImportService.amountToCents('0.05'), 5);
    });

    test('剥离货币符号与千分位', () {
      expect(QianjiImportService.amountToCents('¥1,234.56'), 123456);
      expect(QianjiImportService.amountToCents('￥1,234'), 123400);
    });

    test('一位小数补零', () {
      expect(QianjiImportService.amountToCents('12.3'), 1230);
    });

    test('空与非法返回 null', () {
      expect(QianjiImportService.amountToCents(''), null);
      expect(QianjiImportService.amountToCents('abc'), null);
      expect(QianjiImportService.amountToCents('12.345'), null); // 超两位
      expect(QianjiImportService.amountToCents('-10'), null);
    });
  });

  group('parseTime', () {
    test('标准格式解析', () {
      final t = QianjiImportService.parseTime('2026-10-07 10:21:08');
      expect(t, isNotNull);
      expect(t!.year, 2026);
      expect(t.month, 10);
      expect(t.day, 7);
    });

    test('空返回 null', () {
      expect(QianjiImportService.parseTime(''), null);
      expect(QianjiImportService.parseTime('not-a-date'), null);
    });
  });

  group('splitTags', () {
    test('多种分隔符混合', () {
      expect(
        QianjiImportService.splitTags('早餐,午餐 晚餐、夜宵'),
        ['早餐', '午餐', '晚餐', '夜宵'],
      );
    });

    test('去空去重保序', () {
      expect(
        QianjiImportService.splitTags('早餐, 早餐 ,午餐,,午餐'),
        ['早餐', '午餐'],
      );
    });

    test('空串返回空列表', () {
      expect(QianjiImportService.splitTags(''), []);
      expect(QianjiImportService.splitTags('   '), []);
    });
  });

  group('buildGroups', () {
    final now = DateTime(2026, 10, 7);
    QianjiBill bill(
      BillType type,
      String cat1,
      String cat2,
      int cents,
    ) => QianjiBill(
      dateTime: now,
      type: type,
      cat1: cat1,
      cat2: cat2,
      note: '',
      amountCents: cents,
    );

    test('按 (类型,一级,二级) 分组，笔数降序', () {
      final bills = [
        bill(BillType.expense, '餐饮', '早餐', 1000),
        bill(BillType.expense, '餐饮', '早餐', 2000),
        bill(BillType.expense, '交通', '', 500),
        bill(BillType.income, '工资', '', 10000),
      ];
      final groups = QianjiImportService.buildGroups(bills, []);
      // 3 个唯一组
      expect(groups.length, 3);
      // 笔数降序：餐饮/早餐(2) > 交通(1) = 工资(1)
      expect(groups.first.count, 2);
      expect(groups.first.cat2, '早餐');
      expect(groups.first.totalCents, 3000);
    });

    test('groupKey 格式稳定', () {
      expect(
        QianjiImportService.groupKey(BillType.expense, '餐饮', '早餐'),
        '${BillType.expense.index}|餐饮|早餐',
      );
    });

    test('自动归级：二级命中已有二级分类', () {
      final categories = [
        Category(
          id: 1,
          name: '餐饮',
          iconCode: 0,
          colorValue: 0,
          type: BillType.expense,
          parentId: null,
          sortOrder: 0,
        ),
        Category(
          id: 2,
          name: '早餐',
          iconCode: 0,
          colorValue: 0,
          type: BillType.expense,
          parentId: 1,
          sortOrder: 0,
        ),
      ];
      final bills = [bill(BillType.expense, '餐饮', '早餐', 100)];
      final groups = QianjiImportService.buildGroups(bills, categories);
      expect(groups.single.autoMatch?.id, 2);
    });

    test('钱迹"其它"归级到栗子"其他"', () {
      final categories = [
        Category(
          id: 1,
          name: '其他',
          iconCode: 0,
          colorValue: 0,
          type: BillType.expense,
          parentId: null,
          sortOrder: 0,
        ),
      ];
      final bills = [bill(BillType.expense, '其它', '', 100)];
      final groups = QianjiImportService.buildGroups(bills, categories);
      expect(groups.single.autoMatch?.id, 1);
    });
  });
}
