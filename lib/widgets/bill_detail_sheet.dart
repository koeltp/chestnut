import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/enums.dart';
import '../pages/add_bill/add_bill_page.dart';
import '../providers/bill_provider.dart';
import '../theme/app_colors.dart';
import '../utils/money_util.dart';
import 'category_avatar.dart';

/// 账单详情底部弹窗：点击明细条目时展示完整信息，代替"直接进编辑页"
///
/// 操作：复制（预填数据另存一笔）/ 修改（编辑该笔）/ 删除（二次确认）；
/// 点击分类行先关闭详情，再由宿主跳转该分类的统计视图
/// （首页 push 统计页 / 统计页内部钻取，见 [onCategoryTap]）
Future<void> showBillDetailSheet(
  BuildContext context, {
  required Bill bill,
  required Map<int, Category> categories,
  required void Function(Category category) onCategoryTap,
}) {
  // 同步取好 Provider，删除时不再跨 async gap 访问 context
  final provider = context.read<BillProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    // 解除默认 9/16 屏高度限制：超长地址/备注时内容可撑满屏幕
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => _DetailBody(
      bill: bill,
      categories: categories,
      onCategoryTap: onCategoryTap,
      hostContext: context,
      provider: provider,
    ),
  );
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.bill,
    required this.categories,
    required this.onCategoryTap,
    required this.hostContext,
    required this.provider,
  });

  final Bill bill;
  final Map<int, Category> categories;
  final void Function(Category category) onCategoryTap;

  /// 宿主页 context：详情弹窗 pop 后用宿主 context 压栈新页面，
  /// 避免 sheet 内部 context 失效
  final BuildContext hostContext;
  final BillProvider provider;

  /// 打开记一笔页：修改 = 编辑该笔；复制 = 预填数据保存为新记录
  void _openEditor(bool edit) {
    Navigator.of(hostContext).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            edit ? AddBillPage(editBill: bill) : AddBillPage(copyOf: bill),
      ),
    );
  }

  /// 删除（二次确认）：确认后先关详情再写库，列表由流自动刷新
  Future<void> _confirmDelete(BuildContext sheetContext) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账单'),
        content: const Text('确定删除这条账单吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    await provider.deleteBill(bill.id);
  }

  /// 点击分类行：先关详情再交给宿主跳转，避免返回时又回到已关闭的弹窗
  void _tapCategory(BuildContext sheetContext) {
    final c = categories[bill.categoryId];
    if (c == null) return;
    Navigator.of(sheetContext).pop();
    onCategoryTap(c);
  }

  /// 时间显示格式：2026-10-02 18:08
  String _format(DateTime t, int? timeMinute) {
    final tm = timeMinute ?? t.hour * 60 + t.minute;
    final hh = (tm ~/ 60).toString().padLeft(2, '0');
    final mm = (tm % 60).toString().padLeft(2, '0');
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    return '${t.year}-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = bill.type == BillType.expense;
    final amountColor = isExpense ? AppColors.expense : AppColors.income;
    final category = categories[bill.categoryId];
    // 位置展示用完整地址（含店名），无完整地址退回短地名
    final location = bill.locationFull ?? bill.location;
    return SafeArea(
      // 内容可滚动：超长地址/备注撑满屏幕时滚动查看，不截断不溢出
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：标题 + 操作胶囊（删除红底红字提示危险操作）
              Row(
                children: [
                  const Text(
                    '详情',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  _pill('复制', onTap: () => _openEditor(false)),
                  const SizedBox(width: 8),
                  _pill('修改', onTap: () => _openEditor(true)),
                  const SizedBox(width: 8),
                  _pill('删除', red: true, onTap: () => _confirmDelete(context)),
                ],
              ),
              const SizedBox(height: 6),
              _Row(
                label: '金额',
                child: Text(
                  '${isExpense ? '-' : '+'}¥'
                  '${MoneyUtil.centsToYuanGroupedTrimmed(bill.amountCents)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: amountColor,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              _Row(
                label: '分类',
                onTap: category == null ? null : () => _tapCategory(context),
                child: category == null
                    ? const Text(
                        '未知分类',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 文字图标：行内显示名称首字（无圆底小字）
                          category.iconCode == kTextIconCode
                              ? Text(
                                  category.name.isEmpty
                                      ? '?'
                                      : category.name.characters.first,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: Color(category.colorValue),
                                  ),
                                )
                              : Icon(
                                  IconData(
                                    // ignore: non_const_argument_for_const_parameter
                                    category.iconCode,
                                    fontFamily: 'MaterialIcons',
                                  ),
                                  size: 16,
                                  color: Color(category.colorValue),
                                ),
                          const SizedBox(width: 6),
                          Text(
                            category.name,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              _Row(
                label: '时间',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _format(bill.date, bill.timeMinute),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '记录于 ${_format(bill.createdAt, null)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              _Row(
                label: '备注',
                child: Text(
                  bill.note ?? '未添加备注',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    color: bill.note == null
                        ? AppColors.textSecondary.withValues(alpha: 0.7)
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (location != null) ...[
                const Divider(height: 1, color: AppColors.divider),
                _Row(
                  label: '位置',
                  child: Text(
                    location,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// 操作胶囊：常规操作浅灰底，删除红底红字
  Widget _pill(String text, {required VoidCallback onTap, bool red = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: red
              ? AppColors.expense.withValues(alpha: 0.08)
              : AppColors.fill,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: red ? AppColors.expense : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 详情信息行：左侧灰色字段名，右侧值；整行可点（分类跳转）
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.onTap});

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        // 值拿满标签右侧全部宽度：短值靠右（child 自行右对齐），
        // 长值（地址/备注）自动折行，最多 3 行
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
