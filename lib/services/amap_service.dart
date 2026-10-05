import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 逆地理结构化结果：formatted 整串 + 省市区街道独立字段
class RegeoDetail {
  const RegeoDetail({
    required this.formatted,
    required this.province,
    required this.city,
    required this.district,
    required this.township,
  });

  /// 高德 formatted_address 整串（末尾常自带地标名，拼接 POI 名会重复，
  /// 仅作结构化字段缺失时的兜底）
  final String formatted;
  final String province;
  final String city;
  final String district;

  /// 乡镇/街道级（个别地区可能为空）
  final String township;

  /// "省+市+区+街道"逐级拼接：跳过空段与重复段（直辖市 province==city）。
  /// 纯行政区划不含地标名，作为完整定位信息的前缀永不与 POI 名重复
  String get adminPath {
    final parts = <String>[];
    for (final s in [province, city, district, township]) {
      if (s.isEmpty || parts.contains(s)) continue;
      parts.add(s);
    }
    return parts.join();
  }
}

/// 高德 Web 服务 API 封装（逆地理 + 输入提示）
///
/// 仅通过 HTTP 接口查询"坐标 → 附近地点"与"关键词 → 地点提示"，
/// 不依赖任何高德原生 SDK。[_webKey] 必须是高德控制台"Web服务"类型的
/// Key，与地图 SDK 使用的 Android 平台 Key 互不通用。
class AmapService {
  AmapService();

  /// Web 服务 Key（控制台应用：chestnut_web）
  static const String _webKey = '81ba570c708b2486912fc116697cb8c4';

  /// Android 平台 Key（地图 SDK 鉴权用，经 AMapInitializer 传入）
  static const String androidMapKey = 'c547548d14c20b2111af15003717c5bf';

  static const String _baseUrl = 'https://restapi.amap.com/v3';

  /// 上次请求时刻：个人 Key 全局 QPS=3，客户端节流防止拖动地图时
  /// 连续触发逆地理被限流（info=CUQPS_HAS_EXCEEDED_THE_LIMIT）
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// QPS 防护：距上次请求不足 400ms 时延迟补齐后再发
  Future<void> _throttle() async {
    const minGap = Duration(milliseconds: 400);
    final gap = DateTime.now().difference(_lastRequestAt);
    if (gap < minGap) {
      await Future<void>.delayed(minGap - gap);
    }
    _lastRequestAt = DateTime.now();
  }

