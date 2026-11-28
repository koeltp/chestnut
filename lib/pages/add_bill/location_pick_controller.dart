import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../services/amap_service.dart';

/// 列表条目（附近地点 / 搜索结果统一模型）
class LocationEntry {
  const LocationEntry({
    required this.title,
    this.subtitle = '',
    this.distance,
    this.location,
    this.fullAddress,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final int? distance;
  final Gcj02Point? location;

  /// 条目自带的完整地址（当前选择点的逆地理结果）；POI/搜索条目
  /// 通常缺省市，选中时在页面 _select 中现场逆地理补全
  final String? fullAddress;

  /// 高亮标红（首项"已保存的位置"）：提醒用户点它可原样保留旧位置
  final bool highlight;
}

/// 两点间粗略距离（米）：小范围选点场景平面近似足够。
/// 控制器（已加载点去重、条目距离补算）与页面（拖动判定）共用
double distanceMeters(Gcj02Point a, Gcj02Point b) {
  const kmPerDegLat = 111.0;
  final kmPerDegLng = 111.0 * cos(a.lat * pi / 180);
  final dLat = (a.lat - b.lat).abs() * kmPerDegLat;
  final dLng = (a.lng - b.lng).abs() * kmPerDegLng;
  return sqrt(dLat * dLat + dLng * dLng) * 1000;
}

/// 位置选点的数据控制器：附近列表加载与关键词搜索。
///
/// 从选点页剥离的数据链路：
/// - 附近模式：周边搜索接口（列表主体）+ 逆地理（并行补首项地址）；
/// - 搜索模式：输入提示接口，防抖 400ms；
/// - 竞态控制：请求代数制，发起新请求时自增，响应返回时代数不符
///   即为过期结果，丢弃——防止快速搜索/连续拖动时旧数据覆盖新数据。
/// 状态变化经 [ChangeNotifier] 通知页面刷新。
class LocationPickController extends ChangeNotifier {
  LocationPickController({
    required this.service,
    this.savedName,
    this.savedPoint,
  });

  final AmapService service;

  /// 编辑账单时的保存位置：与中心点相距很近（50m 内）时，列表首项
  /// 显示"已保存的位置"，点击可原样带回
  final String? savedName;
  final Gcj02Point? savedPoint;

  /// 列表数据；null = 首次定位中尚未加载
  List<LocationEntry>? entries;
  bool loading = false;
  String? error;

  /// 搜索关键词；非空为搜索模式，清空后回到附近列表
  String keyword = '';

  /// 当前地图中心（GCJ-02）：搜索时作就近参考，清空关键词后
  /// 回附近列表的加载点。由页面在移图/拖动结束时同步写入
  Gcj02Point? center;

  Timer? _debounce;
  Gcj02Point? _lastLoadedPoint;
  int _reqGen = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _disposed = true;
    super.dispose();
  }

  /// 搜索框变化：防抖 400ms 后请求输入提示；清空则回到附近列表
  void onSearchChanged(String value) {
    _debounce?.cancel();
    final kw = value.trim();
    if (kw.isEmpty) {
      keyword = '';
      notifyListeners();
      final c = center;
      if (c != null) loadNear(c);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      search(kw);
    });
  }

  /// 地图拖动/程序化移图结束：中心点变化时刷新附近列表。
  /// 搜索模式下不覆盖搜索结果；中心与已加载点一致时跳过重复请求
  void onCameraSettled(Gcj02Point center) {
    if (keyword.isNotEmpty) return;
    final loaded = _lastLoadedPoint;
    if (loaded != null && distanceMeters(center, loaded) < 1) return;
    loadNear(center);
  }

  /// 退出搜索模式（选中行政区条目飞往目标区域时调用），
  /// 附近列表由随后的 loadNear 重新加载
  void exitSearch() {
    if (keyword.isEmpty) return;
    keyword = '';
    notifyListeners();
  }

  /// 定位失败等非列表链路错误的写入入口：页面复用列表区错误态展示，
  /// 重试按钮按错误时的模式分流回加载/搜索/定位
  void reportError(String message) {
    if (_disposed) return;
    error = message;
    notifyListeners();
  }

  /// 加载中心点附近地点列表。
  /// 列表主体来自周边搜索接口（全量 POI、按距离排序）；逆地理仅并行
  /// 补充首项"当前选择点"的地址文本，失败时静默跳过不影响列表。
  Future<void> loadNear(Gcj02Point point) async {
    final gen = ++_reqGen;
    _lastLoadedPoint = point;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final regeoFuture = service
          .regeoDetail(point)
          .then<RegeoDetail?>((v) => v, onError: (Object _) => null);
      final results = await Future.wait([service.around(point), regeoFuture]);
      final pois = results[0] as List<PoiItem>;
      final detail = results[1] as RegeoDetail?;
      // 首项地址用结构化行政区划（省市区镇）而非 formatted 整串：
      // 针指在无店铺处时，高德会拿最近的 POI 名当锚点拼在末尾
      // （如"…新市镇晚安家居(新市街店)"），名不副实；adminPath
      // 只描述"针所在的位置"，与下方店铺条目形成"要店点店、
      // 要位置点首项"的清晰分工
      final address = detail == null
          ? ''
          : (detail.adminPath.isNotEmpty ? detail.adminPath : detail.formatted);
      // 代数不符：期间已发起更新的请求（继续拖动/切搜索），丢弃过期结果
      if (gen != _reqGen || _disposed) return;
      final saved = savedPoint;
      final atSaved =
          saved != null &&
          savedName != null &&
          distanceMeters(point, saved) < 50;
      final list = <LocationEntry>[
        if (atSaved)
          LocationEntry(
            title: savedName!,
            subtitle: '已保存的位置',
            location: saved,
            highlight: true,
          )
        else if (address.isNotEmpty)
          LocationEntry(
            title: address,
            subtitle: '当前选择点',
            location: point,
            // 结构化行政区划本身就是完整地址，选中时无需再补
            fullAddress: address,
          ),
        ...pois.map(
          (p) => LocationEntry(
            title: p.name,
            subtitle: p.address,
            // 接口未带距离时按坐标现算（输入提示类数据无 distance 字段）
            distance:
                p.distance ??
                (p.location != null
                    ? distanceMeters(p.location!, point).round()
                    : null),
            location: p.location,
          ),
        ),
      ];
      if (_disposed) return;
      entries = list;
      notifyListeners();
    } catch (e) {
      // 留日志便于连机排查；界面仍统一轻提示
      debugPrint('附近地点加载失败: $e');
      if (gen != _reqGen || _disposed) return;
      error = '加载失败，请重试';
      notifyListeners();
    } finally {
      if (gen == _reqGen && !_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// 关键词搜索（输入提示接口）
  Future<void> search(String kw) async {
    final gen = ++_reqGen;
    keyword = kw;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final tips = await service.inputTips(kw, center);
      // 代数不符：期间已切回附近列表或发起新搜索，丢弃过期结果
      if (gen != _reqGen || _disposed) return;
      entries = tips
          .map(
            (t) => LocationEntry(
              title: t.name,
              subtitle: t.address,
              location: t.location,
            ),
          )
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('地点搜索失败: $e');
      if (gen != _reqGen || _disposed) return;
      error = '搜索失败，请重试';
      notifyListeners();
    } finally {
      if (gen == _reqGen && !_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }
}
