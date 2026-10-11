import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/asset_repository.dart';
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
part 'add_bill_page.rows.dart';
part 'add_bill_page.chips.dart';
part 'add_bill_page.transfer.dart';
part 'add_bill_page.save.dart';


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

/// 记一笔页共享状态基类：全部字段集中于此，四个分区 mixin（见 part 文件）
/// 经由它访问字段；跨分区共用的小工具（_assetById）也放这里
abstract class _AddBillBase extends State<AddBillPage> {
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

  /// 按 id 查未归档账户；查不到（未选择/已失效）返回 null。
  /// 胶囊行与转账区两个分区共用，放基类
  Asset? _assetById(int? id) {
    if (id == null) return null;
    for (final a in _allAssets) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// 记一笔页状态：生命周期 + 页面骨架（build / 顶栏 / 分类区 / 数字键盘）；
/// 备注行、胶囊行、转账区、保存逻辑分别在四个 part 文件的分区 mixin 中
class _AddBillPageState extends _AddBillBase
    with _NoteRows, _Chips, _TransferArea, _SaveAndBudget {
  /// 数字键盘固定高度：分割线 1 + 4 行键位 × 52（实测前的兜底估算）
  static const double _keyboardHeight = 1 + 52 * 4;

  /// 备注行高度估算（实测前的兜底值）
  static const double _noteRowHeight = 40;

  /// 日期/定位胶囊行高度估算（实测前的兜底值）
  static const double _dateRowHeight = 38;

  /// 金额上限（分）：约 999 万，防御性限制输入长度
  static const int _maxAmountCents = 999999999;

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
      // 新建模式：金额/分类/备注不恢复，但账户默认带上次记账用的，
      // 连续记账大多用同一账户（见 _restoreLastAsset）
      _restoreLastAsset();
    }
    // 异步加载全部标签（供弹层渲染，不阻塞首帧）
    _loadAllTags();
  }

  /// 新建模式默认带上次记账关联的账户：账户已被删除或归档时，
  /// didChangeDependencies 的资产流监听会自动清掉这个悬挂 id
  void _restoreLastAsset() {
    _selectedAssetId = context.read<AssetProvider>().lastBillAssetId;
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
}
