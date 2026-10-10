import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/bill_image_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../../models/asset_category.dart';
import '../../models/enums.dart';
import '../../models/summaries.dart';
import '../../pages/settings/category_manage_page.dart';
import '../../providers/asset_provider.dart';
import '../../providers/bill_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/cloud_storage_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/amap_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/money_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/asset_circle_icon.dart';
import '../../widgets/asset_pick_sheet.dart';
import '../../widgets/number_keyboard.dart';
import '../../widgets/tag_picker_sheet.dart';
import 'bill_image_sheet.dart';
import 'category_section.dart';
import 'location_picker_page.dart';
import 'wheel_date_picker.dart';

/// 记一笔页面
///
/// 新增、编辑与复制共用：传入 [editBill] 进入编辑模式（保存覆盖原记录）；
/// 传入 [copyOf] 进入复制模式（预填数据，保存生成一条新记录，见详情弹窗"复制"）。
/// 布局自上而下：顶栏（关闭/类型Tab/+）→ 账户条 + 分类区（转账类型为
/// 转出/转入账户选择区）→ 备注与金额行 → 日期/定位胶囊 → 数字键盘。
class AddBillPage extends StatefulWidget {
  const AddBillPage({super.key, this.editBill, this.copyOf});

  final Bill? editBill;

  /// 复制模式的源账单：仅用于预填，保存时走新增分支
  final Bill? copyOf;

  @override
  State<AddBillPage> createState() => _AddBillPageState();
}

class _AddBillPageState extends State<AddBillPage> {
  late BillType _type;
  String _amountText = '';

  /// 优惠金额输入文本（元）；空 = 未设置优惠。仅支出账单可用
  String _discountText = '';

  /// 输入模式（钱迹式）：true 时数字键盘改道写入优惠，
  /// 备注/金额行整体变身为"优惠"行；
  /// 再点优惠胶囊切回实付模式，已填优惠保留
  bool _discountMode = false;

  int? _selectedCategoryId;
  late DateTime _date;

  /// 关联账户（支出 = 付款账户，收入 = 收款账户，转账 = 转出账户）；
  /// null = 不关联（纯记账，余额不动）
  int? _selectedAssetId;

  /// 转入账户（仅转账账单）：储蓄卡 → 信用卡即还款
  int? _toAssetId;

  /// 未归档账户缓存（账户选择行/弹窗渲染用；资产流订阅实时刷新）
  List<Asset> _allAssets = [];

  /// 资产流订阅：页面存活期间保持缓存刷新，退出时取消
  StreamSubscription<List<Asset>>? _assetsSub;

  /// 已选标签 id 集合（空 = 未打标签）；# 按钮显示数量，弹层内勾选
  final Set<int> _selectedTagIds = {};

  /// 图片仓储（选图暂存 / 保存转正 / 退出清理共用）
  late final BillImageRepository _imageRepo = context
      .read<BillImageRepository>();

  /// 暂存图片路径（本次添加、尚未保存入库）
  List<String> _stagedImages = [];

  /// 已入库图片（编辑模式回显；复制模式为空——凭证不随复制）
  List<BillImage> _existingImages = [];

  /// 编辑模式下在面板中移除的已入库图，保存时统一删记录/本地文件/云端
  final List<BillImage> _removedExistingImages = [];

  /// 当前图片总数（胶囊计数用）
  int get _imageCount => _existingImages.length + _stagedImages.length;

  /// 全部标签缓存（弹层渲染用，initState 时加载，新建标签后追加）
  List<Tag> _allTags = [];

  /// 账单时间（当日 0..1439 分钟）
  late int _timeMinute;
  final _noteController = TextEditingController();

  /// 备注输入框焦点：聚焦时系统软键盘弹出、直接覆盖在常驻数字键盘上
  /// （钱迹式遮盖），失焦后数字键盘原地露出，两键盘永不同时出现
  final _noteFocus = FocusNode();

  /// 上一帧系统键盘可见性。Android 收起键盘（输入法"∨"按钮）不会
  /// 自动释放 TextField 焦点——需要对比 insets 变化，收起时主动失焦
  bool _keyboardWasVisible = false;

  /// 数字键盘固定高度：分割线 1 + 4 行键位 × 52（实测前的兜底估算）
  static const double _keyboardHeight = 1 + 52 * 4;

  /// 备注行高度估算（实测前的兜底值）
  static const double _noteRowHeight = 40;

  /// 日期/定位胶囊行高度估算（实测前的兜底值）
  static const double _dateRowHeight = 38;

  /// 底部固定区（备注行 + 日期行 + 键盘）实测总高，首帧后测量
  double? _bottomZoneHeight;

  /// 日期行 + 键盘的实测高度 = 备注行底面到屏幕底的距离，
  /// 用于备注聚焦时精确贴合系统键盘上缘
  double? _belowNoteHeight;

  final _bottomZoneKey = GlobalKey();
  final _belowNoteKey = GlobalKey();

