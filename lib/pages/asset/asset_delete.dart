import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../providers/asset_provider.dart';
import '../../widgets/confirm_dialog.dart';

/// 删除资产的统一确认流程：查关联账单数 → 确认框 → 执行删除。
/// 编辑页与归档行两个入口共用，确认口径与文案保持一致。
/// 返回 true = 已删除（调用方据此处理自身退出，如详情页随之关闭）
Future<bool> confirmDeleteAsset(BuildContext context, Asset asset) async {
  final provider = context.read<AssetProvider>();
  final count = await provider.relatedBillCount(asset.id);
  if (!context.mounted) return false;
  final confirmed = await showConfirmDialog(
    context,
    title: '删除资产',
    content: '删除后「${asset.name}」及其历史快照将被清除，不可恢复。'
        '${count > 0 ? '$count 笔关联账单会保留，但不再关联此账户。' : ''}',
    confirmText: '删除',
    danger: true,
  );
  if (!confirmed) return false;
  await provider.deleteAsset(asset);
  return true;
}
