import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 选点地图标记图标：离屏 Canvas 绘制位图，交给原生 Marker 层。
///
/// amap_map 的 defaultMarker 渲染样式不可控，改用代码绘制位图
/// （fromBytes），无需打包图片资源。仅位置选点页使用。
abstract final class MapMarkerIcons {
  /// 经典 📍 图钉造型（圆头 + 白孔 + 尖底）。
  ///
  /// [color] 区分语义：保存位置用蓝、中心选点用红。
  /// 位图 96×128，尖底位于 y=124（anchor 由调用方按此值设置）。
  static Future<BitmapDescriptor> pin(Color color) async {
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

  /// GPS 当前位置小蓝点（白描边圆点，京东式），48×48，anchor 取中心
  static Future<BitmapDescriptor> dot() async {
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
}
