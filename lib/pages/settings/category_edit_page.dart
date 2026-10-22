import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../providers/category_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/show_toast.dart';
import '../../widgets/category_avatar.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/color_palette_picker.dart';
import '../../widgets/section_card.dart';

/// 添加 / 编辑分类全屏页（钱迹式）
///
/// 三种模式由构造参数决定：
/// · 新增一级：[category] 为 null 且 [parent] 为 null
/// · 新增二级：[category] 为 null、[parent] 为所属一级分类
/// · 编辑：[category] 非空
/// 功能：批量添加（名称按逗号等分隔一次建多个）、分组图标库搜索、
/// 编辑模式底部删除（连带删除子分类与账单，需确认）。
class CategoryEditPage extends StatefulWidget {
  const CategoryEditPage({
    super.key,
    required this.type,
    this.parent,
    this.category,
  });

  final BillType type;

  /// 新增二级分类时的所属一级分类
  final Category? parent;

  /// 编辑模式下的分类
  final Category? category;

  @override
  State<CategoryEditPage> createState() => _CategoryEditPageState();
}

class _CategoryEditPageState extends State<CategoryEditPage> {
  late final TextEditingController _nameController;
  bool _batch = false; // 批量添加开关（仅新增模式显示）：多选图标批量建分类
  String _search = ''; // 图标搜索词
  int _groupIndex = 0; // 当前选中的图标分组下标
  late int _iconCode; // 当前选中的图标 codePoint（单选模式）

  /// 左侧分组列滚动控制器：编辑模式定位分组后自动滚到可视区
  final ScrollController _groupTabController = ScrollController();

  /// 单个分组 tab 的固定槽高（含上下 margin 2×2）
  static const double _tabExtent = 40;

  /// 当前选中图标的固定分类色：预览与图标网格选中态共用，
  /// 颜色由图标唯一决定，保存时写入同一颜色
  int get _colorValue =>
      _manualColor ?? kCategoryIconColorMap[_iconCode] ?? kCategoryColorChoices.first;

  /// 手动选择的分类色：非空时不再随换图标联动（点预览选色后置值）
  int? _manualColor;

  /// 当前是否为文字图标（不用图标库，头像显示名称首字）
  bool get _isTextIcon => _iconCode == kTextIconCode;

  /// 批量模式下多选的图标 codePoint 集合
  final Set<int> _batchIcons = {};

  bool get _isEditing => widget.category != null;

