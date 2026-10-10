import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/asset_repository.dart';
import '../../models/asset_category.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/asset_circle_icon.dart';
import '../../widgets/pie_chart_card.dart';
import '../../widgets/section_card.dart';
import 'asset_category_sheet.dart';
import 'asset_detail_page.dart';
import 'asset_edit_page.dart';
import 'debt_note_list_page.dart';

/// 资产管理页：钱迹式净资产盘点
///
/// 自上而下：净资产总览卡 → 负债率卡 → 总借出/借入卡 → 组聚合列表
/// → 净值走势 → 资产构成 → 已归档折叠区。所有区块随数据库流实时刷新。
class AssetPage extends StatelessWidget {
  const AssetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产管理'),
        actions: [
          // 金额明文/模糊切换：净资产属敏感数字，默认模糊
          IconButton(
            tooltip: '显示/隐藏金额',
            onPressed: () =>
                context.read<AssetProvider>().toggleMasked(),
            icon: Icon(
              context.watch<AssetProvider>().masked
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'asset_add_fab',
        // 钱迹式添加流程：先选分类，再进动态表单页（借出/借入进借条页）
        onPressed: () async {
          final def = await showAssetCategorySheet(context);
          if (def == null || !context.mounted) return;
          await handleAssetCategoryPicked(context, def);
        },
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          24,
        ),
        children: [
          StreamBuilder<AssetSummary>(
            stream: context.read<AssetProvider>().summaryStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              final summary = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NetValueCard(summary: summary),
                  const SizedBox(height: AppDimens.gapSection),
                  _LiabilityRateCard(summary: summary),
                  // 总借出/借入卡：一条借条都没有时不占版面，
                  // 从添加分类选"借出/借入"建第一条后才显示
                  if (summary.lendOutAllCents != 0 ||
                      summary.borrowInAllCents != 0) ...[
                    const SizedBox(height: AppDimens.gapSection),
                    _DebtNoteCard(summary: summary),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppDimens.gapSection),
          _GroupListSection(),
          const SizedBox(height: AppDimens.gapSection),
          StreamBuilder<AssetSummary>(
            stream: context.read<AssetProvider>().summaryStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NetTrendCard(
                    currentNetCents: snapshot.data!.snapshotNetCents,
                  ),
                  const SizedBox(height: AppDimens.gapSection),
                  _StructureCard(),
                ],
              );
            },
          ),
          _ArchivedSection(),
        ],
      ),
    );
  }
}

/// 金额统一展示：模糊态显示占位符；负数带负号
String _fmtAmount(int cents, bool masked) {
  if (masked) return '¥ ****';
  final text = MoneyUtil.centsToYuanGroupedTrimmed(cents.abs());
  return '${cents < 0 ? '-' : ''}¥$text';
}

