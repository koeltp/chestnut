import 'package:chestnut/models/enums.dart';
import 'package:chestnut/pages/add_bill/add_bill_validation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 加账单保存校验纯函数的边界条件测试
///
/// 覆盖：空金额、转账双账户、转账同账户、缺分类、免单（金额 0 有优惠）通过
void main() {
  group('validateBillDraft', () {
    // ---- 空金额 / 免单 ----

    test('支出：金额 0 无优惠 → 拒绝', () {
      final err = validateBillDraft(
        type: BillType.expense,
        amountCents: 0,
        discountCents: null,
        selectedCategoryId: 1,
        selectedAssetId: 1,
        toAssetId: null,
      );
      expect(err, '请输入正确的金额');
    });

    test('支出：金额 0 有优惠 → 通过（免单）', () {
      final err = validateBillDraft(
        type: BillType.expense,
        amountCents: 0,
        discountCents: 100,
        selectedCategoryId: 1,
        selectedAssetId: 1,
        toAssetId: null,
      );
      expect(err, isNull);
    });

    test('支出：正常金额 → 通过', () {
      final err = validateBillDraft(
        type: BillType.expense,
        amountCents: 1000,
        discountCents: null,
        selectedCategoryId: 1,
        selectedAssetId: 1,
        toAssetId: null,
      );
      expect(err, isNull);
    });

    // ---- 转账 ----

    test('转账：只填一个账户 → 拒绝', () {
      final err = validateBillDraft(
        type: BillType.transfer,
        amountCents: 1000,
        discountCents: null,
        selectedCategoryId: null,
        selectedAssetId: 1,
        toAssetId: null,
      );
      expect(err, '请选择转出与转入账户');
    });

    test('转账：两个账户相同 → 拒绝', () {
      final err = validateBillDraft(
        type: BillType.transfer,
        amountCents: 1000,
        discountCents: null,
        selectedCategoryId: null,
        selectedAssetId: 5,
        toAssetId: 5,
      );
      expect(err, '转出与转入不能是同一账户');
    });

    test('转账：两账户不同 → 通过（不需要分类）', () {
      final err = validateBillDraft(
        type: BillType.transfer,
        amountCents: 1000,
        discountCents: null,
        selectedCategoryId: null,
        selectedAssetId: 3,
        toAssetId: 7,
      );
      expect(err, isNull);
    });

    // ---- 收入 ----

    test('收入：缺分类 → 拒绝', () {
      final err = validateBillDraft(
        type: BillType.income,
        amountCents: 1000,
        discountCents: null,
        selectedCategoryId: null,
        selectedAssetId: 1,
        toAssetId: null,
      );
      expect(err, '请选择分类');
    });

    test('收入：有分类 → 通过', () {
      final err = validateBillDraft(
        type: BillType.income,
        amountCents: 1000,
        discountCents: null,
        selectedCategoryId: 2,
        selectedAssetId: 1,
        toAssetId: null,
      );
      expect(err, isNull);
    });

    // ---- 优先级：转账同账户 优先于 空金额 ----

    test('转账空金额：空金额提示优先', () {
      // 先校验金额（金额 0 无优惠），再校验转账账户
      final err = validateBillDraft(
        type: BillType.transfer,
        amountCents: 0,
        discountCents: null,
        selectedCategoryId: null,
        selectedAssetId: 1,
        toAssetId: null,
      );
      expect(err, '请输入正确的金额');
    });
  });
}
