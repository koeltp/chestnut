import 'package:flutter_test/flutter_test.dart';

import 'package:chestnut/data/database.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/utils/credit_bill_cycle.dart';

void main() {
  Bill bill(DateTime date, BillType type, int amountCents) => Bill(
    id: 0,
    type: type,
    amountCents: amountCents,
    date: date,
    createdAt: date,
  );

  group('creditCycleStart 本期账单周期起点', () {
    test('已过出账日 → 本月出账日', () {
      expect(
        creditCycleStart(5, DateTime(2026, 11, 15)),
        DateTime(2026, 11, 5),
      );
    });

    test('未到出账日 → 上月出账日', () {
      expect(creditCycleStart(5, DateTime(2026, 11, 3)), DateTime(2026, 10, 5));
    });

    test('当天即出账日 → 含今天', () {
      expect(creditCycleStart(5, DateTime(2026, 11, 5)), DateTime(2026, 11, 5));
    });

    test('31 号出账日在小月按月末处理', () {
      // 11 月 15 日，本月无 31 号：起点 = 上月 31 号
      expect(
        creditCycleStart(31, DateTime(2026, 11, 15)),
        DateTime(2026, 10, 31),
      );
      // 12 月 15 日：本月 31 号未到，上月 11 月 30 号
      expect(
        creditCycleStart(31, DateTime(2026, 12, 15)),
        DateTime(2026, 11, 30),
      );
    });

    test('非法出账日返回 null', () {
      expect(creditCycleStart(null, DateTime(2026, 11, 15)), isNull);
      expect(creditCycleStart(0, DateTime(2026, 11, 15)), isNull);
      expect(creditCycleStart(32, DateTime(2026, 11, 15)), isNull);
    });
  });

  group('unbilledCents 未出账单推算', () {
    final now = DateTime(2026, 11, 15);

    test('周期起点含当天：出账日当天与之后的支出计入', () {
      final bills = [
        bill(DateTime(2026, 11, 5), BillType.expense, 2000),
        bill(DateTime(2026, 11, 6), BillType.expense, 3000),
      ];
      expect(unbilledCents(billDay: 5, now: now, bills: bills), 5000);
    });

    test('上期支出不计入', () {
      final bills = [bill(DateTime(2026, 11, 4), BillType.expense, 5000)];
      expect(unbilledCents(billDay: 5, now: now, bills: bills), 0);
    });

    test('今天支出计入', () {
      final bills = [bill(DateTime(2026, 11, 15), BillType.expense, 9900)];
      expect(unbilledCents(billDay: 5, now: now, bills: bills), 9900);
    });

    test('收入（如退货退款）冲减未出', () {
      final bills = [
        bill(DateTime(2026, 11, 6), BillType.expense, 5000),
        bill(DateTime(2026, 11, 7), BillType.income, 800),
      ];
      expect(unbilledCents(billDay: 5, now: now, bills: bills), 4200);
    });

    test('转账忽略：还款转入冲已出未还，不影响未出', () {
      final bills = [
        bill(DateTime(2026, 11, 6), BillType.expense, 5000),
        bill(DateTime(2026, 11, 7), BillType.transfer, 80000),
      ];
      expect(unbilledCents(billDay: 5, now: now, bills: bills), 5000);
    });

    test('跨月周期：月初未到出账日时窗口从上月出账日起', () {
      final nov3 = DateTime(2026, 11, 3);
      final bills = [
        // 10 月 20 日在本期窗口（上期出账日 10-05 之后）
        bill(DateTime(2026, 10, 20), BillType.expense, 1200),
        bill(DateTime(2026, 10, 4), BillType.expense, 3000),
      ];
      expect(unbilledCents(billDay: 5, now: nov3, bills: bills), 1200);
    });

    test('未填出账日返回 null = 推算不出', () {
      final bills = [bill(DateTime(2026, 11, 6), BillType.expense, 5000)];
      expect(unbilledCents(billDay: null, now: now, bills: bills), isNull);
    });

    test('无流水推算为 0', () {
      expect(unbilledCents(billDay: 5, now: now, bills: const []), 0);
    });
  });
}