/// 净值总览卡：总净值大数字 + 总资产/总负债两列（钱迹式布局）
class _NetValueCard extends StatelessWidget {
  const _NetValueCard({required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return SectionCard(
      onTap: () => context.read<AssetProvider>().toggleMasked(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '总净值（总资产 − 总负债）',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimens.gapSm),
          Text(
            _fmtAmount(summary.netCents, masked),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          Row(
            children: [
              Expanded(
                child: _TotalColumn(
                  label: '总资产',
                  cents: summary.totalAssetCents,
                  color: AppColors.primary,
                  masked: masked,
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: AppColors.divider,
              ),
              Expanded(
                child: _TotalColumn(
                  label: '总负债',
                  cents: -summary.totalLiabilityCents,
                  color: AppColors.expense,
                  masked: masked,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 净值卡内两列之一：标签 + 金额在各自区块内居中
class _TotalColumn extends StatelessWidget {
  const _TotalColumn({
    required this.label,
    required this.cents,
    required this.color,
    required this.masked,
  });

  final String label;
  final int cents;
  final Color color;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _fmtAmount(cents, masked),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 负债率卡：资产/负债项数 + 负债率 + 进度条
class _LiabilityRateCard extends StatelessWidget {
  const _LiabilityRateCard({required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    final rate = summary.liabilityRate;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '负债率',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${summary.assetCount} 项资产 | ${summary.liabilityCount} 项负债',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(rate * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: rate > 0.5 ? AppColors.expense : AppColors.income,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppDimens.gapMd),
              Expanded(
                child: Text(
                  masked
                      ? '负债占资产的 ****'
                      : '负债占资产 '
                          '¥${MoneyUtil.centsToYuanGroupedTrimmed(summary.totalLiabilityCents)}'
                          ' / '
                          '¥${MoneyUtil.centsToYuanGroupedTrimmed(summary.totalAssetCents)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 6,
              backgroundColor: AppColors.fill,
              valueColor: AlwaysStoppedAnimation(
                rate > 0.5 ? AppColors.expense : AppColors.income,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 总借出/借入卡：借条台账总量（含"不计入统计"的记录），点击进借条列表
class _DebtNoteCard extends StatelessWidget {
  const _DebtNoteCard({required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return SectionCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DebtNoteListPage()),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.north_east,
                  size: 18,
                  color: AppColors.income,
                ),
                const SizedBox(width: AppDimens.gapSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '总借出',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _fmtAmount(summary.lendOutAllCents, masked),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.income,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.divider),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: AppDimens.gapMd),
              child: Row(
                children: [
                  Icon(
                    Icons.south_west,
                    size: 18,
                    color: AppColors.expense,
                  ),
                  const SizedBox(width: AppDimens.gapSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '总借入',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          _fmtAmount(summary.borrowInAllCents, masked),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.expense,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

/// 组聚合列表：每种资产类型一张独立卡片（钱迹式），组行为
/// 图标 + 组名 + 项数 + 合计，点击原地展开组内账户列表，点账户行
/// 进流水明细页。没有账户的组整个不显示，添加首个账户后才出现。
/// 合计口径：未归档且计入总资产的账户。
class _GroupListSection extends StatefulWidget {
  @override
  State<_GroupListSection> createState() => _GroupListSectionState();
}

class _GroupListSectionState extends State<_GroupListSection> {
  /// 已展开的组名集合（组名即分类体系主键）
  final Set<String> _expanded = {};

  void _toggle(String groupName) {
    setState(() {
      if (!_expanded.remove(groupName)) _expanded.add(groupName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Asset>>(
      stream: context.read<AssetProvider>().activeStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final list = snapshot.data!;
        // 分类名 -> 组：一次遍历完成分桶
        final byGroup = <AssetGroupDef, List<Asset>>{};
        for (final a in list) {
          byGroup.putIfAbsent(AssetGroups.groupOf(a.category), () => []).add(a);
        }
        // 空组不渲染：用户 + 添加首个账户后该组卡片才出现
        final groups = AssetGroups.all
            .where((g) => (byGroup[g] ?? const []).isNotEmpty)
            .toList();
        return Column(
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              SectionCard(
                padding: EdgeInsets.zero,
                child: _GroupRow(
                  group: groups[i],
                  items: byGroup[groups[i]]!,
                  expanded: _expanded.contains(groups[i].name),
                  onToggle: () => _toggle(groups[i].name),
                ),
              ),
              // 组卡片之间的间距（列表首尾由页面统一控制）
              if (i < groups.length - 1)
                const SizedBox(height: AppDimens.gapSection),
            ],
          ],
        );
      },
    );
  }
}

/// 组行：图标 + 组名 + 项数 + 合计 + 旋转 chevron；展开后组内账户
/// 行直接挂在下方（行间分割线，与组行同卡）
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.items,
    required this.expanded,
    required this.onToggle,
  });

  final AssetGroupDef group;
  final List<Asset> items;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    // 组合计只含"计入总资产"的账户（关闭开关的仅展示不计入）
    final total = items
        .where((a) => a.includeInNet)
        .fold<int>(0, (s, a) => s + a.valueCents);
    final color = AssetGroups.colorOf(group.categories.first.name);
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.pagePadding,
              vertical: AppDimens.gapMd,
            ),
            child: Row(
              children: [
                Container(
                  width: AppDimens.iconTile,
                  height: AppDimens.iconTile,
                  decoration: BoxDecoration(
                    color: AppColors.tint(color),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(group.icon, color: color, size: 21),
                ),
                const SizedBox(width: AppDimens.gapMd),
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${items.length} 项',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppDimens.gapMd),
                Text(
                  _fmtAmount(group.kind == AssetKind.liability ? -total : total, masked),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: group.kind == AssetKind.liability
                        ? AppColors.expense
                        : AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                // 展开/收起指示：右 chevron 旋转 90° 变下 chevron
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            _AssetRow(asset: items[i]),
          ],
        ],
      ],
    );
  }
}

/// 资产行（组展开列表内）：点击进账户流水页
class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    final isLiability = asset.kind == AssetKind.liability;
    final subtitle = _subtitleOf(asset);
    final display =
        '¥${MoneyUtil.centsToYuanGroupedTrimmed(asset.valueCents)}';
    return InkWell(
      // 点行进账户流水页；总资产卡整卡可点进编辑页
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AssetDetailPage(assetId: asset.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
          vertical: AppDimens.gapMd,
        ),
        child: Row(
          children: [
            AssetCircleIcon(category: asset.category),
            const SizedBox(width: AppDimens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      // 未计入净值标记：关闭"计入总资产"的账户
                      if (!asset.includeInNet) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.fill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '未计入',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppDimens.gapSm),
            Text(
              masked ? '¥ ****' : display,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isLiability ? AppColors.expense : AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 行副标题：备注优先；信用卡账户展示额度/出账日/还款日摘要
  String? _subtitleOf(Asset asset) {
    if (asset.kind == AssetKind.liability &&
        AssetGroups.groupOf(asset.category) == AssetGroups.credit) {
      final parts = <String>[
        if (asset.creditLimitCents != null)
          '额度 ¥${MoneyUtil.centsToYuanGroupedTrimmed(asset.creditLimitCents!)}',
        if (asset.billDay != null) '出账日 ${asset.billDay}',
        if (asset.repayDay != null) '还款日 ${asset.repayDay}',
      ];
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    final note = asset.note;
    if (note != null && note.isNotEmpty) return note;
    return null;
  }
}

/// 净值曲线卡：历史快照聚合点 + 今天实时净值点（纯资产快照口径）。
/// 点数不足 2 时的空态提示用户更新市值积累曲线。
class _NetTrendCard extends StatelessWidget {
  const _NetTrendCard({required this.currentNetCents});

  final int currentNetCents;

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return StreamBuilder<List<NetValuePoint>>(
      stream: context.read<AssetProvider>().netHistoryStream(),
      builder: (context, snapshot) {
        final history = snapshot.data ?? const <NetValuePoint>[];
        // 末点 = 今天实时净值（不含借条的快照口径）：与历史点口径一致
        final points = [
          ...history,
          (
            DateFormat('yyyy-MM-dd').format(DateTime.now()),
            currentNetCents,
          ),
        ];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '净值走势',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '资产快照口径',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.gapMd),
              SizedBox(height: 180, child: _chart(points, masked)),
            ],
          ),
        );
      },
    );
  }

  /// 单点无法画趋势：给一个引导性空态而不是孤零零一个点
  Widget _chart(List<NetValuePoint> points, bool masked) {
    if (points.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 44,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: AppDimens.gapSm),
            const Text(
              '更新市值后，这里会记录净值走势',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].$2.toDouble()),
    ];
    // 纵轴范围：上下各留 12% 呼吸空间，净值走平（min==max）时垫出可视区间
    final values = points.map((p) => p.$2).toList();
    var minY = values.reduce((a, b) => a < b ? a : b).toDouble();
    var maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    final pad = (maxY - minY) * 0.12;
    minY -= pad == 0 ? 1000 : pad;
    maxY += pad == 0 ? 1000 : pad;
    // 横轴日期抽稀：最多显示 5 个刻度
    final labelStep = (points.length / 5).ceil();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.round();
                final show =
                    idx == 0 ||
                    idx == points.length - 1 ||
                    idx % labelStep == 0;
                if (!show || idx >= points.length) {
                  return const SizedBox.shrink();
                }
                // `yyyy-MM-dd` -> `MM-dd`
                final day = points[idx].$1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    day.length >= 10 ? day.substring(5) : day,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    masked
                        ? '${points[s.x.round()].$1}\n¥ ****'
                        : '${points[s.x.round()].$1}\n'
                            '¥${MoneyUtil.centsToYuanGroupedTrimmed(s.y.round())}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2,
            color: AppColors.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.14),
                  AppColors.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 资产构成卡：未归档且计入总资产的账户按分类求和（复用统计页环形图组件）
class _StructureCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Asset>>(
      stream: context.read<AssetProvider>().activeStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final masked = context.watch<AssetProvider>().masked;
        final assets = snapshot.data!
            .where((a) => a.kind == AssetKind.asset && a.includeInNet)
            .toList();
        // 分类名 -> 市值合计
        final totals = <String, int>{};
        for (final a in assets) {
          totals[a.category] = (totals[a.category] ?? 0) + a.valueCents;
        }
        var total = 0;
        totals.forEach((_, v) => total += v);
        final items = totals.entries.map((e) => (e.key, e.value)).toList();
        return PieChartCard(
          title: '资产构成',
          items: items,
          centerLabel: '资产合计',
          centerValue: masked ? '****' : MoneyUtil.centsToYuanGroupedTrimmed(total),
          centerValueColor: AppColors.primary,
          emptyText: '添加资产后查看构成',
        );
      },
    );
  }
}

/// 已归档折叠区：归档资产不参与净值，可在此恢复
class _ArchivedSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Asset>>(
      stream: context.read<AssetProvider>().archivedStream(),
      builder: (context, snapshot) {
        final list = snapshot.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppDimens.gapSection),
          child: SectionCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  '已归档 (${list.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    _ArchivedRow(asset: list[i]),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 归档行：只读展示 + 恢复按钮
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapSm,
      ),
      child: Row(
        children: [
          Icon(
            AssetGroups.iconOf(asset.category),
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppDimens.gapMd),
          Expanded(
            child: Text(
              asset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => context.read<AssetProvider>().setArchived(
              asset,
              archived: false,
            ),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }
}
