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
class DebtNoteListPage extends StatelessWidget {
  const DebtNoteListPage({super.key});

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
        stream: context.read<DebtNoteProvider>().allStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final list = snapshot.data!;
          final lendOut = list
              .where((n) => n.direction == DebtDirection.lendOut)
              .toList();
          final borrowIn = list
              .where((n) => n.direction == DebtDirection.borrowIn)
              .toList();
          final lendTotal = lendOut.fold<int>(0, (s, n) => s + n.amountCents);
          final borrowTotal = borrowIn.fold<int>(0, (s, n) => s + n.amountCents);
          final masked = context.watch<AssetProvider>().masked;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapSection,
              AppDimens.pagePadding,
              24,
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
                  stream: context.read<DebtNoteProvider>().photoNoteIdsStream(),
                  builder: (context, photoSnap) {
                    final photoNoteIds = photoSnap.data ?? const <int>{};
                    return StreamBuilder<Map<int, Asset>>(
                      stream:
                          context.read<AssetProvider>().assetsMapStream(),
                      builder: (context, assetSnap) {
                        final assets =
                            assetSnap.data ?? const <int, Asset>{};
                        return SectionCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < list.length; i++) ...[
                                if (i > 0)
                                  const Divider(indent: 16, endIndent: 16),
                                DebtFlowRow(
                                  note: list[i],
                                  hasImage:
                                      photoNoteIds.contains(list[i].id),
                                  accountLine:
                                      debtAccountLine(list[i], assets),
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