  /// 周边地点搜索：坐标 → 附近 POI（按距离由近到远）
  ///
  /// 与逆地理接口不同，本接口检索周边全量 POI 库，地图上标注得到的
  /// 小店、幼儿园等都能返回，用于选点页"附近地点"列表主体。
  Future<List<PoiItem>> around(Gcj02Point point) async {
    final uri = Uri.parse(
      '$_baseUrl/place/around?key=$_webKey'
      '&location=${point.lng},${point.lat}'
      '&radius=1000&offset=25&page=1&sortrule=distance',
    );
    final data = await _get(uri);
    return ((data['pois'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parsePoi)
        .where((p) => p.name.isNotEmpty)
        .toList();
  }

  /// 逆地理（结构化）：坐标 → 省市区街道独立字段 + formatted 整串
  ///
  /// [RegeoDetail.adminPath] 供完整定位信息拼接：纯行政区划不含
  /// 地标名，追加 POI 名永不重复；formatted 仅作结构化字段缺失时兜底
  Future<RegeoDetail> regeoDetail(Gcj02Point point) async {
    final uri = Uri.parse(
      '$_baseUrl/geocode/regeo?key=$_webKey&location=${point.lng},${point.lat}',
    );
    final data = await _get(uri);
    final regeocode = (data['regeocode'] as Map<String, dynamic>?) ?? const {};
    final comp =
        (regeocode['addressComponent'] as Map<String, dynamic>?) ?? const {};
    // 直辖市等场景 city 可能是空数组而非字符串，统一转空串
    String pick(String key) => comp[key] is String ? comp[key] as String : '';
    return RegeoDetail(
      formatted: _str(regeocode['formatted_address']),
      province: pick('province'),
      city: pick('city'),
      district: pick('district'),
      township: pick('township'),
    );
  }

  /// 地理编码：地名 → 坐标（取首个结果）。
  /// 行政区类搜索提示（如"四川省成都市"）无坐标，选中后用它把地图
  /// 带到目标区域，支撑异地补记场景（搜城市名 → 飞过去 → 再选店）。
  Future<Gcj02Point?> geocode(String address) async {
    final uri = Uri.parse(
      '$_baseUrl/geocode/geo?key=$_webKey'
      '&address=${Uri.encodeComponent(address)}',
    );
    final data = await _get(uri);
    final geocodes = ((data['geocodes'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (geocodes.isEmpty) return null;
    return _parseLocation(_str(geocodes.first['location']));
  }

  /// 输入提示：关键词 → 地点候选
  ///
  /// [near] 传入当前坐标使提示就近优先；行政区类提示无坐标
  /// （location 为空），选择后仅返回地名文本。
  Future<List<PoiItem>> inputTips(String keywords, Gcj02Point? near) async {
    var query =
        'key=$_webKey&keywords=${Uri.encodeComponent(keywords)}&citylimit=false';
    if (near != null) {
      query += '&location=${near.lng},${near.lat}';
    }
    final data = await _get(Uri.parse('$_baseUrl/assistant/inputtips?$query'));
    return ((data['tips'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parsePoi)
        .where((p) => p.name.isNotEmpty)
        .toList();
  }

  PoiItem _parsePoi(Map<String, dynamic> raw) {
    return PoiItem(
      name: _str(raw['name']),
      address: _str(raw['address']),
      // 接口返回如 "120.464" 的小数字符串，四舍五入为整米
      distance: double.tryParse(_str(raw['distance']))?.round(),
      location: _parseLocation(_str(raw['location'])),
    );
  }

  /// 高德接口的空值以 []（空数组）表示而非空字符串（如 address、tel），
  /// 直接 as String? 强转会抛类型错误导致整个列表加载失败，统一安全转换
  static String _str(Object? value) => value is String ? value : '';

  /// "116.480829,39.995855" → 坐标；行政区类提示无坐标返回 null
  Gcj02Point? _parseLocation(String text) {
    if (text.isEmpty) return null;
    final parts = text.split(',');
    if (parts.length != 2) return null;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lng == null || lat == null) return null;
    return Gcj02Point(lat: lat, lng: lng);
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    await _throttle();
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('高德接口 HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    // status=1 表示成功，info 字段是失败原因说明
    if (data['status'] != '1') {
      throw Exception('高德接口错误: ${data['info']}');
    }
    return data;
  }
}

/// 附近地点项（列表条目统一模型）
class PoiItem {
  const PoiItem({
    required this.name,
    this.address = '',
    this.distance,
    this.location,
  });

  final String name;
  final String address;

  /// 距坐标点距离（米），周边搜索/逆地理自带，输入提示无此值
  final int? distance;

  /// 坐标（GCJ-02），行政区类输入提示为 null
  final Gcj02Point? location;
}

/// 高德坐标系坐标（GCJ-02 火星坐标）
class Gcj02Point {
  const Gcj02Point({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

/// WGS-84 → GCJ-02 标准偏转算法（公开通用实现）
///
/// 系统定位（geolocator/LocationManager）给出的是 WGS-84 坐标，
/// 高德地图与高德接口使用 GCJ-02，未经偏转会有约 100~600 米偏差。
/// 克拉索夫斯基椭球参数与分段偏转公式为国内地图行业通用实现。
class Wgs84ToGcj02 {
  Wgs84ToGcj02._();

  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  /// 转换；中国境外（含港澳台以外区域判断阈值）原样返回
  static Gcj02Point convert(double wgLat, double wgLng) {
    if (wgLng < 72.004 || wgLng > 137.8347 || wgLat < 0.8293 || wgLat > 55.8271) {
      return Gcj02Point(lat: wgLat, lng: wgLng);
    }
    final dLat = _transformLat(wgLng - 105.0, wgLat - 35.0);
    final dLng = _transformLng(wgLng - 105.0, wgLat - 35.0);
    final radLat = wgLat / 180.0 * pi;
    var magic = sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = sqrt(magic);
    final offsetLat =
        (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * pi);
    final offsetLng = (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * pi);
    return Gcj02Point(lat: wgLat + offsetLat, lng: wgLng + offsetLng);
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }
}
