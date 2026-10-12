import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_card.dart';

/// 历史市值记录页：按日列出某资产的全部市值快照，可修正可删除
///
/// 快照本身"只增不删"（每次更新市值落一条），误输市值（如多打一个 0）
/// 后净值曲线会留尖刺——这里是唯一的清理入口。展示/编辑/删除都以"日"
/// 为单位，与净值聚合"当天最后一条"口径一致
class AssetSnapshotHistoryPage extends StatelessWidget {
  const AssetSnapshotHistoryPage({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return Scaffold(
      appBar: AppBar(title: const Text('历史市值记录')),
      body: StreamBuilder<List<AssetSnapshot>>(
        stream: context.read<AssetProvider>().snapshotStream(asset.id),
        builder: (context, snapshot) {
          final snaps = snapshot.data ?? const <AssetSnapshot>[];
          if (snaps.isEmpty) {
            return const Center(
              child: Text(
                '暂无记录，更新市值后按日留存',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSection,
              AppDimens.pagePadding,
              24,
            ),
            children: [
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < snaps.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 16),
                      _SnapshotRow(
                        asset: asset,
                        snap: snaps[i],
                        masked: masked,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '市值按日留存，可修正或删除误输的数值，净值曲线随记录实时更新',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 单条记录行：日期 + 当日市值 + 修正/删除
class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required this.asset,
    required this.snap,
    required this.masked,
  });

  final Asset asset;
  final AssetSnapshot snap;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              snap.day,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            masked
                ? '¥ ****'
                : '¥${MoneyUtil.centsToYuanGroupedTrimmed(snap.valueCents)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '修正',
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            onPressed: () => _edit(context),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '删除',
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.expense,
            ),
            onPressed: () => _delete(context),
          ),
        ],
      ),
    );
  }

  /// 修正该日市值：弹出输入对话框（预填当前值），确认后该日整日落新值。
  /// 与更新市值一致拒绝非正数（快照恒为正，负债由资产类型区分）
  Future<void> _edit(BuildContext context) async {
    // provider 在首个 await 前取好，避免跨异步缺口使用 BuildContext
    final provider = context.read<AssetProvider>();
    final controller = TextEditingController(
      text: MoneyUtil.centsToYuan(snap.valueCents),
    );
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('修正 ${snap.day}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: MoneyUtil.amountInputFormatters,
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (text == null) return; // 取消不改值
    final cents = MoneyUtil.yuanToCents(text.trim());
    if (cents == null || cents <= 0) {
      if (context.mounted) showAppToast(context, '请输入正确的金额');
      return;
    }
    if (cents == snap.valueCents) return; // 值没变不落新快照
    try {
      await provider.updateSnapshotValue(asset.id, snap.day, cents);
    } catch (_) {
      // 极小概率：资产刚被删除，外键插入失败
      if (context.mounted) showAppToast(context, '修正失败');
    }
  }

  /// 删除该日记录：确认后整日清除，净值曲线该日不再计入该资产
  Future<void> _delete(BuildContext context) async {
    final provider = context.read<AssetProvider>();
    final confirmed = await showConfirmDialog(
      context,
      title: '删除记录',
      content: '删除 ${snap.day} 的市值记录后，净值曲线该日不再计入「${asset.name}」。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    try {
      await provider.deleteSnapshotDay(asset.id, snap.day);
    } catch (_) {
      if (context.mounted) showAppToast(context, '删除失败');
    }
  }
}
