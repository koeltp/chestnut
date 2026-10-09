import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/repositories/bill_image_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../models/enums.dart';
import '../pages/add_bill/add_bill_page.dart';
import '../providers/bill_provider.dart';
import '../providers/cloud_storage_provider.dart';
import '../theme/app_colors.dart';
import '../utils/money_util.dart';
import '../utils/show_toast.dart';
import 'category_avatar.dart';
import 'photo_viewer_page.dart';

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
  void Function(Tag tag)? onTagTap,
}) {
  // 同步取好 Provider，删除时不再跨 async gap 访问 context
  final provider = context.read<BillProvider>();
  final tagRepo = context.read<TagRepository>();
  final imageRepo = context.read<BillImageRepository>();
  final cloud = context.read<CloudStorageProvider>();
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
      onTagTap: onTagTap,
      hostContext: context,
      provider: provider,
      tagRepo: tagRepo,
      imageRepo: imageRepo,
      cloud: cloud,
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
    required this.tagRepo,
    required this.imageRepo,
    required this.cloud,
    this.onTagTap,
  });

  /// 点击条目时的账单快照：弹窗是纯静态展示面板，打开期间数据库
  /// 不会经由其它路径变更（所有增删改都从本弹窗发起，发起即先关弹窗）
  final Bill bill;

  /// 打开弹窗时的分类字典快照（同上，弹窗存活期间不会被变更）
  final Map<int, Category> categories;
  final void Function(Category category) onCategoryTap;

  /// 点击标签回调：宿主跳转到该标签的账单筛选视图
  final void Function(Tag tag)? onTagTap;

  /// 宿主页 context：详情弹窗 pop 后用宿主 context 压栈新页面，
  /// 避免 sheet 内部 context 失效
  final BuildContext hostContext;
  final BillProvider provider;
  final TagRepository tagRepo;

  /// 图片仓储与云存储配置：图片条加载/云端兜底/手动重传
  final BillImageRepository imageRepo;
  final CloudStorageProvider cloud;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  /// 该账单的标签列表（打开弹窗时加载一次）
  List<Tag> _tags = [];

  /// 该账单的图片列表（流订阅：上传状态变化自动刷新）
  List<BillImage> _images = [];
  StreamSubscription<List<BillImage>>? _imageSub;

  /// imageId → 本地文件（null = 本地缺失且云端拉回失败，显示占位）
  final Map<int, File?> _localFiles = {};

  @override
  void initState() {
    super.initState();
    _loadTags();
    // 订阅图片流：手动重传改状态、后台补传完成都会推新数据
    _imageSub = widget.imageRepo
        .watchImagesByBillId(widget.bill.id)
        .listen((images) {
      if (!mounted) return;
      setState(() => _images = images);
      unawaited(_ensureFiles(images));
    });
  }

  @override
  void dispose() {
    unawaited(_imageSub?.cancel());
    super.dispose();
  }

  /// 加载该账单的标签
  Future<void> _loadTags() async {
    final tags = await widget.tagRepo.getTagsByBillId(widget.bill.id);
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  /// 确保每张图都有本地文件可用（读取永远本地优先）：
  /// 缓存缺失的记录按 objectKey 从云端拉回落盘；拉取失败缓存 null
  /// 显示占位（重开弹窗可重试）
  Future<void> _ensureFiles(List<BillImage> images) async {
    for (final img in images) {
      if (_localFiles.containsKey(img.id)) continue;
      final local = File(img.localPath);
      if (await local.exists()) {
        if (mounted) setState(() => _localFiles[img.id] = local);
        continue;
      }
      final client = widget.cloud.createClient();
      if (client == null) {
        // 云存储已解绑：无兜底来源，保持占位
        if (mounted) setState(() => _localFiles[img.id] = null);
        continue;
      }
      final file = await widget.imageRepo.ensureLocalFile(img, client);
      if (!mounted) return;
      setState(() => _localFiles[img.id] = file);
    }
  }

  /// 全屏预览：从被点的那张进入，左右滑可看该账单其余图片
  void _preview(BillImage img) {
    // 只收集本地文件已就绪的图；当前图未就绪不打开（等云端拉回后刷新）
    final paths = <String>[];
    var index = 0;
    for (final i in _images) {
      final file = _localFiles[i.id];
      if (file == null) continue;
      if (identical(i, img)) index = paths.length;
      paths.add(file.path);
    }
    if (paths.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(
          paths: paths,
          initialIndex: index,
          // Hero 过渡以被点那张为准：缩略图飞出放大，关闭时飞回
          openHeroTag: img.localPath,
        ),
      ),
    );
  }

  /// 手动重传（"未上传"角标点击）：结果 toast，状态变化由流刷新缩略图
  Future<void> _reupload(BillImage img) async {
    final client = widget.cloud.createClient();
    if (client == null) {
      showAppToast(context, '云存储未启用，请先到"我的-图片云存储"配置');
      return;
    }
    final ok = await widget.imageRepo.uploadOne(img, client);
    if (!mounted) return;
    showAppToast(context, ok ? '上传成功' : '上传失败，请检查网络后重试');
  }

  /// 打开记一笔页：修改 = 编辑该笔；复制 = 预填数据保存为新记录。
  /// 先关弹窗再压栈编辑页——弹窗的使命在发起动作时即告结束，
  /// 编辑保存/取消返回都直接落在宿主列表，不保留过期的弹窗现场
  void _openEditor(bool edit) {
    // 先用打开弹窗时的快照构建编辑页再关弹窗（pop 后 widget 不可再读）
    final page = edit
        ? AddBillPage(editBill: widget.bill)
        : AddBillPage(copyOf: widget.bill);
    Navigator.of(widget.hostContext).pop();
    Navigator.of(widget.hostContext).push(
      MaterialPageRoute<void>(builder: (_) => page),
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
    await widget.provider.deleteBill(widget.bill.id);
  }

  /// 点击分类行：先关详情再交给宿主跳转，避免返回时又回到已关闭的弹窗
  void _tapCategory(BuildContext sheetContext) {
    final c = widget.categories[widget.bill.categoryId];
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
    final lat = widget.bill.lat;
    final lng = widget.bill.lng;
    if (lat == null || lng == null) return;
    final request = MapLauncher.marker(
      LocationCoords(lat, lng, title: widget.bill.location),
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
    final isExpense = widget.bill.type == BillType.expense;
    final amountColor = isExpense ? AppColors.expense : AppColors.income;
    final category = widget.categories[widget.bill.categoryId];
    // 位置展示用完整地址（含店名），无完整地址退回短地名
    final location = widget.bill.locationFull ?? widget.bill.location;
    // 仅精确坐标的账单可跳地图；只有行政区地名的旧账保持纯文字
    final hasLocationPoint = widget.bill.lat != null && widget.bill.lng != null;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 免单（实付 0 且有优惠）显示绿色"免单"，不再显 -¥0
                    (widget.bill.amountCents == 0 &&
                            widget.bill.discountCents != null &&
                            widget.bill.discountCents! > 0)
                        ? const Text(
                            '免单',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.income,
                            ),
                          )
                        : Text(
                            '${isExpense ? '-' : '+'}¥'
                            '${MoneyUtil.centsToYuanGroupedTrimmed(widget.bill.amountCents)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: amountColor,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                    // 有优惠时在实付下方展示原价（划线）与省额
                    if (widget.bill.discountCents != null &&
                        widget.bill.discountCents! > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '原价 ¥${MoneyUtil.centsToYuanGroupedTrimmed(widget.bill.amountCents + widget.bill.discountCents!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '省 ¥${MoneyUtil.centsToYuanTrimmed(widget.bill.discountCents!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.income,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // 图片凭证条：金额行下方 56px 圆角横滑缩略图（点击全屏预览）
              if (_images.isNotEmpty) ...[
                const Divider(height: 1, color: AppColors.divider),
                _Row(
                  label: '图片',
                  child: SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => _thumbCell(_images[i]),
                    ),
                  ),
                ),
              ],
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
                      _format(widget.bill.date, widget.bill.timeMinute),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '记录于 ${_format(widget.bill.createdAt, null)}',
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
                // Align 让 Text 按内容自然宽度收缩：短文本窄块靠右
                //（视觉同右对齐）；长文本撑满内容区、内部左对齐，
                // 换行后从左缘续行（段落式），不再每行贴右
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    widget.bill.note ?? '未添加备注',
                    style: TextStyle(
                      fontSize: 15,
                      color: widget.bill.note == null
                          ? AppColors.textSecondary.withValues(alpha: 0.7)
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (_tags.isNotEmpty) ...[
                const Divider(height: 1, color: AppColors.divider),
                _Row(
                  label: '标签',
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in _tags)
                        GestureDetector(
                          onTap: widget.onTagTap == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  widget.onTagTap!(t);
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Color(t.color).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              t.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(t.color),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (location != null) ...[
                const Divider(height: 1, color: AppColors.divider),
                _Row(
                  label: '位置',
                  onTap: hasLocationPoint ? _tapLocation : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 与列表条目同款定位针图标，置于地址文字之前
                      const Padding(
                        padding: EdgeInsets.only(top: 2, right: 4),
                        child: Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      // 去掉内部右对齐：短地址整体靠右（Row.end），
                      // 长地址换行后从左缘续行（段落式）
                      Flexible(
                        child: Text(
                          location,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
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

  /// 缩略图单元：56px 圆角图 + 右上角上传状态角标（点击重传）
  Widget _thumbCell(BillImage img) {
    final file = _localFiles[img.id];
    final uploading = img.uploadState == BillImageUploadState.uploading;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _preview(img),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: file == null
                ? Container(
                    width: 56,
                    height: 56,
                    color: AppColors.fill,
                    child: const Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Image.file(
                    file,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    // 文件半路被清（罕见）：退占位，不影响其余图
                    errorBuilder: (_, _, _) => Container(
                      width: 56,
                      height: 56,
                      color: AppColors.fill,
                      child: const Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
          ),
        ),
        // 未上传角标：上传中转圈，等待/失败橙点；点角标手动重传
        if (img.uploadState != BillImageUploadState.done)
          Positioned(
            right: -3,
            top: -3,
            child: GestureDetector(
              onTap: uploading ? null : () => unawaited(_reupload(img)),
              child: Container(
                width: 16,
                height: 16,
                // 半透明黑圆底：角标浮在照片上，白底遇白图会隐身
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: uploading
                    ? const Padding(
                        padding: EdgeInsets.all(3),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppColors.expense,
                      ),
              ),
            ),
          ),
      ],
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
