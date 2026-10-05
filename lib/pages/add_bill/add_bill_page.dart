import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../models/summaries.dart';
import '../../pages/settings/category_manage_page.dart';
import '../../providers/bill_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/amap_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/money_util.dart';
import '../../widgets/category_avatar.dart';
import '../../widgets/number_keyboard.dart';
import 'location_picker_page.dart';
import 'wheel_date_picker.dart';

/// 记一笔页面
///
/// 新增、编辑与复制共用：传入 [editBill] 进入编辑模式（保存覆盖原记录）；
/// 传入 [copyOf] 进入复制模式（预填数据，保存生成一条新记录，见详情弹窗"复制"）。
/// 布局自上而下：顶栏（关闭/类型Tab/删除）→ 分类区（分组展开）→
/// 备注与金额行 → 日期/定位胶囊 → 数字键盘。
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
  int? _selectedCategoryId;
  late DateTime _date;

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

  bool get _isEditing => widget.editBill != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;
    final bill = widget.editBill ?? widget.copyOf;
    if (bill != null) {
      _type = bill.type;
      // 零头为 0 时省略小数：用户输入整数保存，回填时不显示 xxx.00
      _amountText = MoneyUtil.centsToYuanTrimmed(bill.amountCents);
      _selectedCategoryId = bill.categoryId;
      _date = bill.date;
      _timeMinute = bill.timeMinute ?? nowMinute;
      _noteController.text = bill.note ?? '';
      _locationName = bill.location;
      _locationFull = bill.locationFull;
      if (bill.lat != null && bill.lng != null) {
        _selectedPoint = Gcj02Point(lat: bill.lat!, lng: bill.lng!);
      }
    } else {
      _type = BillType.expense;
      _date = DateTime.now();
      _timeMinute = nowMinute;
    }
  }

  @override
  void dispose() {
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
                    Expanded(child: _buildCategoryGrid()),
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
                    _buildNoteRow(),
                    KeyedSubtree(
                      key: _belowNoteKey,
                      child: Column(
                        children: [_buildDateChip(), _buildKeyboard()],
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

  /// 顶栏：左关闭 ｜ 支出/收入 Tab（下划线选中态）｜ 编辑模式右删除
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
              // 右上角 + 与左侧 ✕ 对称：点击进入分类管理页
              if (_isEditing)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 24),
                  color: AppColors.expense,
                  onPressed: _confirmDelete,
                )
              else
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
    final color = _type == BillType.expense
        ? AppColors.expense
        : AppColors.income;
    // 未输入任何金额时显示整数 0（与"无小数不显示小数"的规则一致）
    final display = _amountText.isEmpty ? '0' : _amountText;
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
            '#',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
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
                  display,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: TextStyle(
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

  /// 日期胶囊：今天/昨天/前天显示相对日期，其余显示 M月d日，统一附带时间。
  /// 点击弹出日期滚轮（内含今/昨/前快捷与时间选择入口）。
  Widget _buildDateChip() {
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
            (widget.editBill ?? widget.copyOf)?.location != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        6,
        AppDimens.pagePadding,
        4,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _pickDate,
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
          if (showLocation) ...[
            const SizedBox(width: 8),
            _buildLocationChip(),
          ],
        ],
      ),
    );
  }

  /// 定位胶囊：未定位显示"定位"入口，点击获取当前位置；
  /// 已定位显示地名与清除按钮。样式与日期胶囊保持一致。
  Widget _buildLocationChip() {
    final hasLocation = _locationName != null;
    return Flexible(
      child: InkWell(
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
              Flexible(
                child: Text(
                  hasLocation ? _locationName! : '定位',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
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

  /// 分类选择：分组展开式（参考钱迹）
  ///
  /// 一级分类按每行 5 个横向排列；点击一级分类后，其子分类以浅色圆角
  /// 面板展开在该行下方，面板内为 5 列子分类网格。无子分类的一级
  /// 直接选中，不展开面板。
  Widget _buildCategoryGrid() {
    return StreamBuilder<List<Category>>(
      stream: context.read<CategoryProvider>().categoriesStream(_type),
      builder: (context, snapshot) {
        final categories = snapshot.data ?? const <Category>[];
        if (categories.isEmpty) {
          return const Center(
            child: Text(
              '暂无分类，请在"我的-分类管理"中添加',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        // 按层级分组：一级分类列表 + 一级 id → 子类列表
        final parents = categories.where((c) => c.parentId == null).toList();
        final subsMap = <int, List<Category>>{};
        for (final c in categories) {
          final pid = c.parentId;
          if (pid != null) (subsMap[pid] ??= []).add(c);
        }
        if (parents.isEmpty) {
          return const Center(
            child: Text(
              '暂无一级分类，请在"我的-分类管理"中添加',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        // 尚未选中（或选中分类已不存在，如类型切换后）时按第一项补默认值，
        // 保证直接保存也合法
        final exists = categories.any((c) => c.id == _selectedCategoryId);
        if (!exists) {
          final subs = subsMap[parents.first.id];
          _selectedCategoryId = (subs == null || subs.isEmpty)
              ? parents.first.id
              : subs.first.id;
        }
        // 由选中分类推导当前展开的一级（选中可能是子类）
        Category? selected;
        for (final c in categories) {
          if (c.id == _selectedCategoryId) {
            selected = c;
            break;
          }
        }
        final activeParentId = selected == null
            ? parents.first.id
            : (selected.parentId ?? selected.id);

        // 一级分类按每行 5 个分块，展开面板插入在选中项所在行之后
        final rows = <List<Category>>[];
        for (var i = 0; i < parents.length; i += 5) {
          final end = (i + 5 > parents.length) ? parents.length : i + 5;
          rows.add(parents.sublist(i, end));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          children: [
            for (final row in rows) ...[
              _buildParentRow(row, activeParentId, subsMap),
              // 选中项所在行下方展开其子分类面板，三角尖对准选中项
              if (row.any((p) => p.id == activeParentId) &&
                  (subsMap[activeParentId]?.isNotEmpty ?? false))
                _buildSubPanel(
                  subsMap[activeParentId]!,
                  row.indexWhere((p) => p.id == activeParentId),
                ),
            ],
          ],
        );
      },
    );
  }

  /// 一级分类行：每行 5 个，不足补空位保持对齐
  Widget _buildParentRow(
    List<Category> row,
    int activeParentId,
    Map<int, List<Category>> subsMap,
  ) {
    return Row(
      children: [
        for (final parent in row)
          _ParentCell(
            category: parent,
            selected: parent.id == activeParentId,
            onTap: () => _selectParent(parent, subsMap),
          ),
        for (var i = row.length; i < 5; i++) const Expanded(child: SizedBox()),
      ],
    );
  }

  /// 点击一级分类：有子类则选中其第一个子类（触发展开），无子类直接选中
  void _selectParent(Category parent, Map<int, List<Category>> subsMap) {
    final subs = subsMap[parent.id];
    setState(() {
      _selectedCategoryId = (subs == null || subs.isEmpty)
          ? parent.id
          : subs.first.id;
    });
  }

  /// 子分类展开面板：浅色圆角底 + 5 列网格
  ///
  /// [activeIndex] 为选中一级分类在本行中的列位置（0~4），
  /// 顶部三角指示器据此对准选中项。
  Widget _buildSubPanel(List<Category> subs, int activeIndex) {
    // 行内每列等宽，三角形中心对齐第 activeIndex 列的中点
    final arrowX = (activeIndex * 2 + 1) / 5 - 1; // 映射到 Alignment.x（-1 ~ 1）
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment(arrowX, -1),
            child: CustomPaint(
              size: const Size(14, 6),
              painter: _TrianglePainter(),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 0.82,
            ),
            itemCount: subs.length,
            itemBuilder: (context, index) {
              final sub = subs[index];
              return _CategoryCell(
                category: sub,
                selected: sub.id == _selectedCategoryId,
                onTap: () => setState(() => _selectedCategoryId = sub.id),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 数字键盘
  Widget _buildKeyboard() {
    return NumberKeyboard(
      onKey: _onAmountKey,
      onDelete: _onAmountDelete,
      onClear: () => setState(() => _amountText = ''),
      onToday: () => setState(() => _date = DateTime.now()),
      onAgain: () => _save(stay: true),
      onDone: () => _save(),
    );
  }

  // ---------- 金额输入约束 ----------

  /// 键盘数字键入：约束前导零、小数位数与金额上限
  void _onAmountKey(String key) {
    setState(() {
      if (key == '.') {
        // 已含小数点或为空时不可再输入（空时填 0.）
        if (_amountText.contains('.') || _amountText.isEmpty) {
          if (_amountText.isEmpty) _amountText = '0.';
          return;
        }
        _amountText += '.';
        return;
      }
      // 输入首个非零数字时替换掉前导 0
      if (_amountText == '0') {
        _amountText = key;
        return;
      }
      final candidate = _amountText + key;
      // 小数超过两位则忽略
      final dotIndex = candidate.indexOf('.');
      if (dotIndex >= 0 && candidate.length - dotIndex - 1 > 2) return;
      final cents = MoneyUtil.yuanToCents(candidate);
      if (cents == null || cents > _maxAmountCents) return;
      _amountText = candidate;
    });
  }

  /// 退格
  void _onAmountDelete() {
    if (_amountText.isEmpty) return;
    setState(
      () => _amountText = _amountText.substring(0, _amountText.length - 1),
    );
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
    final cents = MoneyUtil.yuanToCents(_amountText);
    if (cents == null || cents == 0) {
      _toast('请输入正确的金额');
      return;
    }
    if (_selectedCategoryId == null) {
      _toast('请选择分类');
      return;
    }
    final note = _noteController.text.trim();
    final provider = context.read<BillProvider>();
    if (_isEditing) {
      final bill = widget.editBill!;
      await provider.updateBill(
        Bill(
          id: bill.id,
          type: _type,
          amountCents: cents,
          categoryId: _selectedCategoryId!,
          note: note.isEmpty ? null : note,
          date: _date,
          timeMinute: _timeMinute,
          location: _locationName,
          locationFull: _locationFull,
          lat: _selectedPoint?.lat,
          lng: _selectedPoint?.lng,
          createdAt: bill.createdAt,
        ),
      );
    } else {
      await provider.addBill(
        BillsCompanion.insert(
          type: _type,
          amountCents: cents,
          categoryId: _selectedCategoryId!,
          date: _date,
          timeMinute: Value(_timeMinute),
          note: Value(note.isEmpty ? null : note),
          location: Value(_locationName),
          locationFull: Value(_locationFull),
          lat: Value(_selectedPoint?.lat),
          lng: Value(_selectedPoint?.lng),
        ),
      );
    }
    // 记账成功后检查预算用量（仅支出记账会占预算）
    if (_type == BillType.expense) await _checkBudgetHint();
    if (stay) {
      // 再记：重置金额与备注，继续记录下一笔
      if (!mounted) return;
      setState(() {
        _amountText = '';
        _noteController.clear();
      });
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 已提示过的预算级别（会话内去重）：如 'total-2'（总预算超支）、
  /// 'cat-12-1'（分类 12 用量超 80%）
  final Set<String> _budgetHintKeys = {};

  /// 记账后预算提醒：支出落库后检查账单所在月的总预算与该分类
  /// （二级归并到一级）预算用量，越过 80% 或超支时轻提示。
  /// 总预算与分类预算同时越线时只提示总预算，避免连弹。
  Future<void> _checkBudgetHint() async {
    final provider = context.read<BudgetProvider>();
    final month = DateTime(_date.year, _date.month);
    // 分类归并：账单挂在二级分类时按一级分类的预算检查
    final categories =
        await context.read<CategoryProvider>().categoriesMapStream().first;
    final cat = categories[_selectedCategoryId];
    // ?? 0 兜底类型：0 不会匹配任何分类预算（categoryId > 0），
    // 正常路径下 _selectedCategoryId 在保存时已校验非空
    final topId = cat?.parentId ?? _selectedCategoryId ?? 0;
    if (!mounted) return;
    final topName = cat == null
        ? '该分类'
        : categories[topId]?.name ?? cat.name;

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
      final target =
          budgets.where((b) => b.categoryId == topId && b.amountCents > 0);
      if (target.isNotEmpty) {
        final summaries = await provider.categorySummaryStream(month).first;
        final spent = summaries
            .firstWhere((s) => s.categoryId == topId,
                orElse: () => CategorySummary(
                      categoryId: topId,
                      name: topName,
                      iconCode: 0,
                      colorValue: 0,
                      type: BillType.expense,
                      totalCents: 0,
                    ))
            .totalCents;
        hint = _budgetHintText(
            'cat', topId, '「$topName」预算', spent, target.first.amountCents);
      }
    }
    if (hint != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hint), behavior: SnackBarBehavior.floating),
      );
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

  /// 编辑模式：删除账单（二次确认）
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
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
    if (confirmed == true && mounted) {
      await context.read<BillProvider>().deleteBill(widget.editBill!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// 轻提示
  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// 一级分类单元：圆形浅底图标，选中时分类色实底白图标，
/// 与子分类面板内的选中风格保持一致
class _ParentCell extends StatelessWidget {
  const _ParentCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        // 去掉方形水波/高亮：选中反馈只由图标底色渐变承担
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  // 选中：分类色实底白图标；未选中：分类色浅底
                  color: selected ? color : color.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: category.iconCode == kTextIconCode
                    ? Text(
                        category.name.isEmpty
                            ? '?'
                            : category.name.characters.first,
                        style: TextStyle(
                          color: selected ? Colors.white : color,
                          fontSize: 21,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Icon(
                        // ignore: non_const_argument_for_const_parameter
                        IconData(category.iconCode, fontFamily: 'MaterialIcons'),
                        color: selected ? Colors.white : color,
                        size: 21,
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  color: selected ? color : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 面板顶部三角指示器：与面板同色，营造"气泡指向选中一级分类"的效果
class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.fill;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 分类网格单元（子分类面板内使用）
class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return InkWell(
      onTap: onTap,
      // 去掉方形水波/高亮：选中反馈只由图标底色渐变承担
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              // 选中：分类色实底白图标；未选中：分类色浅底
              color: selected ? color : color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: category.iconCode == kTextIconCode
                ? Text(
                    category.name.isEmpty
                        ? '?'
                        : category.name.characters.first,
                    style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontSize: 21,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Icon(
                    // ignore: non_const_argument_for_const_parameter
                    IconData(category.iconCode, fontFamily: 'MaterialIcons'),
                    color: selected ? Colors.white : color,
                    size: 21,
                  ),
          ),
          const SizedBox(height: 5),
          Text(
            category.name,
            style: TextStyle(
              fontSize: 12,
              color: selected ? color : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
