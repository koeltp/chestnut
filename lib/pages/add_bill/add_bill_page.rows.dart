part of 'add_bill_page.dart';

/// 备注与金额行、优惠金额行、标签选择面板
mixin _NoteRows on _AddBillBase {
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
}
