import 'dart:async';

import 'package:flutter/material.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/enums.dart';
import '../pages/add_bill/add_bill_page.dart';
import '../providers/bill_provider.dart';
import '../theme/app_colors.dart';
import '../utils/money_util.dart';
import '../utils/show_toast.dart';
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

class _DetailBody extends StatefulWidget {
  const _DetailBody({
    required this.bill,
    required this.categories,
    required this.onCategoryTap,
    required this.hostContext,
    required this.provider,
  });

  /// 点击条目时的账单快照：仅作初始显示值与订阅键，
  /// 之后展示一律以单条流推送的最新值为准
  final Bill bill;
  final Map<int, Category> categories;
  final void Function(Category category) onCategoryTap;

  /// 宿主页 context：详情弹窗 pop 后用宿主 context 压栈新页面，
  /// 避免 sheet 内部 context 失效
  final BuildContext hostContext;
  final BillProvider provider;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  /// 最新账单：创建时取宿主传入的快照，之后由单条流推送覆盖；
  /// 编辑/复制/删除都必须操作它，避免拿到关闭弹窗前的旧数据
  late Bill _current = widget.bill;
  StreamSubscription<Bill?>? _sub;

  @override
  void initState() {
    super.initState();
    // 订阅单条账单流：编辑保存后弹窗自动刷新；
    // 账单被删（null）时自动关闭弹窗，避免展示已不存在的数据
    _sub = widget.provider.watchBillById(widget.bill.id).listen((bill) {
      if (!mounted) return;
      if (bill == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _current = bill);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// 打开记一笔页：修改 = 编辑该笔；复制 = 预填数据保存为新记录。
  /// 必须用最新值 _current：若操作前数据库已被其它路径改过，
  /// 用打开弹窗时的旧快照进编辑页会回显过期数据
  void _openEditor(bool edit) {
    Navigator.of(widget.hostContext).push(
      MaterialPageRoute<void>(
        builder: (_) => edit
            ? AddBillPage(editBill: _current)
            : AddBillPage(copyOf: _current),
      ),
    );
  }

  /// 删除（二次确认）：确认后先关详情再写库，列表由流自动刷新；
  /// 弹窗已关闭、订阅已取消，删除不会触发本页的 null 自动 pop
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
    await widget.provider.deleteBill(_current.id);
  }

  /// 点击分类行：先关详情再交给宿主跳转，避免返回时又回到已关闭的弹窗
  void _tapCategory(BuildContext sheetContext) {
    final c = widget.categories[_current.categoryId];
    if (c == null) return;
    Navigator.of(sheetContext).pop();
    widget.onCategoryTap(c);
  }

  /// 点击位置行：拉起手机上已安装的地图 App，在该笔消费地点打点。
  /// 只"查看位置"不直接开始导航——查旧账多为确认店在哪，导航动作过重。
  ///
  /// 库存坐标是 GCJ-02（高德系）：map_launcher 对高德/腾讯直传，
  /// 对百度以 coord_type=gcj02 声明由百度自转 BD-09，无需手动纠偏。
  Future<void> _tapLocation() async {
    final lat = _current.lat;
    final lng = _current.lng;
    if (lat == null || lng == null) return;
    final request = MapLauncher.marker(
      LocationCoords(lat, lng, title: _current.location),
    );
    // 只提供国内主流四家；未安装原生 App 的不列：
    // 高德/百度只有 scheme 没有网页兜底，谷歌网页版在国内打不开
    final candidates = await request.getSupportedMaps(const [
      MapApp.amap,
      MapApp.baidu,
      MapApp.tencent,
      MapApp.google,
    ]);
    if (!mounted) return;
    final installed = candidates.where((m) => m.isInstalled).toList();
    if (installed.isEmpty) {
      showAppToast(context, '未检测到已安装的地图应用');
      return;
    }
    if (installed.length == 1) {
      await _openMap(installed.single);
      return;
    }
    final picked = await _showMapPicker(installed);
    if (picked != null) await _openMap(picked);
  }

  /// 拉起指定地图；scheme 偶发失效时插件内部已尝试 universal link 兜底
  Future<void> _openMap(SupportedMap map) async {
    try {
      await map.show();
    } on MapLaunchException {
      if (mounted) showAppToast(context, '打开地图失败，请重试');
    }
  }

  /// 多地图选择面板：白色圆角底部弹窗，风格与详情弹窗一致
  Future<SupportedMap?> _showMapPicker(List<SupportedMap> maps) {
    return showModalBottomSheet<SupportedMap>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '选择地图应用',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final m in maps)
              ListTile(
                leading: Image.memory(m.iconBytes, width: 32, height: 32),
                title: Text(_mapLabel(m)),
                titleTextStyle: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// 地图 App 中文名映射：插件自带 name 是英文
  String _mapLabel(SupportedMap m) => switch (m.map.id) {
        'amap' => '高德地图',
        'baidu' => '百度地图',
        'tencent' => '腾讯地图',
        'google' => 'Google 地图',
        _ => m.name,
      };

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
    final isExpense = _current.type == BillType.expense;
    final amountColor = isExpense ? AppColors.expense : AppColors.income;
    final category = widget.categories[_current.categoryId];
    // 位置展示用完整地址（含店名），无完整地址退回短地名
    final location = _current.locationFull ?? _current.location;
    // 仅精确坐标的账单可跳地图；只有行政区地名的旧账保持纯文字
    final hasLocationPoint = _current.lat != null && _current.lng != null;
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
                  '${MoneyUtil.centsToYuanGroupedTrimmed(_current.amountCents)}',
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
                      _format(_current.date, _current.timeMinute),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '记录于 ${_format(_current.createdAt, null)}',
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
                  _current.note ?? '未添加备注',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    color: _current.note == null
                        ? AppColors.textSecondary.withValues(alpha: 0.7)
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (location != null) ...[
                const Divider(height: 1, color: AppColors.divider),
                _Row(
                  label: '位置',
                  onTap: hasLocationPoint ? _tapLocation : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          location,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      // 地图跳转 affordance：暗示此行可点
                      if (hasLocationPoint)
                        const Padding(
                          padding: EdgeInsets.only(top: 1, left: 4),
                          child: Icon(
                            Icons.map_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
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