  /// 首帧后实测底部固定区各段高度：估算值受中文字体行高影响不可靠，
  /// 实测值保证备注行在任何机型/字体下都精确贴住系统键盘上缘
  void _measureBottomZone() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final zone = _bottomZoneKey.currentContext?.size?.height;
      final below = _belowNoteKey.currentContext?.size?.height;
      if (zone != _bottomZoneHeight || below != _belowNoteHeight) {
        setState(() {
          _bottomZoneHeight = zone;
          _belowNoteHeight = below;
        });
      }
    });
  }

  /// 定位地名；null = 未定位
  String? _locationName;

  /// 定位完整信息（省市区街道 + 地点名），专供搜索字段 locationFull；
  /// 编辑时读旧账单回显，选点页无法补全时保留旧值兜底
  String? _locationFull;

  /// 定位坐标（与地名一起保存，编辑时选点页据此回到原地点）
  Gcj02Point? _selectedPoint;

  /// 金额上限（分）：约 999 万，防御性限制输入长度
  static const int _maxAmountCents = 999999999;

  /// 按类型缓存分类查询流：drift 的 watch() 每次调用都生成新 Stream，
  /// 若在 build 中现取现用，金额键入等高频 rebuild 会让 StreamBuilder
  /// 反复换流重订阅（分类区空窗闪烁、重复查询）；缓存后只有切换
  /// 收/支类型才真正换流
  late final Map<BillType, Stream<List<Category>>> _categoryStreams = {
    for (final t in BillType.values)
      t: context.read<CategoryProvider>().categoriesStream(t),
  };

  /// 已提示过的预算级别（会话内去重）：如 'total-2'（总预算超支）、
  /// 'cat-12-1'（分类 12 用量超 80%）
  final Set<String> _budgetHintKeys = {};

  bool get _isEditing => widget.editBill != null;

  /// 编辑/复制模式的源账单（复制模式仅用于预填，保存仍走新增分支）
  Bill? get _sourceBill => widget.editBill ?? widget.copyOf;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;
    final bill = _sourceBill;
    if (bill != null) {
      _type = bill.type;
      // 零头为 0 时省略小数：用户输入整数保存，回填时不显示 xxx.00
      _amountText = MoneyUtil.centsToYuanTrimmed(bill.amountCents);
      _discountText = bill.discountCents == null
          ? ''
          : MoneyUtil.centsToYuanTrimmed(bill.discountCents!);
      _selectedCategoryId = bill.categoryId;
      _date = bill.date;
      _timeMinute = bill.timeMinute ?? nowMinute;
      _noteController.text = bill.note ?? '';
      _locationName = bill.location;
      _locationFull = bill.locationFull;
      _selectedAssetId = bill.assetId;
      _toAssetId = bill.toAssetId;
      if (bill.lat != null && bill.lng != null) {
        _selectedPoint = Gcj02Point(lat: bill.lat!, lng: bill.lng!);
      }
      // 编辑模式：异步加载该账单已有标签
      _loadExistingTags(bill.id);
      // 编辑模式异步加载已入库图片回显；复制模式不带图（凭证不复制）
      if (widget.editBill != null) _loadExistingImages(bill.id);
    } else {
      _type = BillType.expense;
      _date = DateTime.now();
      _timeMinute = nowMinute;
      // 新建模式：不做任何历史恢复，每次打开都是全新输入
    }
    // 异步加载全部标签（供弹层渲染，不阻塞首帧）
    _loadAllTags();
  }

  /// 加载全部标签到缓存（弹层用）
  Future<void> _loadAllTags() async {
    final tags = await context.read<TagRepository>().getTags();
    if (!mounted) return;
    setState(() => _allTags = tags);
  }

  /// 编辑模式加载账单已有标签
  Future<void> _loadExistingTags(int billId) async {
    final tags = await context.read<TagRepository>().getTagsByBillId(billId);
    if (!mounted) return;
    setState(() {
      _selectedTagIds
        ..clear()
        ..addAll(tags.map((t) => t.id));
    });
  }

  /// 编辑模式加载已入库图片回显
  Future<void> _loadExistingImages(int billId) async {
    final images = await _imageRepo.getImagesByBillId(billId);
    if (!mounted) return;
    setState(() => _existingImages = images);
  }

  @override
  void dispose() {
    // 页面退出且未保存：清掉本次会话暂存的图片临时文件（已保存的
    // 路径经 attachStagedImages 转正移走，此处 discard 为空操作）
    for (final path in _stagedImages) {
      unawaited(_imageRepo.photos.discard(path));
    }
    unawaited(_assetsSub?.cancel());
    _noteFocus.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 备注聚焦时用户点输入法"∨"收起键盘：insets 归零但焦点仍在，
    // 主动失焦让自定义数字键盘恢复显示
    final visible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (_keyboardWasVisible && !visible && _noteFocus.hasFocus) {
      _noteFocus.unfocus();
    }
    _keyboardWasVisible = visible;
    // 订阅资产流：缓存未归档账户供账户条/弹窗渲染；账户被删除或
    // 归档时清掉悬挂的已选 id，避免保存时关联到失效账户
    _assetsSub ??= context
        .read<AssetProvider>()
        .activeStream()
        .listen((list) {
          if (!mounted) return;
          setState(() {
            _allAssets = list;
            if (_selectedAssetId != null &&
                !list.any((a) => a.id == _selectedAssetId)) {
              _selectedAssetId = null;
            }
            if (_toAssetId != null && !list.any((a) => a.id == _toAssetId)) {
              _toAssetId = null;
            }
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    // 底部固定区（备注行 + 日期行 + 数字键盘）常驻屏幕底；
    // 备注聚焦时整体上移，让备注行恰好贴在系统键盘上缘——
    // 日期行与数字键盘被系统键盘盖住，分类区高度保持不变（钱迹式）
    _measureBottomZone();
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final belowNote = _belowNoteHeight ?? _keyboardHeight + _dateRowHeight;
    final bottomOffset = insets > _keyboardHeight ? insets - belowNote : 0.0;
    final bottomZone =
        _bottomZoneHeight ?? _keyboardHeight + _noteRowHeight + _dateRowHeight;
    return Scaffold(
      // 不随系统键盘 resize：系统键盘直接覆盖在底部固定区上
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: SafeArea(
        // 点击页面空白处收回备注焦点：系统键盘收起、数字键盘露出
        child: GestureDetector(
          onTap: () => _noteFocus.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              // 内容层：让出整个底部固定区，分类区高度恒定不跳
              Padding(
                padding: EdgeInsets.only(bottom: bottomZone),
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      // 转账无分类：整区替换为转出/转入账户选择；
                      // 支出/收入的账户在底部胶囊行选择，这里只放分类树
                      child: _type == BillType.transfer
                          ? _buildTransferAccountArea()
                          : _buildCategoryGrid(),
                    ),
                  ],
                ),
              ),
              // 底部固定区：备注聚焦时上移至备注行贴系统键盘上缘
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomOffset < 0 ? 0 : bottomOffset,
                child: Column(
                  key: _bottomZoneKey,
                  children: [
                    _discountMode ? _buildDiscountRow() : _buildNoteRow(),
                    KeyedSubtree(
                      key: _belowNoteKey,
                      child: Column(
                        children: [_buildChipRow(), _buildKeyboard()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶栏：左关闭 ｜ 支出/收入/转账 Tab（下划线选中态）｜ 右上角 +
  Widget _buildTopBar() {
    // 白底顶栏 + 底部渐变条实现"只有下边"的立体效果（BoxShadow 无法单边）
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, size: 26),
                color: AppColors.textPrimary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [for (final t in BillType.values) _buildTopTab(t)],
                ),
              ),
              // 右上角 + 与左侧 ✕ 对称：点击进入分类管理页。
              // 三模式（新建/编辑/复制）统一；删除走详情弹窗，不在编辑页重复
              IconButton(
                icon: const Icon(Icons.add, size: 26),
                color: AppColors.textPrimary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CategoryManagePage(),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 顶栏下缘向下渐隐的立体条：黑 10% → 透明，仅存在于下方
        Container(
          width: double.infinity,
          height: 5,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x1A000000), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }

  /// 顶栏类型 Tab：文字 + 选中态主色下划线
  Widget _buildTopTab(BillType type) {
    final selected = _type == type;
    return InkWell(
      onTap: () {
        if (selected) return;
        setState(() {
          _type = type;
          // 切换类型后原分类不再适用，重置为空（由分类区默认选中补齐）
          _selectedCategoryId = null;
          // 优惠只属于支出：切到收入/转账时退出优惠模式并清空，
          // 防止已填优惠被误带进收入或转账账单
          if (type != BillType.expense) {
            _discountMode = false;
            _discountText = '';
          }
          // 转入账户只属于转账：切出转账时清掉，支出/收入不保存该值
          if (type != BillType.transfer) {
            _toAssetId = null;
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              type.label,
              style: TextStyle(
                fontSize: 16,
                height: 1.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 备注与金额行：# 备注输入 ｜ 金额 + 币种
  Widget _buildNoteRow() {
    // 转账金额用中性色：非收非支，与明细列表/详情弹窗同口径
    final color = switch (_type) {
      BillType.expense => AppColors.expense,
      BillType.income => AppColors.income,
      BillType.transfer => AppColors.textPrimary,
    };
    // 空金额时不显示大字"0"，改为中号灰色提示，明确录入的是实付
    // （优惠另有独立入口）；转账语义不同提示"转账金额"；CNY 始终保留
    final amountEmpty = _amountText.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        4,
        AppDimens.pagePadding,
        0,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showTagSheet,
            child: Text(
              _selectedTagIds.isEmpty ? '#' : '#(${_selectedTagIds.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _selectedTagIds.isEmpty
                    ? AppColors.textSecondary
                    : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _noteController,
              focusNode: _noteFocus,
              maxLength: 50,
              keyboardType: TextInputType.text,
              // 按"完成"键释放焦点：系统键盘收起、数字键盘恢复
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _noteFocus.unfocus(),
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                // 收紧上下内边距：文字贴近行底，备注行贴键盘上缘时
                // 文字与键盘的视觉距离更短（钱迹同款紧凑观感）
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                hintText: '点此输入备注…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 金额 + CNY 整体贴右缘（与左侧 # 对称）：备注 Expanded 吃掉全部
          // 剩余空间把它们推到最右；FittedBox 在空间不足时整体缩小防溢出。
          // 注意不能用 Flexible——它会平分剩余空间，导致 CNY 右侧留空。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  amountEmpty
                      ? (_type == BillType.transfer ? '转账金额' : '实付金额')
                      : _amountText,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: amountEmpty
                      ? const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        )
                      : TextStyle(
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                ),
                const SizedBox(width: 3),
                const Text(
                  'CNY',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 优惠模式金额行（钱迹式整行变身）：
  /// 左侧"优惠"标题，右侧绿色优惠数字，无 CNY。
  /// 此模式下备注输入框隐藏，数字键盘输入直接写入优惠额
  Widget _buildDiscountRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        4,
        AppDimens.pagePadding,
        0,
      ),
      child: Row(
        children: [
          const Text(
            '优惠',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _discountText.isEmpty ? '0.00' : _discountText,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.income,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 3),
                // 单位与实付模式同款（13 号灰字），两种金额行视觉统一
                const Text(
                  'CNY',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出标签选择面板：已选胶囊（点取消）+ 全部标签（点选）+ 新建 + 管理
  Future<void> _showTagSheet() async {
    // 备注聚焦时先收起系统键盘，避免弹层被键盘挡住
    _noteFocus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TagPickerSheet(
        selectedIds: _selectedTagIds,
        allTags: _allTags,
        onChanged: (ids) {
          setState(() {
            _selectedTagIds
              ..clear()
              ..addAll(ids);
          });
        },
      ),
    );
  }

  /// 胶囊行：账户（支出/收入，弹窗选择）/ 日期 / 优惠 / 图片 / 定位。
  /// 日期胶囊：今天/昨天/前天显示相对日期，其余显示 M月d日，统一附带时间；
  /// 点击弹出日期滚轮（内含今/昨/前快捷与时间选择入口）。
  Widget _buildChipRow() {
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(_date.year, _date.month, _date.day)).inDays;
    final hh = (_timeMinute ~/ 60).toString().padLeft(2, '0');
    final mm = (_timeMinute % 60).toString().padLeft(2, '0');
    final label = switch (diff) {
      0 => '今天 $hh:$mm',
      1 => '昨天 $hh:$mm',
      2 => '前天 $hh:$mm',
      _ => '${_date.month}月${_date.day}日 $hh:$mm',
    };
    // 定位开关关闭时隐藏入口；编辑/复制已有位置的账单除外，保留清除能力
    final showLocation =
        context.watch<SettingsProvider>().billLocationEnabled ||
        _sourceBill?.location != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        6,
        AppDimens.pagePadding,
        4,
      ),
      // 胶囊行横向可滚动：小屏上日期/优惠/图片/定位摆不下时滑动查看，
      // 不再挤压定位胶囊的文字宽度。
      // 满宽是关键：SingleChildScrollView 会收缩到内容宽度，被外层
      // Column（默认居中）摆到屏幕中间，包一层无穷宽让胶囊贴左排列
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // 账户胶囊放最前（支出/收入）；转账的两个账户在内容区选择行
              if (_type != BillType.transfer) ...[
                _buildAssetChip(),
                const SizedBox(width: 8),
              ],
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.fill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_type == BillType.expense) ...[
                const SizedBox(width: 8),
                _buildDiscountChip(),
              ],
              // 图片入口：仅在用户已启用云存储后出现（未配置完全隐藏）
              if (_imageEntryVisible) ...[
                const SizedBox(width: 8),
                _buildImageChip(),
              ],
              if (showLocation) ...[
                const SizedBox(width: 8),
                _buildLocationChip(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 图片入口可见性：云存储已启用才显示（watch 保证配置页开启后
  /// 返回记一笔页时胶囊即时出现）
  bool get _imageEntryVisible => context.watch<CloudStorageProvider>().enabled;

  /// 图片胶囊：点击弹出图片面板。中性灰底——计数态不用绿色，
  /// 绿色保留给"省钱"语义；增删都在面板里，胶囊无 ✕ 态
  Widget _buildImageChip() {
    final count = _imageCount;
    return InkWell(
      onTap: _showImageSheet,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_outlined,
              size: 12,
              color: AppColors.primary,
            ),
            const SizedBox(width: 5),
            Text(
              count > 0 ? '图片($count)' : '图片',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开图片面板：已入库图与暂存图一起交给面板管理，
  /// 变更实时回传（保存时才真正写库/删记录/触发上传）
  Future<void> _showImageSheet() async {
    // 备注聚焦时先收起系统键盘，避免弹层被键盘挡住
    _noteFocus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BillImageSheet(
        repo: _imageRepo,
        initialExisting: _existingImages,
        initialStaged: _stagedImages,
        onChanged: (existing, staged) {
          setState(() {
            // 对比找出门板里被移除的已入库图，保存时统一清理
            for (final old in _existingImages) {
              if (!existing.any((e) => e.id == old.id)) {
                _removedExistingImages.add(old);
              }
            }
            _existingImages = existing;
            _stagedImages = staged;
          });
        },
      ),
    );
  }

  /// 优惠胶囊（仅支出，位于日期与定位胶囊之间），三态：
  /// 未设置=灰底"优惠"；已设置=浅绿底"省 ¥x"；
  /// 优惠输入模式中=浅绿底"优惠 ✕"，✕ 清空优惠并退回实付模式。
  /// 点胶囊本体在实付/优惠输入模式间切换（钱迹式）
  Widget _buildDiscountChip() {
    final discountCents = MoneyUtil.yuanToCents(_discountText);
    final hasDiscount = discountCents != null && discountCents > 0;
    final active = _discountMode;
    final bg = (active || hasDiscount)
        ? AppColors.tint(AppColors.income)
        : AppColors.fill;
    final fg = (active || hasDiscount)
        ? AppColors.income
        : AppColors.textPrimary;
    return InkWell(
      onTap: () => setState(() => _discountMode = !_discountMode),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasDiscount
                  ? '省 ¥${MoneyUtil.centsToYuanTrimmed(discountCents)}'
                  : '优惠',
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
            // 输入模式中展示 ✕：仅收起优惠行切回实付模式（钱迹语义），
            // 已填优惠保留；清零请用键盘 C 键
            if (active) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _discountMode = false),
                child: Icon(Icons.cancel, size: 14, color: fg),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 定位胶囊：未定位显示"定位"入口，点击获取当前位置；
  /// 已定位显示地名与清除按钮。样式与日期胶囊保持一致。
  Widget _buildLocationChip() {
    final hasLocation = _locationName != null;
    return InkWell(
      onTap: _locate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.place_outlined,
              size: 12,
              color: AppColors.primary,
            ),
            const SizedBox(width: 5),
            Text(
              hasLocation ? _locationName! : '定位',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            // 已定位时提供清除入口，长地名不至于挤掉清除按钮
            if (hasLocation) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() {
                  _locationName = null;
                  _locationFull = null;
                  _selectedPoint = null;
                }),
                child: const Icon(
                  Icons.cancel,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 打开位置选择页（高德地图选点 + 附近地点/搜索列表）
  ///
  /// 编辑模式把已保存的地名与坐标传入，选点页回到老地点；
  /// 选中返回后地名与坐标一起更新，未选择（返回键）保持原状。
  Future<void> _locate() async {
    final selection = await Navigator.of(context).push<LocationSelection>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialName: _locationName,
          initialPoint: _selectedPoint,
        ),
      ),
    );
    if (!mounted) return;
    if (selection != null && selection.name.isNotEmpty) {
      setState(() {
        _locationName = selection.name;
        _selectedPoint = selection.point;
        // 选点页补全了完整地址则更新；无法补全（如"已保存的位置"）
        // 保留旧值，避免把已有的完整信息冲掉
        if (selection.fullAddress != null) {
          _locationFull = selection.fullAddress;
        }
      });
    }
  }

  // ---------- 账户选择（支出/收入胶囊 + 弹窗，转账选择区） ----------

  /// 账户胶囊：显示当前关联账户（未选显示"不关联"），点击弹出
  /// 账户选择面板（与图片胶囊同交互）；上次使用的账户进页时已自动
  /// 带上（见 _restoreLastAsset）。转账模式不显示——两个账户在内容区选
  Widget _buildAssetChip() {
    final asset = _assetById(_selectedAssetId);
    return InkWell(
      onTap: _pickAsset,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (asset == null)
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 12,
                color: AppColors.textSecondary,
              )
            else
              AssetCircleIcon(category: asset.category, size: 14),
            const SizedBox(width: 5),
            Text(
              asset?.name ?? '不关联',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 弹窗选择账户：支出/收入允许"不关联"（余额不动）；
  /// 下滑关闭等取消操作返回 null，保持当前选择不变
  Future<void> _pickAsset() async {
    final result = await showAssetPickSheet(
      context,
      assets: _allAssets,
      allowNone: true,
    );
    if (result == null || !mounted) return;
    setState(() => _selectedAssetId = result.$1?.id);
  }

  /// 转账模式内容区：账户卡片——转出/转入两行账户（图标+名称+余额）
  /// + 中间贯穿分隔线上的互换浮钮。两账户均必选（联动余额的前提），
  /// 储蓄卡 → 信用卡即为还款
  Widget _buildTransferAccountArea() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        16,
        AppDimens.pagePadding,
        16,
      ),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
            boxShadow: [
              // 极浅投影把卡片从白底页面托起（与 SectionCard 同强度）
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _transferAccountRow(
                asset: _assetById(_selectedAssetId),
                hint: '选择转出账户',
                onTap: () => _pickTransferAsset(to: false),
              ),
              _swapDivider(),
              _transferAccountRow(
                asset: _assetById(_toAssetId),
                hint: '选择转入账户',
                onTap: () => _pickTransferAsset(to: true),
              ),
            ],
          ),
        ),
        // 还款提示独立成卡：仅转入信用卡组账户时才有意义
        if (_isToCreditCard) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '转入信用卡账户即为还款，不计入收支统计与预算',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  /// 转入账户是否为信用卡组账户（信用卡/花呗/白条等）：
  /// 决定还款提示卡是否显示，其它账户不显示
  bool get _isToCreditCard {
    final to = _assetById(_toAssetId);
    return to != null &&
        AssetGroups.groupOf(to.category) == AssetGroups.credit;
  }

  /// 转出/转入之间的分隔：贯穿左右的淡横线，互换浮钮叠压在线的中点
  Widget _swapDivider() {
    // 必须显式撑满宽度：Column 松约束下 Stack 会收缩到最宽子项
    // （40px 浮钮），整条线就会完全被浮钮盖住
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: SizedBox(
                height: 1,
                width: double.infinity,
                child: ColoredBox(color: AppColors.divider),
              ),
            ),
          ),
          _swapButton(),
        ],
      ),
    );
  }

  /// 白色圆形互换浮钮：点击交换转出/转入
  Widget _swapButton() {
    return InkWell(
      onTap: () => setState(() {
        final tmp = _selectedAssetId;
        _selectedAssetId = _toAssetId;
        _toAssetId = tmp;
      }),
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.swap_vert,
          size: 20,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  /// 按 id 查未归档账户；查不到（未选择/已失效）返回 null
  Asset? _assetById(int? id) {
    if (id == null) return null;
    for (final a in _allAssets) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// 账户行：彩色圆图标 + 账户名 + 右侧实时余额（对齐主流记账
  /// App 的账户本体展示）；未选时灰字提示，点击弹账户选择弹窗
  Widget _transferAccountRow({
    required Asset? asset,
    required String hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: asset == null
            ? Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppColors.fill,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 17,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    hint,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  AssetCircleIcon(category: asset.category, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _balanceText(asset),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
      ),
    );
  }

  /// 余额文本：信用卡显示红色负数欠款（溢缴款按普通余额展示），
  /// 资产正常色——转账选账户时余额一目了然
  Widget _balanceText(Asset asset) {
    final owed = asset.kind == AssetKind.liability && asset.valueCents > 0;
    final balance = MoneyUtil.centsToYuanGroupedTrimmed(asset.valueCents);
    return Text(
      owed ? '-¥$balance' : '¥$balance',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: owed ? AppColors.expense : AppColors.textPrimary,
      ),
    );
  }

  /// 弹窗选择转账账户：转出/转入均必选（allowNone = false），
  /// 下滑关闭等取消操作返回 null，保持当前值不变
  Future<void> _pickTransferAsset({required bool to}) async {
    final result = await showAssetPickSheet(
      context,
      assets: _allAssets,
    );
    if (result == null || !mounted) return;
    final pickedId = result.$1?.id;
    setState(() {
      if (to) {
        _toAssetId = pickedId;
      } else {
        _selectedAssetId = pickedId;
      }
    });
  }

  /// 分类选择：委托通用 [CategoryTreeSelector] 单选模式
  ///
  /// 点一级 = 挂一级本身并展开二级面板（不预选二级）；点二级选中；
  /// 再点当前已选二级 = 取消、挂回一级。默认挂第一个一级分类本身。
  Widget _buildCategoryGrid() {
    return CategorySection(
      stream: _categoryStreams[_type]!,
      type: _type,
      selectedId: _selectedCategoryId,
      onSelectedChanged: (id) => setState(() => _selectedCategoryId = id),
      // 选中分类不存在时（如类型切换后）兜底挂第一个一级本身
      onEnsureSelected: (id) => _selectedCategoryId = id,
    );
  }

  /// 数字键盘
  Widget _buildKeyboard() {
    return NumberKeyboard(
      onKey: _onAmountKey,
      onDelete: _onAmountDelete,
      onClear: () => setState(() {
        // 清空当前输入模式对应的字段
        if (_discountMode) {
          _discountText = '';
        } else {
          _amountText = '';
        }
      }),
      onToday: () => setState(() => _date = DateTime.now()),
      onAgain: () => _save(stay: true),
      onDone: () => _save(),
    );
  }

  // ---------- 金额输入约束 ----------

  /// 键盘数字键入：优惠模式写入优惠额，实付模式写入实付额。
  /// 两者共用同一套前导零/小数位/上限约束
  void _onAmountKey(String key) {
    setState(() {
      final current = _discountMode ? _discountText : _amountText;
      final next = _constrainAmountInput(current, key);
      if (next == null) return;
      if (_discountMode) {
        _discountText = next;
      } else {
        _amountText = next;
      }
    });
  }

  /// 金额类输入约束：返回追加/处理后的新文本；null = 本次按键忽略
  String? _constrainAmountInput(String text, String key) {
    if (key == '.') {
      // 已含小数点忽略；空文本补前导 0（输入 "." 视为 "0."）
      if (text.contains('.')) return null;
      return text.isEmpty ? '0.' : '$text.';
    }
    // 输入首个非零数字时替换掉前导 0
    if (text == '0') return key;
    final candidate = text + key;
    // 小数超过两位则忽略
    final dotIndex = candidate.indexOf('.');
    if (dotIndex >= 0 && candidate.length - dotIndex - 1 > 2) return null;
    final cents = MoneyUtil.yuanToCents(candidate);
    if (cents == null || cents > _maxAmountCents) return null;
    return candidate;
  }

  /// 退格：作用于当前输入模式对应的字段
  void _onAmountDelete() {
    setState(() {
      if (_discountMode) {
        if (_discountText.isEmpty) return;
        _discountText = _discountText.substring(0, _discountText.length - 1);
      } else {
        if (_amountText.isEmpty) return;
        _amountText = _amountText.substring(0, _amountText.length - 1);
      }
    });
  }

  /// 选择账单日期与时间：滚轮弹窗（年/月/日 + 今昨前快捷 + 时间入口）
  Future<void> _pickDate() async {
    final picked = await showModalBottomSheet<(DateTime, int)>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusHeader),
        ),
      ),
      builder: (_) =>
          WheelDatePicker(initial: _date, initialMinute: _timeMinute),
    );
    if (picked != null) {
      setState(() {
        _date = picked.$1;
        _timeMinute = picked.$2;
      });
    }
  }

  // ---------- 保存 / 删除 ----------

  /// 保存账单（新增或更新）
  ///
  /// [stay] 为 true 时"再记"：保存后清空金额与备注并留在页面，
  /// 保留分类与日期，便于连续记账。
  Future<void> _save({bool stay = false}) async {
    // 实付允许为 0（免单），但实付为 0 必须有优惠；无优惠时实付必须 >0。
    // 留空按 0 处理，使用户在优惠模式直接保存即可记一笔免单
    final cents = MoneyUtil.yuanToCents(_amountText) ?? 0;
    // 优惠额：0/空视为未优惠存 null；优惠可大于实付（平台补贴券等），
    // 不设上限约束。收入/转账入口已隐藏且切类型会清空，这里再兜底
    var discountCents = MoneyUtil.yuanToCents(_discountText);
    if (discountCents != null && discountCents == 0) discountCents = null;
    if (_type != BillType.expense) discountCents = null;
    if (cents == 0 && discountCents == null) {
      showAppToast(context, '请输入正确的金额');
      return;
    }
    // 转账：两账户必选且不能相同，不挂分类；其余类型维持分类必选校验
    if (_type == BillType.transfer) {
      if (_selectedAssetId == null || _toAssetId == null) {
        showAppToast(context, '请选择转出与转入账户');
        return;
      }
      if (_selectedAssetId == _toAssetId) {
        showAppToast(context, '转出与转入不能是同一账户');
        return;
      }
    } else if (_selectedCategoryId == null) {
      showAppToast(context, '请选择分类');
      return;
    }
    final note = _noteController.text.trim();
    final provider = context.read<BillProvider>();
    final tagRepo = context.read<TagRepository>();
    // 图片收尾要用云存储配置：在首个 await 前取好，避免跨异步间隙用 context
    final cloud = context.read<CloudStorageProvider>();
    late final int savedBillId;
    if (_isEditing) {
      final bill = widget.editBill!;
      savedBillId = bill.id;
      await provider.updateBill(
        Bill(
          id: bill.id,
          type: _type,
          amountCents: cents,
          discountCents: discountCents,
          categoryId: _selectedCategoryId,
          note: note.isEmpty ? null : note,
          date: _date,
          timeMinute: _timeMinute,
          location: _locationName,
          locationFull: _locationFull,
          lat: _selectedPoint?.lat,
          lng: _selectedPoint?.lng,
          assetId: _selectedAssetId,
          toAssetId: _type == BillType.transfer ? _toAssetId : null,
          createdAt: bill.createdAt,
        ),
      );
      // 编辑：全量替换标签关联
      await tagRepo.setBillTags(bill.id, _selectedTagIds.toList());
    } else {
      final billId = await provider.addBill(
        BillsCompanion.insert(
          type: _type,
          amountCents: cents,
          discountCents: Value(discountCents),
          categoryId: Value(_selectedCategoryId),
          date: _date,
          timeMinute: Value(_timeMinute),
          note: Value(note.isEmpty ? null : note),
          location: Value(_locationName),
          locationFull: Value(_locationFull),
          lat: Value(_selectedPoint?.lat),
          lng: Value(_selectedPoint?.lng),
          assetId: Value(_selectedAssetId),
          toAssetId: Value(_type == BillType.transfer ? _toAssetId : null),
        ),
      );
      savedBillId = billId;
      // 新增：关联标签
      if (_selectedTagIds.isNotEmpty) {
        await tagRepo.setBillTags(billId, _selectedTagIds.toList());
      }
    }
    // 图片收尾：暂存图转正入库并异步上传（不阻塞保存返回）；面板里
    // 移除的已入库图统一删记录/本地文件/云端对象
    final attached = await _imageRepo.attachStagedImages(
      savedBillId,
      _stagedImages,
    );
    for (final removed in _removedExistingImages) {
      await _imageRepo.deleteImage(removed, client: cloud.createClient());
    }
    if (attached.isNotEmpty) {
      final client = cloud.createClient();
      if (client != null) {
        unawaited(_imageRepo.uploadImages(attached, client));
      }
    }
    _stagedImages = [];
    _removedExistingImages.clear();
    // 记账后检查预算用量（仅支出记账会占预算）
    if (_type == BillType.expense) await _checkBudgetHint();
    if (stay) {
      // 再记：重置金额与备注，继续记录下一笔（图片已随上一笔保存，一并清空）
      if (!mounted) return;
      setState(() {
        _amountText = '';
        _discountText = '';
        _discountMode = false;
        _noteController.clear();
        _selectedTagIds.clear();
        _existingImages = [];
      });
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 记账后预算提醒：支出落库后检查账单所在月的总预算与该分类
  /// （二级归并到一级）预算用量，越过 80% 或超支时轻提示。
  /// 总预算与分类预算同时越线时只提示总预算，避免连弹。
  Future<void> _checkBudgetHint() async {
    final provider = context.read<BudgetProvider>();
    final month = DateTime(_date.year, _date.month);
    // 分类归并：账单挂在二级分类时按一级分类的预算检查
    final categories = await context
        .read<CategoryProvider>()
        .categoriesMapStream()
        .first;
    final cat = categories[_selectedCategoryId];
    // ?? 0 兜底类型：0 不会匹配任何分类预算（categoryId > 0），
    // 正常路径下 _selectedCategoryId 在保存时已校验非空
    final topId = cat?.parentId ?? _selectedCategoryId ?? 0;
    if (!mounted) return;
    final topName = cat == null ? '该分类' : categories[topId]?.name ?? cat.name;

    // 总预算优先
    String? hint;
    final budget = await provider.getBudget(month);
    if (budget != null && budget.amountCents > 0) {
      final spent = (await provider.summaryStream(month).first).expenseCents;
      hint = _budgetHintText('total', 0, '本月预算', spent, budget.amountCents);
    }
    // 总预算未越线时才检查分类预算
    if (hint == null) {
      final budgets = await provider.categoryBudgetsStream(month).first;
      final target = budgets.where(
        (b) => b.categoryId == topId && b.amountCents > 0,
      );
      if (target.isNotEmpty) {
        final summaries = await provider.categorySummaryStream(month).first;
        final spent = summaries
            .firstWhere(
              (s) => s.categoryId == topId,
              orElse: () => CategorySummary(
                categoryId: topId,
                name: topName,
                iconCode: 0,
                colorValue: 0,
                type: BillType.expense,
                totalCents: 0,
              ),
            )
            .totalCents;
        hint = _budgetHintText(
          'cat',
          topId,
          '「$topName」预算',
          spent,
          target.first.amountCents,
        );
      }
    }
    if (hint != null && mounted) {
      showAppToast(context, hint);
    }
  }

  /// 组装预算提示文案并做级别去重；越线但同级别已提示过则返回 null
  String? _budgetHintText(
    String prefix,
    int categoryId,
    String label,
    int spent,
    int budget,
  ) {
    final ratio = budget > 0 ? spent / budget : 0.0;
    if (ratio > 1) {
      if (_budgetHintKeys.add('$prefix-${categoryId}_2')) {
        return '$label已超支 ¥${MoneyUtil.centsToYuanGroupedTrimmed(spent - budget)}';
      }
    } else if (ratio > 0.8) {
      if (_budgetHintKeys.add('$prefix-${categoryId}_1')) {
        return '$label已用 ${(ratio * 100).toStringAsFixed(0)}%，注意控制开销';
      }
    }
    return null;
  }
}
