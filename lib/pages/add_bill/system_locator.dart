import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/amap_service.dart';

/// 系统定位封装（geolocator），与 UI 完全解耦。
///
/// 拆出选点页的三块系统细节：权限与服务检查、缓存位置读取、实时定位。
/// 业务参数集中在此处维护：
/// - 缓存位置 10 分钟内视为新鲜（避免跨城旧缓存误导读到错误城市）；
/// - 实时定位 12 秒超时，forceLocationManager 强走 Android
///   LocationManager（厂商融合定位服务，vivo 等无 GMS 设备回调可靠）。
///   高德定位 SDK 已移除：其网络定位库在无 GMS 设备上 Wi-Fi 指纹未命中
///   时会静默丢回调（连失败回调都没有），是"打开就超时"的根源。
/// 系统坐标为 WGS-84，返回前统一转 GCJ-02。
class SystemLocator {
  /// 权限与服务检查：未通过时返回面向用户的提示文案，通过返回 null。
  /// 插件调用异常（极少见）同样归入失败文案，行为与原选点页一致
  Future<String?> checkPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return '请先开启系统定位服务';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return '未授予定位权限，可在系统设置中开启';
      }
      return null;
    } catch (_) {
      return '定位失败，请稍后重试';
    }
  }

  /// 最近一次系统缓存位置（GCJ-02）：10 分钟内视为新鲜，过期或无缓存
  /// 返回 null。缓存读取失败静默降级（实时定位仍会跟进）
  Future<Gcj02Point?> freshLastKnown() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      final age = last == null
          ? null
          : DateTime.now().difference(last.timestamp);
      if (last != null && age != null && age < const Duration(minutes: 10)) {
        debugPrint('[定位] 系统缓存位置（${age.inSeconds}秒前）');
        return Wgs84ToGcj02.convert(last.latitude, last.longitude);
      }
    } catch (_) {
      // 缓存拿不到无所谓，实时定位还在后面
    }
    return null;
  }

  /// 系统实时定位（GCJ-02）。失败（超时/权限突变/插件异常）抛出异常，
  /// 由调用方结合"缓存是否已上图"决定界面提示方式
  Future<Gcj02Point> locate() async {
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
    return Wgs84ToGcj02.convert(pos.latitude, pos.longitude);
  }
}
