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
/// 四档粒度切换（日/月/年/全部），无数据点时才显示空态；
/// 单点画居中孤点，两点起连线成"势"。卡片内固定铺满不滚动，
/// 看历史细节点右上角放大进全屏页。
class NetTrendCard extends StatefulWidget {
  const NetTrendCard({super.key, required this.currentNetCents});

  final int currentNetCents;

  @override
  State<NetTrendCard> createState() => _NetTrendCardState();
}

class _NetTrendCardState extends State<NetTrendCard> {
  /// 默认"日"档：首屏看最近 15 天，其余档位用户主动切换
  NetTrendRange _range = NetTrendRange.day;

  /// 历史流按档位限查、且只订阅一次：日=15 天、月=12 个月、年=12 年、
  /// 全部=全量。build 里新建流会让每次重建都重跑一次查询，历史多时
  /// 会把主线程拖死（实测 4000+ 行会触发输入超时 ANR）
  late Stream<List<NetValuePoint>> _netStream = _streamOf(_range);

  /// 当前档位需要的起点：只取显示的窗口，多一天都不用
  Stream<List<NetValuePoint>> _streamOf(NetTrendRange range) {
    final now = DateTime.now();
    final from = switch (range) {
      NetTrendRange.day => now.subtract(const Duration(days: 14)),
      NetTrendRange.month => DateTime(now.year, now.month - 11, 1),
      NetTrendRange.year => DateTime(now.year - 11, 1, 1),
      NetTrendRange.all => null,
    };
    return context.read<AssetProvider>().netHistoryStream(from: from);
  }

  void _selectRange(NetTrendRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _netStream = _streamOf(range);
    });
  }

  /// 放大：进横屏全屏页，默认全部档，单指横滑看历史
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
    return StreamBuilder<List<NetValuePoint>>(
      stream: _netStream,
      builder: (context, snapshot) {
        final history = snapshot.data ?? const <NetValuePoint>[];
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
                // 历史点还没到：显示转圈而不是"没数据"的空态文案
                child: snapshot.hasData
                    ? NetTrendChart(
                        range: _range,
                        history: history,
                        currentNetCents: widget.currentNetCents,
                        masked: masked,
                      )
                    : const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
              ),
            ],
          ),
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
