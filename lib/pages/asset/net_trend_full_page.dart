import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/asset_repository.dart';
import '../../providers/asset_provider.dart';
import '../../theme/app_colors.dart';
import 'net_trend_chart.dart';
import 'net_trend_data.dart';

/// 净值走势全屏页：横屏占满一屏看曲线，单指左右拖动翻看历史，
/// 点按曲线上任意位置看当日净值。
class NetTrendFullPage extends StatefulWidget {
  const NetTrendFullPage({super.key, required this.currentNetCents});

  final int currentNetCents;

  @override
  State<NetTrendFullPage> createState() => _NetTrendFullPageState();
}

class _NetTrendFullPageState extends State<NetTrendFullPage> {
  /// 全屏默认「季」：横屏宽幅 + 宽窗口才有历史可拖动
  NetTrendRange _range = NetTrendRange.quarter;

  /// 历史流四档共用，全程只订阅一次。
  ///
  /// 档位只决定聚合粒度，不决定"能看多远"：可视窗口由图表按绘图区
  /// 宽度 ÷ 20dp 反推，更早的数据靠单指横滑到达，左边界永远是数据
  /// 起点。20 年（7252 行）实测：全量首帧约 30ms、四档聚合 ≤10ms，
  /// 不需要按档位限查——限查只会让"滑不到最早"看起来像 bug。
  late final Stream<List<NetValuePoint>> _netStream = context
      .read<AssetProvider>()
      .netHistoryStream();

  void _selectRange(NetTrendRange range) {
    if (range == _range) return;
    // 数据流四档共用，切档不重查，只换聚合粒度与标签格式
    setState(() => _range = range);
  }

  @override
  void initState() {
    super.initState();
    // 全屏看走势统一横屏：竖屏上下大量留白，横屏才看得清曲线细节
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // 退出恢复全局竖屏锁定，避免回到上个页面时横屏残留
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final masked = context.watch<AssetProvider>().masked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('净值走势'),
        // 档位切换放标题行右侧，横屏也能一眼点到
        actions: [
          Center(
            child: NetTrendRangeSwitch(value: _range, onChanged: _selectRange),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<List<NetValuePoint>>(
        stream: _netStream,
        builder: (context, snapshot) {
          final history = snapshot.data ?? const <NetValuePoint>[];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: NetTrendChart(
                    range: _range,
                    history: history,
                    currentNetCents: widget.currentNetCents,
                    masked: masked,
                    pannable: true,
                  ),
                ),
                // 四个档位都按窗口横滑，历史不足一个窗口时自然拖不动
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '单指左右拖动查看历史 · 点按查看详情',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
