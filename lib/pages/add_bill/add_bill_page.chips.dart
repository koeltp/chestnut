part of 'add_bill_page.dart';

/// 底部胶囊行：账户/日期/优惠/图片/定位
mixin _Chips on _AddBillBase {
  /// 胶囊行：账户（支出/收入，弹窗选择）/ 日期 / 优惠 / 图片 / 定位。
  /// 日期胶囊：今天/昨天/前天显示相对日期，其余显示 M月d日，统一附带时间；
  /// 点击弹出日期滚轮（内含今/昨/前快捷与时间选择入口）。
  Widget _buildChipRow() {
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(_draft.date.year, _draft.date.month, _draft.date.day)).inDays;
    final hh = (_draft.timeMinute ~/ 60).toString().padLeft(2, '0');
    final mm = (_draft.timeMinute % 60).toString().padLeft(2, '0');
    final label = switch (diff) {
      0 => '今天 $hh:$mm',
      1 => '昨天 $hh:$mm',
      2 => '前天 $hh:$mm',
      _ => '${_draft.date.month}月${_draft.date.day}日 $hh:$mm',
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
              if (_draft.type != BillType.transfer) ...[
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
              if (_draft.type == BillType.expense) ...[
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
    final discountCents = MoneyUtil.yuanToCents(_draft.discountText);
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
    final hasLocation = _draft.locationName != null;
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
              hasLocation ? _draft.locationName! : '定位',
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
                  _draft.locationName = null;
                  _draft.locationFull = null;
                  _draft.selectedPoint = null;
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
          initialName: _draft.locationName,
          initialPoint: _draft.selectedPoint,
        ),
      ),
    );
    if (!mounted) return;
    if (selection != null && selection.name.isNotEmpty) {
      setState(() {
        _draft.locationName = selection.name;
        _draft.selectedPoint = selection.point;
        // 选点页补全了完整地址则更新；无法补全（如"已保存的位置"）
        // 保留旧值，避免把已有的完整信息冲掉
        if (selection.fullAddress != null) {
          _draft.locationFull = selection.fullAddress;
        }
      });
    }
  }

  // ---------- 账户选择（支出/收入胶囊 + 弹窗） ----------

  /// 账户胶囊：显示当前关联账户（未选显示"不关联"），点击弹出
  /// 账户选择面板（与图片胶囊同交互）；上次使用的账户进页时已自动
  /// 带上（见 _restoreLastAsset）。转账模式不显示——两个账户在内容区选
  Widget _buildAssetChip() {
    final asset = _assetById(_draft.selectedAssetId);
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
    setState(() => _draft.selectedAssetId = result.$1?.id);
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
          WheelDatePicker(initial: _draft.date, initialMinute: _draft.timeMinute),
    );
    if (picked != null) {
      setState(() {
        _draft.date = picked.$1;
        _draft.timeMinute = picked.$2;
      });
    }
  }
}
