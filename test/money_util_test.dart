import 'package:chestnut/utils/money_util.dart';
import 'package:flutter_test/flutter_test.dart';

/// MoneyUtil 纯函数测试：分↔元转换与格式化
///
/// 金额是应用的核心数据，全应用统一以"分"存储，转换逻辑必须零偏差。
/// 重点覆盖：小数截断、千分位、零头省略、负数、非法输入。
void main() {
  group('centsToYuan', () {
    test('常规分转元保留两位小数', () {
      expect(MoneyUtil.centsToYuan(12345), '123.45');
      expect(MoneyUtil.centsToYuan(100), '1.00');
      expect(MoneyUtil.centsToYuan(0), '0.00');
    });

    test('不足一元补零', () {
      expect(MoneyUtil.centsToYuan(5), '0.05');
      expect(MoneyUtil.centsToYuan(99), '0.99');
    });

    test('负数带负号', () {
      expect(MoneyUtil.centsToYuan(-12345), '-123.45');
      expect(MoneyUtil.centsToYuan(-5), '-0.05');
    });
  });

  group('centsToYuanTrimmed', () {
    test('零头为 0 省略小数', () {
      expect(MoneyUtil.centsToYuanTrimmed(12300), '123');
      expect(MoneyUtil.centsToYuanTrimmed(100), '1');
      expect(MoneyUtil.centsToYuanTrimmed(0), '0');
    });

    test('有零头保留两位', () {
      expect(MoneyUtil.centsToYuanTrimmed(12345), '123.45');
    });
  });

  group('centsToYuanGrouped', () {
    test('千分位分组', () {
      expect(MoneyUtil.centsToYuanGrouped(1234567), '12,345.67');
      expect(MoneyUtil.centsToYuanGrouped(100000000), '1,000,000.00');
    });

    test('千分位 + 零头省略', () {
      expect(MoneyUtil.centsToYuanGroupedTrimmed(1200000), '12,000');
      expect(MoneyUtil.centsToYuanGroupedTrimmed(1234567), '12,345.67');
    });
  });

  group('yuanToCents', () {
    test('元字符串转分', () {
      expect(MoneyUtil.yuanToCents('123.45'), 12345);
      expect(MoneyUtil.yuanToCents('1'), 100);
      expect(MoneyUtil.yuanToCents('0.05'), 5);
    });

    test('空与非法返回 null', () {
      expect(MoneyUtil.yuanToCents(''), null);
      expect(MoneyUtil.yuanToCents('  '), null);
      expect(MoneyUtil.yuanToCents('abc'), null);
      expect(MoneyUtil.yuanToCents('-1'), null); // 负数非法
    });

    test('浮点精度回归：0.29 元 = 29 分', () {
      // double 0.29 * 100 = 28.999…，round 后应为 29
      expect(MoneyUtil.yuanToCents('0.29'), 29);
      expect(MoneyUtil.yuanToCents('179.99'), 17999);
    });
  });
}
