part of 'add_bill_page.dart';

/// 保存账单与预算提醒
mixin _SaveAndBudget on _AddBillBase {
  // ---------- 保存 / 删除 ----------

  /// 保存账单（新增或更新）
  ///
  /// [stay] 为 true 时"再记"：保存后清空金额与备注并留在页面，
  /// 保留分类与日期，便于连续记账。
  Future<void> _save({bool stay = false}) async {
    // 实付允许为 0（免单），但实付为 0 必须有优惠；无优惠时实付必须 >0。
    // 留空按 0 处理，使用户在优惠模式直接保存即可记一笔免单
    final cents = MoneyUtil.yuanToCents(_draft.amountText) ?? 0;
    // 优惠额：0/空视为未优惠存 null；优惠可大于实付（平台补贴券等），
    // 不设上限约束。收入/转账入口已隐藏且切类型会清空，这里再兜底
    var discountCents = MoneyUtil.yuanToCents(_draft.discountText);
    if (discountCents != null && discountCents == 0) discountCents = null;
    if (_draft.type != BillType.expense) discountCents = null;
    if (cents == 0 && discountCents == null) {
      showAppToast(context, '请输入正确的金额');
      return;
    }
    // 转账：两账户必选且不能相同，不挂分类；其余类型维持分类必选校验
    if (_draft.type == BillType.transfer) {
      if (_draft.selectedAssetId == null || _draft.toAssetId == null) {
        showAppToast(context, '请选择转出与转入账户');
        return;
      }
      if (_draft.selectedAssetId == _draft.toAssetId) {
        showAppToast(context, '转出与转入不能是同一账户');
        return;
      }
    } else if (_draft.selectedCategoryId == null) {
      showAppToast(context, '请选择分类');
      return;
    }
    final note = _draft.note.trim();
    final provider = context.read<BillProvider>();
    final tagRepo = context.read<TagRepository>();
    // 图片收尾要用云存储配置：在首个 await 前取好，避免跨异步间隙用 context
    final cloud = context.read<CloudStorageProvider>();
    // 记忆账户要用资产状态：同样在首个 await 前取好
    final assetProvider = context.read<AssetProvider>();
    late final int savedBillId;
    // 落库可因业务规则抛出（如账户余额不足），必须给用户反馈，
    // 否则保存像"点了没反应"；余额不足直接用仓储层的中文文案
    try {
      if (_isEditing) {
        final bill = widget.editBill!;
        savedBillId = bill.id;
        await provider.updateBill(
          Bill(
            id: bill.id,
            type: _draft.type,
            amountCents: cents,
            discountCents: discountCents,
            categoryId: _draft.selectedCategoryId,
            note: note.isEmpty ? null : note,
            date: _draft.date,
            timeMinute: _draft.timeMinute,
            location: _draft.locationName,
            locationFull: _draft.locationFull,
            lat: _draft.selectedPoint?.lat,
            lng: _draft.selectedPoint?.lng,
            assetId: _draft.selectedAssetId,
            toAssetId: _draft.type == BillType.transfer ? _draft.toAssetId : null,
            createdAt: bill.createdAt,
          ),
        );
        // 编辑：全量替换标签关联
        await tagRepo.setBillTags(bill.id, _draft.selectedTagIds.toList());
      } else {
        final billId = await provider.addBill(
          BillsCompanion.insert(
            type: _draft.type,
            amountCents: cents,
            discountCents: Value(discountCents),
            categoryId: Value(_draft.selectedCategoryId),
            date: _draft.date,
            timeMinute: Value(_draft.timeMinute),
            note: Value(note.isEmpty ? null : note),
            location: Value(_draft.locationName),
            locationFull: Value(_draft.locationFull),
            lat: Value(_draft.selectedPoint?.lat),
            lng: Value(_draft.selectedPoint?.lng),
            assetId: Value(_draft.selectedAssetId),
            toAssetId: Value(_draft.type == BillType.transfer ? _draft.toAssetId : null),
          ),
        );
        savedBillId = billId;
        // 新增：关联标签
        if (_draft.selectedTagIds.isNotEmpty) {
          await tagRepo.setBillTags(billId, _draft.selectedTagIds.toList());
        }
      }
    } on InsufficientBalanceException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.toString());
      return;
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '保存失败：$e');
      return;
    }
    // 新增成功记住本次关联的账户，下次进记一笔页默认带回；显式选了
    // "不关联"也照存（null 清除记录），尊重用户的选择。编辑旧账单
    // 不改记忆——历史账单的账户不该影响下一笔的默认值
    if (!_isEditing) {
      unawaited(assetProvider.setLastBillAssetId(_draft.selectedAssetId));
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
    if (_draft.type == BillType.expense) await _checkBudgetHint();
    if (stay) {
      // 再记：重置金额与备注，继续记录下一笔（图片已随上一笔保存，一并清空）
      if (!mounted) return;
      setState(() {
        _draft.amountText = '';
        _draft.discountText = '';
        _discountMode = false;
        _noteController.clear();
        _draft.note = '';
        _draft.selectedTagIds.clear();
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
    final month = DateTime(_draft.date.year, _draft.date.month);
    // 分类归并：账单挂在二级分类时按一级分类的预算检查
    final categories = await context
        .read<CategoryProvider>()
        .categoriesMapStream()
        .first;
    final cat = categories[_draft.selectedCategoryId];
    // ?? 0 兜底类型：0 不会匹配任何分类预算（categoryId > 0），
    // 正常路径下 _draft.selectedCategoryId 在保存时已校验非空
    final topId = cat?.parentId ?? _draft.selectedCategoryId ?? 0;
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