  /// 是否为二级分类（编辑时按其 parentId 判断）
  bool get _isSub =>
      _isEditing ? widget.category!.parentId != null : widget.parent != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    // 文字图标模式下预览显示名称首字，输入即刷新
    _nameController.addListener(() {
      if (_isTextIcon && mounted) setState(() {});
    });
    // 新增默认文字图标（不选任何图标 = 显示名称首字），编辑回显原值
    _iconCode = widget.category?.iconCode ?? kTextIconCode;
    // 编辑时定位到该图标所在分组
    if (_isEditing) {
      final gi = kCategoryIconGroups.indexWhere(
        (g) => g.icons.any((i) => i.$1.codePoint == _iconCode),
      );
      if (gi >= 0) {
        _groupIndex = gi;
        // 定位的分组可能落在左列可视区之外，首帧后按固定槽高滚到该 tab
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_groupTabController.hasClients) return;
          final max = _groupTabController.position.maxScrollExtent;
          _groupTabController.jumpTo(
            (_groupIndex * _tabExtent).clamp(0.0, max),
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _groupTabController.dispose();
    super.dispose();
  }

  String get _title {
    if (_isEditing) return _isSub ? '编辑二级分类' : '编辑一级分类';
    return _isSub ? '添加二级分类' : '添加一级分类';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CategoryProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        leading: const BackButton(),
        title: Text(
          _title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          // 顶栏"保存"：钱迹为右上角文字按钮
          TextButton(
            onPressed: () => _save(provider),
            child: const Text(
              '保存',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.pagePadding),
        children: [
          // 批量添加：仅新增模式提供，名称按分隔符拆分一次建多个
          if (!_isEditing) _buildBatchCard(),
          const SizedBox(height: 10),
          _buildInfoCard(),
          const SizedBox(height: 10),
          _buildIconCard(),
        ],
      ),
    );
  }

  /// 批量添加卡：开关打开后名称框支持"餐饮、购物、交通"式批量输入
  Widget _buildBatchCard() {
    return SectionCard(
      // 覆盖 SectionCard 默认 16 内边距：上下 4，行高 48（4+40+4）
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Text(
            '批量添加',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          // 缩小开关：FittedBox 整体等比缩放 Switch（默认 60x48），
          // 占位 40x40 与图标预览同高，撑起行高 48
          SizedBox(
            width: 40,
            height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Switch(
                value: _batch,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() {
                  _batch = v;
                  // 关闭批量时：以已选图标中第一个作为单选，并带出名称
                  if (!v && _batchIcons.isNotEmpty) {
                    _iconCode = _batchIcons.first;
                    _nameController.text = _labelOf(_iconCode);
                    _batchIcons.clear();
                  }
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分类信息卡：一级为单行（分类信息 + 名称 + 方形预览）；
  /// 新增二级为两行（一级分类只读 + 二级分类输入 + 圆形预览）。
  /// 批量添加模式无名称输入（名称取图标语义名）：一级整卡隐藏，
  /// 二级仅显示所属一级分类只读行（钱迹图2/图3）。
  Widget _buildInfoCard() {
    if (_batch) {
      if (!_isSub) return const SizedBox.shrink();
      return SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              const Text(
                '一级分类',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                // 兜底空串：parent 理论上必有（跳转前已按 parentId 查出）
                widget.parent?.name ?? '',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final preview = _buildPreview();
    if (!_isSub) {
      return SectionCard(
        // 覆盖默认 16 内边距：上下 4 + 预览 40 = 行高 48，与批量添加行一致
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            const Text(
              '分类信息',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildNameField()),
            // 名称与图标预览拉开间距（右对齐文字紧贴预览不美观）
            const SizedBox(width: 12),
            preview,
          ],
        ),
      );
    }
    // 新增二级：显示所属一级分类 + 二级名称输入
    return SectionCard(
      // 覆盖默认 16 内边距：两行内容紧凑排布
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          // 一级分类只读行：固定 28 高（用户指定），与二级行视觉平衡
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const Text(
                  '一级分类',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  // 兜底空串：parent 理论上必有（跳转前已按 parentId 查出）
                  widget.parent?.name ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 10, thickness: 1, color: AppColors.fill),
          Row(
            children: [
              const Text(
                '二级分类',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildNameField()),
              const SizedBox(width: 12),
              preview,
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      autofocus: !_isEditing,
      textAlign: TextAlign.right,
      maxLength: 10,
      inputFormatters: [LengthLimitingTextInputFormatter(10)],
      // 紧凑行高：卡片行高固定 28，输入区不得撑高
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        counterText: '',
        hintText: '输入分类名称',
        hintStyle: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
        border: InputBorder.none,
      ),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    );
  }

  /// 图标预览：统一分类头像（40/21，文字图标显示名称首字），
  /// 点击弹出 9 色色板手动选色
  Widget _buildPreview() {
    return GestureDetector(
      onTap: _pickColor,
      child: CategoryAvatar(
        name: _nameController.text,
        iconCode: _iconCode,
        color: _colorValue,
        size: AppDimens.iconTile,
        iconSize: 21,
      ),
    );
  }

  /// 点击预览图标：弹出 9 色色板选择分类色；手动选色后换图标
  /// 不再覆盖（_manualColor 置值），保存时写入所选颜色
  Future<void> _pickColor() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择颜色',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ColorPalettePicker(
                selectedColor: _colorValue,
                dotSize: 40,
                onChanged: (c) => Navigator.pop(ctx, c),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _manualColor = picked);
    }
  }

  /// 分类图标卡：标题 + 搜索框；左组列 + 右 4 列图标网格，
  /// 搜索时隐藏组列、跨组平铺匹配结果
  Widget _buildIconCard() {
    final query = _search.trim();
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '分类图标',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _buildSearchBox(),
            ],
          ),
          const SizedBox(height: 10),
          if (query.isEmpty)
            // 定高图标区：分组扩到 15 个后左列远高于单组网格内容，
            // 左右各自内部滚动（钱迹样式），卡片高度不再随组数膨胀
            SizedBox(
              height: 400,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: ListView.builder(
                      controller: _groupTabController,
                      padding: EdgeInsets.zero,
                      // 每个 tab 槽高固定：编辑定位按纯算术滚到可视区
                      itemExtent: _tabExtent,
                      itemCount: kCategoryIconGroups.length,
                      itemBuilder: (_, i) => _buildGroupTab(i),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildIconGrid(
                      kCategoryIconGroups[_groupIndex].icons,
                      scrollable: true,
                    ),
                  ),
                ],
              ),
            )
          else
            // 搜索模式：所有分组中按名称匹配的图标平铺
            _buildIconGrid([
              for (final g in kCategoryIconGroups)
                for (final item in g.icons)
                  if (item.$2.contains(query)) item,
            ]),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    // 搜索框：38 高胶囊，图标/文字/内边距与高度协调
    //（此前 contentPadding vertical 36 与容器高度不匹配导致文字溢出变形）
    return SizedBox(
      width: 132,
      height: 38,
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        // 提示文字/输入内容垂直居中（contentPadding 归零后默认贴顶）
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: '搜索',
          hintStyle: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 12, right: 6),
            child: Icon(Icons.search, size: 18, color: AppColors.textSecondary),
          ),
          // minHeight 与框同高，保证图标垂直居中
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 38,
          ),
          filled: true,
          fillColor: AppColors.fill,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(19),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// 名称是否为图标库中的语义名（区分用户自定义名称）
  bool _isAutoName(String name) {
    return kCategoryIconGroups.any((g) => g.icons.any((i) => i.$2 == name));
  }

