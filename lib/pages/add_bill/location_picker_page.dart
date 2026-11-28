import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../../services/amap_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/show_toast.dart';
import 'location_pick_controller.dart';
import 'map_marker_icons.dart';
import 'system_locator.dart';

/// 位置选择页（京东式"选点"）
///
/// 上半高德地图：中心固定大头针，拖动地图即改选中心点；
/// 下半当前中心附近地点列表；顶部支持关键词搜索。
/// 选中后把 [LocationSelection]（地名 + 坐标）返回给记一笔页。
///
/// 职责分工：本页只保留地图交互状态机（移图/拖动判定/标记缓存）与
/// UI 构建；附近列表与搜索的数据链路在 [LocationPickController]，
/// 系统定位细节在 [SystemLocator]，标记图标绘制在 [MapMarkerIcons]。
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

class _LocationPickerPageState extends State<LocationPickerPage> {
  final _service = AmapService();
  final _locator = SystemLocator();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  late final LocationPickController _controller;

  AMapController? _mapController;

  /// 高德初始化只执行一次（didChangeDependencies 可能多次触发）
  bool _initializerRan = false;

  /// 当前地图中心（GCJ-02）：地图交互状态机的基准点，同步写入控制器
  /// 供搜索就近参考；程序化移图与用户拖动都会更新
  Gcj02Point? _center;

  /// 系统实时定位在途标记：防止"回到当前位置"连点重复发起
  bool _locating = false;

  /// 行政区条目地理编码飞行中：列表顶部进度条与控制器加载态共用展示
  bool _geocoding = false;

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

