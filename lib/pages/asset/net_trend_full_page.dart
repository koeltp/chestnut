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
  /// 全屏默认「全部」：横屏宽幅 + 90 点窗口才有历史可拖动
  NetTrendRange _range = NetTrendRange.all;

  /// 每档的可视窗口点数：日 90 天、月 24 个月、年 8 年、全部 90 天；
  /// 窗口外的历史靠单指横滑平移查看
  int get _windowSize => switch (_range) {
    NetTrendRange.day => 90,
    NetTrendRange.month => 24,
    NetTrendRange.year => 8,
    NetTrendRange.all => 90,
  };

  /// 历史流按档位限查、且只在初始化与切档时重建：
  /// 日取近 1 年、月取近 3 年、年取近 12 年、全部取全量，
  /// 都比可视窗口长，横滑才有更早的数据可看
  late Stream<List<NetValuePoint>> _netStream = _streamOf(_range);

  Stream<List<NetValuePoint>> _streamOf(NetTrendRange range) {
    final now = DateTime.now();
    final from = switch (range) {
      NetTrendRange.day => now.subtract(const Duration(days: 364)),
      NetTrendRange.month => DateTime(now.year, now.month - 35, 1),
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
                    panWindow: _windowSize,
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
