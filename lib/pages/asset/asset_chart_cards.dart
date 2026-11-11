import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/asset_repository.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../widgets/pie_chart_card.dart';
import '../../widgets/section_card.dart';
import 'net_trend_chart.dart';
import 'net_trend_data.dart';
import 'net_trend_full_page.dart';

/// 净值曲线卡：历史快照聚合点 + 今天实时净值点（纯资产快照口径）。
/// 四档粒度切换（日/月/季/年）；单点画居中孤点，两点起连线成"势"。
/// 窗口规则与全屏页一致（点间距 20dp），只是固定贴右端、不可横滑。
/// 看历史细节点右上角放大进全屏页。
class NetTrendCard extends StatefulWidget {
  const NetTrendCard({super.key, required this.currentNetCents});

  final int currentNetCents;

  @override
  State<NetTrendCard> createState() => _NetTrendCardState();
}

class _NetTrendCardState extends State<NetTrendCard> {
  /// 默认"日"档，其余档位用户主动切换
  NetTrendRange _range = NetTrendRange.day;

  void _selectRange(NetTrendRange range) {
    if (range == _range) return;
    setState(() => _range = range);
  }

  /// 放大：进横屏全屏页，单指横滑可一直翻到最早的数据
  void _openFullPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NetTrendFullPage(currentNetCents: widget.currentNetCents),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
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
              // 档位切换与放大入口都收进标题行，不额外占卡片高度
              NetTrendRangeSwitch(value: _range, onChanged: _selectRange),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openFullPage,
                child: Padding(
                  // 图标放到 22dp，同时给足可点热区（约 40×34）
                  padding: const EdgeInsets.only(
                    left: 14,
                    top: 6,
                    right: 6,
                    bottom: 6,
                  ),
                  child: SvgPicture.asset(
                    'assets/images/icon_fullscreen.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textSecondary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapSm),
          SizedBox(
            height: 180,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 与图表同一套几何：左轴按当前净值标签的实测宽度预留；
                // 这里只需要估算查询点数，图表内部会按真实标签再算一次
                final leftPad = masked
                    ? 0.0
                    : netTrendTextSize(
                            netTrendAxisLabel(
                              widget.currentNetCents.toDouble(),
                            ),
                            textScaler: MediaQuery.textScalerOf(context),
                          ).width +
                          kTrendAxisPadding;
                final plotWidth = max(1.0, constraints.maxWidth - leftPad);
                return _CardTrendChart(
                  range: _range,
                  // 一屏能画几个点，就只查几个点
                  windowPoints: netTrendWindowCapacity(plotWidth),
                  currentNetCents: widget.currentNetCents,
                  masked: masked,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片的数据容器：窗口点数 N 由宽度算出，再按 N 反推查询起点。
/// 卡片常驻资产页、数据一变就会重查，所以只取一屏的量（20 年、
/// N=12 时实测：日 2.6ms、月 1.3ms、季 2.6ms、年 7.3ms；全量则要 27ms+）。
/// 窗口外的更早数据不进卡片，统一去全屏页横滑查看。
class _CardTrendChart extends StatefulWidget {
  const _CardTrendChart({
    required this.range,
    required this.windowPoints,
    required this.currentNetCents,
    required this.masked,
  });

  final NetTrendRange range;
  final int windowPoints;
  final int currentNetCents;
  final bool masked;

  @override
  State<_CardTrendChart> createState() => _CardTrendChartState();
}

class _CardTrendChartState extends State<_CardTrendChart> {
  late Stream<List<NetValuePoint>> _stream = _streamOf();

  Stream<List<NetValuePoint>> _streamOf() =>
      context.read<AssetProvider>().netHistoryStream(
        from: netTrendWindowFrom(
          range: widget.range,
          points: widget.windowPoints,
        ),
      );

  @override
  void didUpdateWidget(covariant _CardTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切档或屏幕宽度变了（旋转/分屏）才重查；窗口点数相同就复用
    if (oldWidget.range != widget.range ||
        oldWidget.windowPoints != widget.windowPoints) {
      _stream = _streamOf();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NetValuePoint>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // 历史点还没到：显示转圈而不是"没数据"的空态文案
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return NetTrendChart(
          range: widget.range,
          history: snapshot.data!,
          currentNetCents: widget.currentNetCents,
          masked: widget.masked,
        );
      },
    );
  }
}

/// 资产构成卡：未归档且计入总资产的账户按分类求和（复用统计页环形图组件）
class StructureCard extends StatefulWidget {
  const StructureCard({super.key});

  @override
  State<StructureCard> createState() => _StructureCardState();
}

class _StructureCardState extends State<StructureCard> {
  /// 流只建一次：在 build 里调 activeStream() 会每次重建都新建查询流，
  /// StreamBuilder 收到初始数据后重建→再新建流，无限循环拖死主线程
  late final Stream<List<Asset>> _assetsStream = context
      .read<AssetProvider>()
      .activeStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Asset>>(
      stream: _assetsStream,
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
          centerValue: masked
              ? '****'
              : MoneyUtil.centsToYuanGroupedTrimmed(total),
          centerValueColor: AppColors.primary,
          emptyText: '添加资产后查看构成',
        );
      },
    );
  }
}