  /// 图标 codePoint 对应的语义名（批量建分类时作为名称）
  String _labelOf(int codePoint) {
    for (final g in kCategoryIconGroups) {
      for (final (icon, label) in g.icons) {
        if (icon.codePoint == codePoint) return label;
      }
    }
    return '其它';
  }

  /// 左侧分组 Tab：选中态蓝字 + 浅蓝圆角底（钱迹样式）
  Widget _buildGroupTab(int index) {
    final selected = index == _groupIndex;
    return InkWell(
      onTap: () => setState(() => _groupIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          kCategoryIconGroups[index].name,
          maxLines: 1,
          // 行高钉死：tab 槽高由 itemExtent 固定，防止系统字体
          // 行高偏大撑破定高槽（UI 防溢出铁律）
          style: TextStyle(
            fontSize: 14,
            height: 1.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 4 列图标网格：圆形彩色图标 + 语义名称
  ///
  /// 普通模式单选（名称跟随带出）；批量模式多选（每个选中图标
  /// 各建一个分类）。每个图标固定自己的分类色：未选中浅色底 +
  /// 彩色图标，选中实底白图标，与记一笔页分类格子风格一致。
  Widget _buildIconGrid(List<CategoryIconItem> items, {bool scrollable = false}) {
    return GridView.builder(
      // 定高区域内滚动浏览；搜索模式保持 shrinkWrap 随内容撑开
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 6,
        // 固定行高（px）而非宽高比：40 圆底 + 4 间距 + 文字，
        // 系统字体缩放时也有余量，彻底杜绝 bottom overflow
        mainAxisExtent: 68,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (icon, label) = items[index];
        final selected = _batch
            ? _batchIcons.contains(icon.codePoint)
            : icon.codePoint == _iconCode;
        // 每个图标固定自己的分类色：未选中浅色底 + 彩色图标，选中实底白图标
        final iconColor = Color(
          kCategoryIconColorMap[icon.codePoint] ?? kCategoryColorChoices.first,
        );
        return InkWell(
          onTap: () {
            if (_batch) {
              // 批量模式：切换多选状态
              setState(() {
                _batchIcons.contains(icon.codePoint)
                    ? _batchIcons.remove(icon.codePoint)
                    : _batchIcons.add(icon.codePoint);
              });
              return;
            }
            // 再点已选中的图标 = 取消选中，回到文字模式（B 方案 toggle）
            final deselect = _iconCode == icon.codePoint;
            setState(() {
              _iconCode = deselect ? kTextIconCode : icon.codePoint;
            });
            if (deselect) return;
            // 名称跟随图标：输入框为空、或仍为某个图标的语义名
            //（用户未手动自定义）时，自动带出所选图标名称
            final name = _nameController.text.trim();
            if (name.isEmpty || _isAutoName(name)) {
              _nameController.text = label;
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? iconColor
                      : iconColor.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: selected ? Colors.white : iconColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- 保存 ----------

  /// 保存：新增（含批量）与编辑共用；所有分支保存前做兄弟重名校验
  /// （0 级 = 收/支：一级查同 type 全部一级，二级查同一父下的全部二级）
  Future<void> _save(CategoryProvider provider) async {
    final all = await provider.categoriesStream(widget.type).first;
    if (_isEditing) {
      final name = _nameController.text.trim();
      if (name.isEmpty) return;
      // 编辑改名：位置不变，查原父下的兄弟重名（排除自己）
      final dup = await provider.siblingNameExists(
        name: name,
        type: widget.type,
        parentId: widget.category!.parentId,
        excludeId: widget.category!.id,
      );
      if (!mounted) return;
      if (dup) {
        showAppToast(context, '同层级下已存在同名分类');
        return;
      }
      // 编辑改名称、图标与颜色（颜色由图标固定映射决定）
      await provider.updateCategory(
        widget.category!.copyWith(
          name: name,
          iconCode: _iconCode,
          colorValue: _colorValue,
        ),
      );
    } else if (_batch) {
      // 批量模式：每个选中图标各建一个分类，名称取图标语义名，
      // 颜色用图标固定映射色（各不相同）；与已有分类重名的自动跳过
      final codes = _batchIcons.toList();
      if (codes.isEmpty) return;
      final parentId = widget.parent?.id;
      var nextSort = all.where((c) => c.parentId == parentId).length;
      var added = 0;
      var skipped = 0;
      for (final code in codes) {
        final dup = await provider.siblingNameExists(
          name: _labelOf(code),
          type: widget.type,
          parentId: parentId,
        );
        if (dup) {
          skipped++;
          continue;
        }
        await provider.addCategory(
          CategoriesCompanion.insert(
            name: _labelOf(code),
            iconCode: code,
            colorValue: kCategoryIconColorMap[code] ?? kCategoryColorChoices.first,
            type: widget.type,
            parentId: Value(parentId),
            sortOrder: Value(nextSort),
          ),
        );
        nextSort++;
        added++;
      }
      if (!mounted) return;
      if (added > 0 && skipped > 0) {
        showAppToast(context, '已添加 $added 个，跳过 $skipped 个重名');
      } else if (added == 0) {
        showAppToast(context, '所选名称均已存在，未添加');
      }
    } else {
      final name = _nameController.text.trim();
      if (name.isEmpty) return;
      final parentId = widget.parent?.id;
      final dup = await provider.siblingNameExists(
        name: name,
        type: widget.type,
        parentId: parentId,
      );
      if (!mounted) return;
      if (dup) {
        showAppToast(context, '同层级下已存在同名分类');
        return;
      }
      final siblingCount = all.where((c) => c.parentId == parentId).length;
      await provider.addCategory(
        CategoriesCompanion.insert(
          name: name,
          iconCode: _iconCode,
          // 预览已按此色显示，保存写入同一颜色保持一致
          colorValue: _colorValue,
          type: widget.type,
          parentId: Value(parentId),
          sortOrder: Value(siblingCount),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }
}
