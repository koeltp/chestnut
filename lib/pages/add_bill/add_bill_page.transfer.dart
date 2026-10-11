part of 'add_bill_page.dart';

/// 转账模式的转出/转入账户选择区
mixin _TransferArea on _AddBillBase {
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
}