  @override
  void initState() {
    super.initState();
    // 控制器必须先于一切异步分支创建：权限被拒等早退路径不触碰控制器，
    // 若延迟到首次使用才初始化，dispose 时会抛 LateInitializationError
    _controller = LocationPickController(
      service: _service,
      savedName: widget.initialName,
      savedPoint: widget.initialPoint,
    );
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
    // 高德 SDK 初始化：隐私合规声明已在启动门（main.dart）用户同意后统一设置，
    // 此处只需注册 Key。init 内部会读取 MediaQuery，不能放 initState，
    // 必须放到 didChangeDependencies；标记防止依赖变化时重复初始化。
    if (!_initializerRan) {
      _initializerRan = true;
      AMapInitializer.init(
        context,
        // androidMapKey 是运行时 getter（按构建模式切 Key），无法 const
        apiKey: AMapApiKey(androidKey: AmapService.androidMapKey),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _makeIcons() async {
    final pin = await MapMarkerIcons.pin(AppColors.primary);
    final dot = await MapMarkerIcons.dot();
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
    final denial = await _locator.checkPermission();
    if (!mounted) return;
    if (denial != null) {
      _toast(denial);
      return;
    }
    _followLocation = follow;
    // 京东式"先显示、后精化"：先读系统最近缓存位置（毫秒级返回）立即
    // 上图，页面马上可用；新鲜期与坐标转换都在 SystemLocator 内
    final cache = await _locator.freshLastKnown();
    if (cache != null) {
      _applyLocation(cache, follow: follow);
    }
    if (_locating) return;
    // 后台启动实时定位，结果经回调回到本页，此处不等待
    unawaited(_locateBySystem());
  }

  /// 系统实时定位：结果经 _applyLocation 回到本页。失败时若缓存位置
  /// 已上图过则不算失败（仅提示未刷新），否则复用列表区错误态展示
  Future<void> _locateBySystem() async {
    _locating = true;
    try {
      final point = await _locator.locate();
      if (!mounted) return;
      _applyLocation(point, follow: _followLocation);
    } catch (e) {
      debugPrint('[定位] 系统定位失败: $e');
      if (!mounted) return;
      if (_gpsPoint != null) {
        _toast('定位未刷新，可稍后重试');
      } else {
        _controller.reportError('定位失败，请重试');
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
    _controller.center = point;
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
    _controller.loadNear(point);
  }

  /// 拖动地图结束：加载新中心点附近列表（搜索模式下不覆盖搜索结果）。
  /// 程序化 moveCamera 结束同样回调本方法，中心与已加载点一致时跳过
  void _onCameraMoveEnd(CameraPosition position) {
    final target = position.target;
    _center = Gcj02Point(lat: target.latitude, lng: target.longitude);
    _controller.center = _center;
    // 中心与最近一次程序化移图目标不符：用户手势拖动，此后定位不拽图
    final prog = _lastProgrammaticTarget;
    if (prog == null || distanceMeters(_center!, prog) > 1) {
      _userDragged = true;
    }
    _controller.onCameraSettled(_center!);
  }

  /// 完整定位信息补全（点选与自定义创建共用）：
  /// 优先"省市区街道"结构化拼接（纯行政区划，天然不含地标名），四段
  /// 全空才退回 formatted 整串；追加点名前先查重（高德逆地理串末尾常
  /// 自带地标，如"…紫云阁酒店 紫云阁酒店"），重叠时不再追加。
  /// 超时/失败静默降级（返回 null 由记一笔页兜底），不阻塞选点。
  /// [existing] 非空（当前选择点条目自带完整地址）直接沿用不再请求
  Future<String?> _resolveFullAddress(
    Gcj02Point point,
    String name, {
    String? existing,
  }) async {
    if (existing != null) return existing;
    try {
      final detail = await _service
          .regeoDetail(point)
          .timeout(const Duration(seconds: 5));
      final base = detail.adminPath.isNotEmpty
          ? detail.adminPath
          : detail.formatted;
      if (base.isNotEmpty) {
        return base.contains(name) ? base : '$base $name';
      }
    } catch (_) {}
    return null;
  }

  /// 创建自定义位置：搜索结果里没有想要的地点时，用输入的关键词
  /// 命名当前红针位置（地图中心）。坐标取当前中心（编辑账单时地图
  /// 仍可飞回），fullAddress 现场逆地理补全，不阻塞返回
  Future<void> _createCustom(String name) async {
    final point = _center;
    if (point == null) {
      _toast('地图尚未就绪，请稍后再试');
      return;
    }
    final full = await _resolveFullAddress(point, name);
    if (!mounted) return;
    Navigator.of(context).pop(
      LocationSelection(name: name, point: point, fullAddress: full),
    );
  }

  /// 选中地点的处理：
  /// 有坐标（店铺等精确地点）→ 直接带回地名与坐标；
  /// 无坐标（行政区类，如"四川省成都市"）→ 当作导航入口，地理编码
  /// 拿坐标后把地图飞过去、附近列表联动切换到该区域（异地补记场景：
  /// 搜城市名 → 飞过去 → 再搜店选店），不直接关闭页面
  Future<void> _select(LocationEntry entry) async {
    final point = entry.location;
    if (point != null) {
      final full = await _resolveFullAddress(
        point,
        entry.title,
        existing: entry.fullAddress,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        LocationSelection(name: entry.title, point: point, fullAddress: full),
      );
      return;
    }
    setState(() => _geocoding = true);
    try {
      final geo = await _service.geocode(entry.title);
      if (!mounted) return;
      if (geo == null) {
        _toast('未能定位到该区域');
        return;
      }
      // 退出搜索模式并清空输入，附近列表由 _moveTo 重新加载
      _controller.exitSearch();
      _searchController.clear();
      _moveTo(geo);
    } catch (e) {
      debugPrint('行政区定位失败: $e');
      if (mounted) _toast('未能定位到该区域');
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
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
          onChanged: _controller.onSearchChanged,
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

  /// 列表区：数据链路状态（条目/加载/错误/搜索模式）在控制器，
  /// 经 ListenableBuilder 订阅刷新
  Widget _buildListArea() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildListContent(),
    );
  }

  Widget _buildListContent() {
    final error = _controller.error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            TextButton(
              onPressed: () {
                if (_controller.keyword.isNotEmpty) {
                  _controller.search(_controller.keyword);
                } else if (_center != null) {
                  _controller.loadNear(_center!);
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
    final entries = _controller.entries;
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
      if (_controller.keyword.isNotEmpty) {
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
      return const Center(
        child: Text(
          '附近没有找到地点',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    // 搜索模式在结果末尾追加"创建新的位置"入口（关键词即位置名）
    final showCreate = _controller.keyword.isNotEmpty;
    // 刷新中在列表顶部显示细进度条，不遮盖已有内容；
    // 行政区地理编码飞行中同样显示（列表内容保持不塌陷）
    final loading = _controller.loading || _geocoding;
    return Column(
      children: [
        if (loading)
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

  /// "创建新的位置"行（钱迹式）：搜索结果末尾的自定义入口
  Widget _buildCreateItem() {
    final keyword = _controller.keyword;
    return InkWell(
      onTap: () => _createCustom(keyword),
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
              '创建新的位置：$keyword',
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

  Widget _buildEntryItem(LocationEntry entry) {
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
