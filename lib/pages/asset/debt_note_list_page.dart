import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../providers/debt_note_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/bill_list_item.dart';
import '../../widgets/debt_flow_row.dart';
import '../../widgets/debt_note_detail_sheet.dart';
import '../../widgets/section_card.dart';
import 'debt_note_edit_page.dart';

/// 借条列表页：借出/借入台账
///
/// 顶部两列合计（全部口径，含"不计入统计"的记录）+ 借条列表；
/// 行点击弹详情（详情里再进编辑），右下角新增。
class DebtNoteListPage extends StatefulWidget {
  const DebtNoteListPage({super.key});

  @override
  State<DebtNoteListPage> createState() => _DebtNoteListPageState();
}

class _DebtNoteListPageState extends State<DebtNoteListPage> {
  /// 三条流都在页面生命周期内恒定：只建一次，重建不重订阅
  late final Stream<List<DebtNote>> _allStream = context
      .read<DebtNoteProvider>()
      .allStream();
  late final Stream<Set<int>> _photoStream = context
      .read<DebtNoteProvider>()
      .photoNoteIdsStream();
  late final Stream<Map<int, Asset>> _assetsStream = context
      .read<AssetProvider>()
      .assetsMapStream();

  /// 各借条已还本金总额（noteId → 分）：合计与行剩余口径数据源
  late final Stream<Map<int, int>> _repaidStream = context
      .read<DebtNoteProvider>()
      .repaidTotalsStream();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('借条')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'debt_note_add_fab',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DebtNoteEditPage()),
        ),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<DebtNote>>(
        stream: _allStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final list = snapshot.data!;
          final lendOut = list
              .where((n) => n.direction == DebtDirection.lendOut)
              .toList();
          final borrowIn = list
              .where((n) => n.direction == DebtDirection.borrowIn)
              .toList();
          final masked = context.watch<AssetProvider>().masked;
          return StreamBuilder<Map<int, int>>(
            stream: _repaidStream,
            builder: (context, repaidSnap) {
              final repaid = repaidSnap.data ?? const <int, int>{};
              int remaining(DebtNote n) =>
                  n.amountCents - (repaid[n.id] ?? 0);
              // 合计为剩余口径（与资产页净值中的借条口径一致）
              final lendTotal = lendOut.fold<int>(
                0,
                (s, n) => s + remaining(n),
              );
              final borrowTotal = borrowIn.fold<int>(
                0,
                (s, n) => s + remaining(n),
              );
              return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSection,
              AppDimens.pagePadding,
              // 底部预留 FAB 高度+边距，末行不被悬浮按钮遮挡
              88,
            ),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    Expanded(
                      child: _TotalCell(
                        icon: Icons.north_east,
                        label: '总借出',
                        count: lendOut.length,
                        cents: lendTotal,
                        color: AppColors.income,
                        masked: masked,
                      ),
                    ),
                    Container(width: 1, height: 32, color: AppColors.divider),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppDimens.gapMd),
                        child: _TotalCell(
                          icon: Icons.south_west,
                          label: '总借入',
                          count: borrowIn.length,
                          cents: borrowTotal,
                          color: AppColors.expense,
                          masked: masked,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.gapSection),
              if (list.isEmpty)
                const _EmptyHint()
              else
                // 借据照片标记 + 关联账户字典：行相机角标与金额下小字
                StreamBuilder<Set<int>>(
                  stream: _photoStream,
                  builder: (context, photoSnap) {
                    final photoNoteIds = photoSnap.data ?? const <int>{};
                    return StreamBuilder<Map<int, Asset>>(
                      stream: _assetsStream,
                      builder: (context, assetSnap) {
                        final assets = assetSnap.data ?? const <int, Asset>{};
                        return SectionCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < list.length; i++) ...[
                                if (i > 0)
                                  const Divider(indent: 16, endIndent: 16),
                                DebtFlowRow(
                                  note: list[i],
                                  hasImage: photoNoteIds.contains(list[i].id),
                                  accountLine: debtAccountLine(list[i], assets),
                                  paidCents: repaid[list[i].id] ?? 0,
                                  onTap: () => showDebtNoteDetailSheet(
                                    context,
                                    note: list[i],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 合计单元：方向图标 + 标签 + 笔数 + 金额
class _TotalCell extends StatelessWidget {
  const _TotalCell({
    required this.icon,
    required this.label,
    required this.count,
    required this.cents,
    required this.color,
    required this.masked,
  });

  final IconData icon;
  final String label;
  final int count;
  final int cents;
  final Color color;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppDimens.gapSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label（$count 笔）',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                masked
                    ? '¥ ****'
                    : '¥${MoneyUtil.centsToYuanGroupedTrimmed(cents)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 空态引导
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: AppDimens.gapSm),
            const Text(
              '还没有借条，点击右下角记录借出/借入',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
