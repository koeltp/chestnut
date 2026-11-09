import '../../models/enums.dart';

/// 加账单保存校验的纯函数：不依赖 BuildContext，只返回校验结果。
///
/// 原校验逻辑内嵌在 `add_bill_page.save.dart` 的 `_save` 方法里，
/// 与 UI 层（showAppToast）耦合。抽成纯函数后可以独立测试边界条件，
/// UI 层只需根据返回值决定是否 toast + return。
///
/// 返回 null = 全部通过；返回 String = 错误提示文案
String? validateBillDraft({
  required BillType type,
  required int amountCents,
  int? discountCents,
  required int? selectedCategoryId,
  required int? selectedAssetId,
  required int? toAssetId,
}) {
  // 金额校验：实付允许为 0（免单），但无优惠时实付必须 >0
  if (amountCents == 0 && discountCents == null) {
    return '请输入正确的金额';
  }
  // 转账：两账户必选且不能相同
  if (type == BillType.transfer) {
    if (selectedAssetId == null || toAssetId == null) {
      return '请选择转出与转入账户';
    }
    if (selectedAssetId == toAssetId) {
      return '转出与转入不能是同一账户';
    }
  } else if (selectedCategoryId == null) {
    // 收入/支出：分类必选
    return '请选择分类';
  }
  return null;
}
