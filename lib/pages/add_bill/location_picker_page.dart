import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../../services/amap_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/show_toast.dart';

/// 位置选择页（京东式"选点"）
///
/// 上半高德地图：中心固定大头针，拖动地图即改选中心点；
/// 下半当前中心附近地点列表；顶部支持关键词搜索。
/// 选中后把 [LocationSelection]（地名 + 坐标）返回给记一笔页。
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, this.initialName, this.initialPoint});

  /// 已保存的地名与坐标（编辑账单时传入）：
  /// 有坐标时地图直接回到老地点，列表首项显示"已保存的位置"
  final String? initialName;
  final Gcj02Point? initialPoint;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

/// 选点结果：地名 + 坐标 + 完整定位信息（行政区类地名无精确坐标，point 为 null）
///
/// [fullAddress] 为"省 市 区 街道 地点名"全量拼接，专供搜索字段
/// locationFull 写入；null = 无法补全（如"已保存的位置"），由记一笔
/// 页保留旧值兜底。location（显示用地名）始终只存 [name]，不受影响。
class LocationSelection {
  const LocationSelection({required this.name, this.point, this.fullAddress});

  final String name;
  final Gcj02Point? point;
  final String? fullAddress;
}

/// 列表条目（附近地点 / 搜索结果统一模型）
class _Entry {
  const _Entry({
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
  /// 通常缺省市，选中时在 _select 中现场逆地理补全
  final String? fullAddress;

  /// 高亮标红（首项"已保存的位置"）：提醒用户点它可原样保留旧位置
  final bool highlight;
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final _service = AmapService();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  AMapController? _mapController;

  /// 高德初始化只执行一次（didChangeDependencies 可能多次触发）
  bool _initializerRan = false;

  /// 列表数据；null = 首次定位中尚未加载
  List<_Entry>? _entries;
  bool _loading = false;
  String? _error;

  /// 当前地图中心（GCJ-02），搜索时作就近参考
  Gcj02Point? _center;

  /// 搜索关键词；非空为搜索模式，清空后回到附近列表
  String _keyword = '';
  Timer? _debounce;

  /// 系统实时定位在途标记：防止"回到当前位置"连点重复发起
  bool _locating = false;

  /// 保存位置的图钉图标（蓝色，代码绘制，避免依赖图片资源）
  BitmapDescriptor? _pinIcon;

  /// GPS 当前位置的小蓝点图标
  BitmapDescriptor? _dotIcon;

  /// 最近一次定位的真实坐标（GCJ-02），地图上以小蓝点标记
  Gcj02Point? _gpsPoint;

  /// 定位早于地图就绪时的待执行移动标记
  bool _pendingMove = false;

  /// 定位结果是否驱动地图移动：新记账=true（打开即定位到当前位置）；
  /// 编辑=false（地图停在保存位置，定位只为显示小蓝点），
  /// 点"回到当前位置"按钮后临时置 true
  bool _followLocation = false;

  /// 用户是否手动拖过地图：拖过之后定位结果不再拽动地图
  bool _userDragged = false;

  /// 最近一次程序化移图的目标点。onCameraMoveEnd 里与地图中心比对，
  /// 区分手势拖动与代码 moveCamera（原生对两种来源回调相同）——
  /// 中心与程序化目标不符即为用户拖动
  Gcj02Point? _lastProgrammaticTarget;

  /// 缓存的 Marker 对象。amap_map 按 marker id 做 diff，而 Marker 每次
  /// 构造都会生成新 id——若在 build 里反复新建，原生层会全删全建，
  /// 定位回调刷新时图标闪烁、气泡消失。必须复用同一对象。
  Marker? _savedMarker;
  Marker? _gpsMarker;

  /// 已加载过附近列表的中心点。程序化 moveCamera 结束同样会回调
  /// onCameraMoveEnd（原生不区分手势与代码移动），中心未变时跳过
  /// 重复请求，避免定位移图/回到保存点后再白发一次逆地理。
  Gcj02Point? _lastLoadedPoint;

  /// 请求代数：发起新请求时自增；响应返回时代数不符说明已有更新的
  /// 请求发出，丢弃过期结果，防止快速搜索/连续拖动时旧数据覆盖新数据
  int _reqGen = 0;

  @override
  void initState() {
    super.initState();
    // 有保存定位（编辑账单）：一打开就回到保存的位置，地图与列表直接到位；
    // 同时后台静默定位以显示当前定位精度（不移图，不抢保存位置）
    // 无保存定位（新记账）：定位当前位置
    final saved = widget.initialPoint;
    if (saved != null) {
      _moveTo(saved);
      _locateAndMove(follow: false);
    } else {
      _locateAndMove();
    }
    _makeIcons();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 高德隐私合规：SDK 要求创建地图/定位前完成授权配置。
    // init 内部会读取 MediaQuery，initState 阶段不允许依赖 InheritedWidget，
    // 必须放到 didChangeDependencies；标记防止依赖变化时重复初始化。
    if (!_initializerRan) {
      _initializerRan = true;
      AMapInitializer.init(
        context,
        apiKey: const AMapApiKey(androidKey: AmapService.androidMapKey),
      );
      AMapInitializer.updatePrivacyAgree(
        const AMapPrivacyStatement(
          hasContains: true,
          hasShow: true,
          hasAgree: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 生成图钉图标（经典 📍 造型：圆头 + 白孔 + 尖底）。
  /// amap_map 的 defaultMarker 渲染样式不可控，改用离屏 Canvas 绘制位图，
  /// fromBytes 交给原生 Marker 层，无需打包图片资源。
  /// [color] 区分语义：保存位置用蓝、中心选点用红。
  static Future<BitmapDescriptor> _renderPin(Color color) async {
    const w = 96, h = 128;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(w / 2, 44);
    final paint = ui.Paint()..color = color;
    // 头部圆
    canvas.drawCircle(center, 32, paint);
    // 尖底三角（底边与圆交叠，避免接缝）
    final path = ui.Path()
      ..moveTo(w / 2 - 21, 66)
      ..lineTo(w / 2 + 21, 66)
      ..lineTo(w / 2, 124)
      ..close();
    canvas.drawPath(path, paint);
    // 白色内孔
    canvas.drawCircle(center, 13, ui.Paint()..color = Colors.white);
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  /// GPS 当前位置小蓝点（白描边圆点，京东式）
  static Future<BitmapDescriptor> _renderDot() async {
    const s = 48;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const c = Offset(s / 2, s / 2);
    // 白色外圈充当描边，内层蓝色实心圆
    canvas.drawCircle(c, 18, ui.Paint()..color = Colors.white);
    canvas.drawCircle(c, 13, ui.Paint()..color = AppColors.primary);
    final image = await recorder.endRecording().toImage(s, s);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<void> _makeIcons() async {
    final pin = await _renderPin(AppColors.primary);
    final dot = await _renderDot();
    if (!mounted) return;
    setState(() {
      _pinIcon = pin;
      _dotIcon = dot;
      _ensureSavedMarker();
      _updateGpsMarker();
    });
  }

  /// 保存位置蓝图钉：位置固定（widget.initialPoint），图标就绪后创建一次。
  /// anchor 对准针尖（位图 96×128 中尖底位于 y=124）
  void _ensureSavedMarker() {
    final saved = widget.initialPoint;
    if (saved == null || _pinIcon == null) return;
    _savedMarker ??= Marker(
      position: LatLng(saved.lat, saved.lng),
      icon: _pinIcon!,
      anchor: const Offset(0.5, 124 / 128),
      infoWindow: InfoWindow(
        title: '上次保存的位置',
        snippet: widget.initialName ?? '',
      ),
    );
  }

  /// GPS 位置小蓝点：位置变化时重建（此时本来就需要更新原生标记）。
  /// 圆形图标 anchor 取中心 (0.5, 0.5)，默认 (0.5, 1.0) 会让圆点
  /// 悬浮在实际位置上方半个图标高度
  void _updateGpsMarker() {
    final gps = _gpsPoint;
    if (gps == null || _dotIcon == null) return;
    _gpsMarker = Marker(
      position: LatLng(gps.lat, gps.lng),
      icon: _dotIcon!,
      anchor: const Offset(0.5, 0.5),
    );
  }

  /// 检查权限后发起定位（系统缓存先行 + 系统实时定位主源）。
  /// [follow] 为 true 时定位结果驱动地图移动；false 只显示小蓝点。
  Future<void> _locateAndMove({bool follow = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _toast('请先开启系统定位服务');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('未授予定位权限，可在系统设置中开启');
        return;
      }
    } catch (_) {
      _toast('定位失败，请稍后重试');
      return;
    }
    _followLocation = follow;
    // 京东式"先显示、后精化"：先读系统最近缓存位置（毫秒级返回），
    // 立即转 GCJ-02 上图，页面马上可用。缓存超过 10 分钟视为过期
    //（避免跨城旧缓存误导读到错误城市）
    try {
      final last = await Geolocator.getLastKnownPosition();
      final age = last == null
          ? null
          : DateTime.now().difference(last.timestamp);
      if (last != null && age != null && age < const Duration(minutes: 10)) {
        debugPrint('[定位] 系统缓存位置（${age.inSeconds}秒前）');
        _applyLocation(
          Wgs84ToGcj02.convert(last.latitude, last.longitude),
          follow: follow,
        );
      }
    } catch (_) {
      // 缓存拿不到无所谓，实时定位还在后面
    }
    if (_locating) return;
    _locateBySystem();
  }

  /// 系统实时定位主源。forceLocationManager 强走 Android LocationManager
  ///（厂商融合定位服务，vivo 等无 GMS 设备回调可靠）。
  /// 高德定位 SDK 已移除：其网络定位库在无 GMS 设备上 Wi-Fi 指纹未命中
  /// 时会静默丢回调（连失败回调都没有），是"打开就超时"的根源。
  /// 系统坐标为 WGS-84，转 GCJ-02 后使用。
  Future<void> _locateBySystem() async {
    _locating = true;
    try {
      debugPrint('[定位] 启动系统实时定位');
      final pos = await Geolocator.getCurrentPosition(
        // AndroidSettings 非 const 构造
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
          forceLocationManager: true,
        ),
      );
      debugPrint('[定位] 系统定位成功: ${pos.latitude}, ${pos.longitude}');
      if (!mounted) return;
      _applyLocation(
        Wgs84ToGcj02.convert(pos.latitude, pos.longitude),
        follow: _followLocation,
      );
    } catch (e) {
      debugPrint('[定位] 系统定位失败: $e');
      if (!mounted) return;
      // 缓存位置已经上图过：不算失败，仅提示未刷新
      if (_gpsPoint != null) {
        _toast('定位未刷新，可稍后重试');
      } else {
        setState(() => _error = '定位失败，请重试');
      }
    } finally {
      _locating = false;
    }
  }

  /// 应用一次定位结果：记录真实位置并更新小蓝点。
  /// [follow] 为 true 且用户未拖动地图时把地图带到该位置——缓存位置
  /// 只是开场占位（可能过时/漂移），实时定位到达后纠正红蓝分离；
  /// 用户一旦手动拖过地图就不再拽回。系统定位为单次回调，不会反复移图。
  void _applyLocation(Gcj02Point point, {bool follow = false}) {
    _gpsPoint = point;
    _updateGpsMarker();
    if (follow && !_userDragged) {
      _moveTo(point);
    }
    if (mounted) setState(() {});
  }

  /// 地图移动到指定点并加载附近列表。
  /// 首次打开时定位回调可能早于地图创建完成（onMapCreated），
  /// 此时 moveCamera 会被吞掉——记下待移动状态，地图就绪后补飞。
  void _moveTo(Gcj02Point point) {
    _center = point;
    _lastProgrammaticTarget = point;
    final controller = _mapController;
    if (controller == null) {
      _pendingMove = true;
    } else {
      _pendingMove = false;
      controller.moveCamera(
        CameraUpdate.newLatLngZoom(LatLng(point.lat, point.lng), 17.5),
      );
    }
    _loadNear(point);
  }

  /// 拖动地图结束：加载新中心点附近列表（搜索模式下不覆盖搜索结果）。
  /// 程序化 moveCamera 结束同样回调本方法，中心与已加载点一致时跳过
  void _onCameraMoveEnd(CameraPosition position) {
    final target = position.target;
    _center = Gcj02Point(lat: target.latitude, lng: target.longitude);
    // 中心与最近一次程序化移图目标不符：用户手势拖动，此后定位不拽图
    final prog = _lastProgrammaticTarget;
    if (prog == null || _distanceMeters(_center!, prog) > 1) {
      _userDragged = true;
    }
    if (_keyword.isNotEmpty) return;
    final loaded = _lastLoadedPoint;
    if (loaded != null && _distanceMeters(_center!, loaded) < 1) return;
    _loadNear(_center!);
  }

  /// 加载中心点附近地点列表。
  /// 列表主体来自周边搜索接口（全量 POI、按距离排序）；逆地理仅并行
  /// 补充首项"当前选择点"的地址文本，失败时静默跳过不影响列表。
  Future<void> _loadNear(Gcj02Point point) async {
    final gen = ++_reqGen;
    _lastLoadedPoint = point;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final regeoFuture = _service
          .regeoDetail(point)
          .then<RegeoDetail?>((v) => v, onError: (Object _) => null);
      final results = await Future.wait([_service.around(point), regeoFuture]);
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
      if (gen != _reqGen || !mounted) return;
      // 中心点与已保存位置相距很近（50m 内）时，首项显示"已保存的位置"，
      // 点击可原样带回；用户拖走地图后恢复显示中心点地址
      final saved = widget.initialPoint;
      final savedName = widget.initialName;
      final atSaved =
          saved != null &&
          savedName != null &&
          _distanceMeters(point, saved) < 50;
      final entries = <_Entry>[
        if (atSaved)
          _Entry(
            title: savedName,
            subtitle: '已保存的位置',
            location: saved,
            highlight: true,
          )
        else if (address.isNotEmpty)
          _Entry(
            title: address,
            subtitle: '当前选择点',
            location: point,
            // 结构化行政区划本身就是完整地址，选中时无需再补
            fullAddress: address,
          ),
        ...pois.map(
          (p) => _Entry(
            title: p.name,
            subtitle: p.address,
            // 接口未带距离时按坐标现算（输入提示类数据无 distance 字段）
            distance:
                p.distance ??
                (p.location != null
                    ? _distanceMeters(p.location!, point).round()
                    : null),
            location: p.location,
          ),
        ),
      ];
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      // 留日志便于连机排查；界面仍统一轻提示
      debugPrint('附近地点加载失败: $e');
      if (gen != _reqGen || !mounted) return;
      setState(() => _error = '加载失败，请重试');
    } finally {
      if (gen == _reqGen && mounted) setState(() => _loading = false);
    }
  }

  /// 搜索框变化：防抖 400ms 后请求输入提示
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final keyword = value.trim();
    if (keyword.isEmpty) {
      setState(() => _keyword = '');
      if (_center != null) _loadNear(_center!);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(keyword);
    });
  }

  Future<void> _search(String keyword) async {
    final gen = ++_reqGen;
    setState(() {
      _keyword = keyword;
      _loading = true;
      _error = null;
    });
    try {
      final tips = await _service.inputTips(keyword, _center);
      // 代数不符：期间已切回附近列表或发起新搜索，丢弃过期结果
      if (gen != _reqGen || !mounted) return;
      setState(() {
        _entries = tips
            .map(
              (t) => _Entry(
                title: t.name,
                subtitle: t.address,
                location: t.location,
              ),
            )
            .toList();
      });
    } catch (e) {
      debugPrint('地点搜索失败: $e');
      if (gen != _reqGen || !mounted) return;
      setState(() => _error = '搜索失败，请重试');
    } finally {
      if (gen == _reqGen && mounted) setState(() => _loading = false);
    }
  }

  /// 创建自定义位置：搜索结果里没有想要的地点时，用输入的关键词
  /// 命名当前红针位置（地图中心）。坐标取当前中心（编辑账单时地图
  /// 仍可飞回），fullAddress 现场逆地理补全（失败静默降级为 null，
  /// 由记一笔页兜底），不阻塞返回
  Future<void> _createCustom(String name) async {
    final point = _center;
    if (point == null) {
      _toast('地图尚未就绪，请稍后再试');
      return;
    }
    var full = '';
    try {
      final detail = await _service
          .regeoDetail(point)
          .timeout(const Duration(seconds: 5));
      // 与点店分支同款拼接：行政区划为底，追加点名（contains 查重防
      // "菜市场 菜市场"式重复）。fullAddress 缺名字会导致详情显示
      // 残缺、搜索（匹配 locationFull）搜不到自定义名
      final base = detail.adminPath.isNotEmpty
          ? detail.adminPath
          : detail.formatted;
      if (base.isNotEmpty) {
        full = base.contains(name) ? base : '$base $name';
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(
      LocationSelection(
        name: name,
        point: point,
        fullAddress: full.isEmpty ? null : full,
      ),
    );
  }

  /// “创建新的位置”行（钱迹式）：搜索结果末尾的自定义入口
  Widget _buildCreateItem() {
    return InkWell(
      onTap: () => _createCustom(_keyword),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '没有找到你的位置？',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              '创建新的位置：$_keyword',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 选中地点的处理：
  /// 有坐标（店铺等精确地点）→ 直接带回地名与坐标；
  /// 无坐标（行政区类，如"四川省成都市"）→ 当作导航入口，地理编码
  /// 拿坐标后把地图飞过去、附近列表联动切换到该区域（异地补记场景：
  /// 搜城市名 → 飞过去 → 再搜店选店），不直接关闭页面
  Future<void> _select(_Entry entry) async {
    final point = entry.location;
    if (point != null) {
      // 完整定位信息：条目自带（当前选择点逆地理）优先；POI/搜索条目
      // 现场逆地理补全——优先"省市区街道"结构化拼接（纯行政区划，
      // 天然不含地标名），四段全空才退回 formatted 整串；追加点名前
      // 先查重（高德逆地理串末尾常自带地标，如"…紫云阁酒店 紫云阁
      // 酒店"），重叠时不再追加。超时/失败静默降级（fullAddress 为空
      // 由记一笔页兜底），不阻塞选点
      var full = entry.fullAddress;
      if (full == null) {
        try {
          final detail = await _service
              .regeoDetail(point)
              .timeout(const Duration(seconds: 5));
          final base = detail.adminPath.isNotEmpty
              ? detail.adminPath
              : detail.formatted;
          if (base.isNotEmpty) {
            full = base.contains(entry.title) ? base : '$base ${entry.title}';
          }
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        LocationSelection(name: entry.title, point: point, fullAddress: full),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final geo = await _service.geocode(entry.title);
      if (!mounted) return;
      if (geo == null) {
        _toast('未能定位到该区域');
        return;
      }
      // 退出搜索模式并清空输入，附近列表由 _moveTo 重新加载
      _keyword = '';
      _searchController.clear();
      _moveTo(geo);
    } catch (e) {
      debugPrint('行政区定位失败: $e');
      if (mounted) _toast('未能定位到该区域');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 两点间粗略距离（米）：小范围选点场景平面近似足够
  double _distanceMeters(Gcj02Point a, Gcj02Point b) {
    const kmPerDegLat = 111.0;
    final kmPerDegLng = 111.0 * cos(a.lat * pi / 180);
    final dLat = (a.lat - b.lat).abs() * kmPerDegLat;
    final dLng = (a.lng - b.lng).abs() * kmPerDegLng;
    return sqrt(dLat * dLat + dLng * dLng) * 1000;
  }

  void _toast(String message) {
    showAppToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildSearchBar(),
            Expanded(flex: 5, child: _buildMapArea()),
            // 编辑模式：有保存位置时单独一行，点击地图回到当时地点
            if (_hasSavedLocation) ...[
              _buildSavedBar(),
              const Divider(
                height: 1,
                thickness: 0.5,
                color: Color(0xFFEEEEEE),
              ),
            ],
            Expanded(flex: 5, child: _buildListArea()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Expanded(
          child: Text(
            '选择位置',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _buildSearchBar() {
    // 通栏搜索框比分类页（132 宽小框）的 38 更高：超宽框同高会视觉显扁，
    // 44 高与京东选点页一致，长宽比更协调
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '搜索小区、写字楼、店铺',
            hintStyle: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 12, right: 6),
              child: Icon(
                Icons.search,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
            // minHeight 与框同高，保证图标垂直居中
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 44,
            ),
            filled: true,
            fillColor: AppColors.fill,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  /// 编辑模式且账单带有保存的地名与坐标时，地图下方显示"上次保存位置"行
  bool get _hasSavedLocation =>
      (widget.initialName?.isNotEmpty ?? false) && widget.initialPoint != null;

  /// "上次保存的位置"横条：整行可点，点击后地图回到当时的地点
  Widget _buildSavedBar() {
    return InkWell(
      onTap: () => _moveTo(widget.initialPoint!),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppColors.primary.withValues(alpha: 0.06),
        child: Row(
          children: [
            const Icon(Icons.place, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '上次保存：${widget.initialName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Text(
              '回到这里',
              style: TextStyle(fontSize: 13, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapArea() {
    // 初始位置：优先当前中心，默认天安门，定位成功后 moveCamera 纠正
    final initial =
        _center ?? const Gcj02Point(lat: 39.909187, lng: 116.397451);
    // 标记对象由 _ensureSavedMarker / _updateGpsMarker 缓存维护，
    // build 只复用——新建对象会导致原生层按 id 全删全建而闪烁
    final markers = <Marker>{?_savedMarker, ?_gpsMarker};
    final map = AMapWidget(
      markers: markers,
      initialCameraPosition: CameraPosition(
        target: LatLng(initial.lat, initial.lng),
        zoom: 17.5,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        // 地图就绪晚于定位回调时，补执行被跳过的移动
        if (_pendingMove) {
          _pendingMove = false;
          final c = _center;
          if (c != null) {
            controller.moveCamera(
              CameraUpdate.newLatLngZoom(LatLng(c.lat, c.lng), 17.5),
            );
          }
        }
      },
      onCameraMoveEnd: _onCameraMoveEnd,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        map,
        // 中心固定选点针：红色大图钉（京东式），拖动地图改选位置；
        // 与蓝图钉（保存位置）、蓝点（GPS 位置）语义分离
        IgnorePointer(
          child: Transform.translate(
            offset: const Offset(0, -22),
            child: const Icon(Icons.place, size: 44, color: Color(0xFFE5484D)),
          ),
        ),
        // 右下角"回到当前位置"
        Positioned(
          right: 12,
          bottom: 16,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            elevation: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              // 已有定位结果时立即把地图飞过去，不等新一轮定位——
              // "回到当前位置"的语义就是回到当前已知位置；
              // 后台同时刷新定位，拿到更准的结果后微调一次
              onTap: () {
                final gps = _gpsPoint;
                if (gps != null) {
                  _moveTo(gps);
                  _locateAndMove();
                } else {
                  _toast('正在定位…');
                  _locateAndMove();
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.my_location,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListArea() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            TextButton(
              onPressed: () {
                if (_keyword.isNotEmpty) {
                  _search(_keyword);
                } else if (_center != null) {
                  _loadNear(_center!);
                } else {
                  // 还没定位成功过：重试即重新定位
                  _locateAndMove();
                }
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }
    if (entries.isEmpty) {
      // 搜索无结果时"创建新的位置"是唯一出路，空态也要提供
      if (_keyword.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Text(
              '没有找到相关地点',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _buildCreateItem(),
          ],
        );
      }
      return Center(
        child: Text(
          '附近没有找到地点',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    return _buildListBody();
  }

  /// 列表区整体（顶部刷新进度条 + 条目列表）
  Widget _buildListBody() {
    final entries = _entries!;
    // 搜索模式在结果末尾追加"创建新的位置"入口（关键词即位置名）
    final showCreate = _keyword.isNotEmpty;
    return Column(
      children: [
        // 刷新中在列表顶部显示细进度条，不遮盖已有内容
        if (_loading)
          const LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.primary,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length + (showCreate ? 1 : 0),
            itemBuilder: (context, index) {
              if (showCreate && index == entries.length) {
                return _buildCreateItem();
              }
              return _buildEntryItem(entries[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEntryItem(_Entry entry) {
    return InkWell(
      onTap: () => _select(entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      // "已保存的位置"条目整体标红，突出"点它保留旧位置"
                      color: entry.highlight
                          ? AppColors.expense
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: entry.highlight
                            ? AppColors.expense
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.distance != null) ...[
              const SizedBox(width: 8),
              Text(
                _distanceText(entry.distance!),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 距离显示：1km 内显示米，超过显示公里（保留 1 位小数）
  String _distanceText(int meters) {
    if (meters < 1000) return '$meters米';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
}
