/// 信用卡账单周期与欠款拆分推算（纯展示用，不入库）
///
/// 欠款总额是唯一落库事实（assets.valueCents，手填锚点）；
/// "已出未还 + 未出账单"只是编辑时的临时录入形态：
/// 未出账单由出账日 + 卡上流水推算预填，已出未还 = 总额 − 未出，
/// 保存时两者之和写回总额，拆分本身不存。
///
/// 口径：未出账单 = 本期周期内记在该卡上的 支出 − 收入。
/// 转账不计入——还款转入冲的是已出未还（总额减法自然体现），
/// 分期/利息等未记成账单的变动会造成推算漂移，以手填总额为准。
library;

import '../data/database.dart';
import '../models/enums.dart';

/// 本期账单周期起点（含当天）：最近一次出账日。
///
/// [billDay] 不在 1~31 返回 null；出账日大于当月天数按当月
/// 月末处理（如 31 号在 11 月视为 30 号，与银行"顺延"口径近似）
DateTime? creditCycleStart(int? billDay, DateTime now) {
  final day = billDay;
  if (day == null || day < 1 || day > 31) return null;
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  if (now.day >= day.clamp(1, daysInMonth)) {
    return DateTime(now.year, now.month, day.clamp(1, daysInMonth));
  }
  final lastOfPrev = DateTime(now.year, now.month, 0);
  final prevDays = DateTime(lastOfPrev.year, lastOfPrev.month + 1, 0).day;
  return DateTime(lastOfPrev.year, lastOfPrev.month, day.clamp(1, prevDays));
}

/// 未出账单推算：本期周期内（起点含当天至今天）该卡上的支出 − 收入。
///
/// [bills] 为该卡的流水（支出/收入的 assetId = 卡；转账按类型忽略，
/// 无论转出转入）。[billDay] 未填返回 null = 推算不出，调用方退化为
/// 全部按已出处理；周期内无流水则推算结果为 0。
int? unbilledCents({
  required int? billDay,
  required DateTime now,
  required List<Bill> bills,
}) {
  final start = creditCycleStart(billDay, now);
  if (start == null) return null;
  final endExclusive = DateTime(now.year, now.month, now.day + 1);
  var cents = 0;
  for (final bill in bills) {
    if (bill.date.isBefore(start) || !bill.date.isBefore(endExclusive)) {
      continue;
    }
    cents += switch (bill.type) {
      BillType.expense => bill.amountCents,
      BillType.income => -bill.amountCents,
      BillType.transfer => 0,
    };
  }
  return cents;
}
