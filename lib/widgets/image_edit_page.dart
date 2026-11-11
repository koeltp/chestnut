import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../theme/app_colors.dart';
import '../utils/show_toast.dart';

/// 图片编辑页（账单图片 / 借据照片共用）
///
/// 工具分两类，**顺序定死：几何先行、标注在后**：
/// · 几何操作（旋转 / 镜像 / 裁剪）作用于整张位图；
/// · 标注操作（画笔 / 箭头 / 马赛克 / 文字）以归一化坐标叠加在位图上，
///   一旦再做几何操作，先把已画内容栅格化烘焙进位图（否则裁剪会让
///   笔迹错位），烘焙后不可撤销标注。
///
/// 编辑全程在内存副本上进行，原图文件不动；「完成」把最终位图编码为
/// JPEG（长边不变、q80，与暂存口径一致）pop 返回，是否落盘 / 入库 /
/// 上云由调用方决定（暂存图换文件、已入库图走"删旧存新"替换）。
class ImageEditPage extends StatefulWidget {
  const ImageEditPage({super.key, required this.sourcePath});

  /// 源图本地路径（读取一次作为初始位图，之后不再回读）
  final String sourcePath;

  @override
  State<ImageEditPage> createState() => _ImageEditPageState();
}

class _ImageEditPageState extends State<ImageEditPage> {
  // ---------- 位图状态 ----------

  /// 当前位图 JPEG 字节（变换/烘焙后同步刷新；「完成」返回它）
  Uint8List? _bytes;

  /// 当前位图解码结果（绘制与栅格化的基准）
  ui.Image? _base;

  /// 像素化版本（马赛克笔刷的纹理源），随 _base 一同重建
  ui.Image? _pixelated;

  /// 当前基准位图的采样均值亮度（0-255），供亮度突降校验用
  double _baseMeanLum = 0;

  // ---------- 标注状态 ----------

  final List<_Annotation> _strokes = [];

  _Tool _tool = _Tool.pen;
  Color _color = AppColors.expense;

  /// 是否发生过编辑（退出时提示确认用）
  bool _modified = false;

  /// 异步操作（变换/烘焙/裁剪）进行中：遮罩转圈并禁点工具
  bool _busy = false;

  // ---------- 裁剪状态（编辑器内置，纯 Flutter） ----------

  /// 裁剪模式：画布上叠加可拖拽裁剪框，标注暂不参与、确认时一并烘焙
  bool _cropMode = false;

  /// 裁剪框（归一化 0-1，画布与标注同坐标系）
  Rect? _cropRect;

  /// 正在拖拽的裁剪框部位：0-3 四角（TL/TR/BR/BL）、4-7 四边（T/R/B/L）、8 整体平移
  int? _cropZone;

  /// 拖拽起点时的裁剪框与手指位置（平移/缩放基准）
  Rect? _cropDragOrig;
  Offset? _cropDragStart;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _base?.dispose();
    _pixelated?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    ui.Image? pix;
    double mean = 0;
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final built = await _buildPixelated(frame.image);
      pix = built.full;
      mean = built.meanLum;
      if (!mounted) {
        frame.image.dispose();
        pix.dispose();
        return;
      }
      setState(() {
        _base = frame.image;
        _bytes = bytes;
        _pixelated = pix!;
        _baseMeanLum = mean;
      });
      pix = null; // 所有权已移交页面状态
    } catch (_) {
      pix?.dispose();
      if (!mounted) return;
      showAppToast(context, '图片加载失败');
      Navigator.of(context).pop();
    }
  }

  // ---------- 几何操作（旋转 / 镜像 / 裁剪） ----------

  /// 顺时针旋转 90°
  Future<void> _rotate() => _transform(rotate: true);

  /// 水平镜像
  Future<void> _flip() => _transform(rotate: false);

  Future<void> _transform({required bool rotate}) async {
    final base = _base;
    if (_busy || base == null) return;
    _setBusy(true);
    try {
      await _bakeStrokes();
      final src = _base!;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (rotate) {
        canvas.translate(src.height.toDouble(), 0);
        canvas.rotate(math.pi / 2);
      } else {
        canvas.translate(src.width.toDouble(), 0);
        canvas.scale(-1, 1);
      }
      canvas.drawImage(src, Offset.zero, Paint());
      final img = await recorder.endRecording().toImage(
        rotate ? src.height : src.width,
        rotate ? src.width : src.height,
      );
      await _swapBase(img);
      _modified = true;
    } catch (_) {
      if (mounted) showAppToast(context, '操作失败，请重试');
    } finally {
      _setBusy(false);
    }
  }

  // ---------- 裁剪（编辑器内置） ----------

  /// 进入裁剪模式：框初始为全图；标注不参与框选，确认时才烘焙
  void _startCrop() {
    if (_busy || _base == null) return;
    setState(() {
      _cropMode = true;
      _cropRect = const Rect.fromLTRB(0, 0, 1, 1);
    });
  }

  /// 退出裁剪模式，标注原样保留
  void _cancelCrop() {
    setState(() {
      _cropMode = false;
      _cropRect = null;
      _cropZone = null;
      _cropDragOrig = null;
      _cropDragStart = null;
    });
  }

  /// 应用裁剪：先把标注烘焙进位图（保证一起被裁），再按裁剪框
  /// 从位图原像素上切出新图。亮度校验对裁剪放宽为"非全黑"——
  /// 裁到画面暗部属合法操作，均值变暗不该被拦
  Future<void> _applyCrop() async {
    if (_busy) return;
    final rect = _cropRect;
    if (rect == null || _base == null) return;
    _setBusy(true);
    try {
      await _bakeStrokes();
      final src = _base!;
      final left = (rect.left * src.width).round().clamp(0, src.width - 2);
      final top = (rect.top * src.height).round().clamp(0, src.height - 2);
      final right = (rect.right * src.width).round().clamp(left + 1, src.width);
      final bottom = (rect.bottom * src.height).round().clamp(
        top + 1,
        src.height,
      );
      final w = right - left;
      final h = bottom - top;
      if (w < 24 || h < 24) {
        if (mounted) showAppToast(context, '裁剪区域太小');
        return;
      }
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
          .drawImage(src, Offset(-left.toDouble(), -top.toDouble()), Paint());
      final cropped = await recorder.endRecording().toImage(w, h);
      await _swapBase(cropped, stableLum: false);
      _modified = true;
      setState(() {
        _cropMode = false;
        _cropRect = null;
      });
    } catch (e, st) {
      debugPrint('chestnut_edit: crop failed: $e\n$st');
      if (mounted) showAppToast(context, '裁剪失败，请重试');
    } finally {
      _setBusy(false);
    }
  }

  /// 裁剪框命中判定（屏幕像素容差）：四角 > 四边 > 框内
  int? _cropHitZone(Offset n, Size size) {
    final r = _cropRect;
    if (r == null) return null;
    final p = Offset(n.dx * size.width, n.dy * size.height);
    final tl = Offset(r.left * size.width, r.top * size.height);
    final tr = Offset(r.right * size.width, r.top * size.height);
    final br = Offset(r.right * size.width, r.bottom * size.height);
    final bl = Offset(r.left * size.width, r.bottom * size.height);
    const cornerR = 30.0;
    if ((p - tl).distance <= cornerR) return 0;
    if ((p - tr).distance <= cornerR) return 1;
    if ((p - br).distance <= cornerR) return 2;
    if ((p - bl).distance <= cornerR) return 3;
    const edgeBand = 18.0;
    if (p.dy >= r.top * size.height - edgeBand &&
        p.dy <= r.bottom * size.height + edgeBand) {
      if ((p.dx - r.left * size.width).abs() <= edgeBand) return 7;
      if ((p.dx - r.right * size.width).abs() <= edgeBand) return 5;
    }
    if (p.dx >= r.left * size.width - edgeBand &&
        p.dx <= r.right * size.width + edgeBand) {
      if ((p.dy - r.top * size.height).abs() <= edgeBand) return 4;
      if ((p.dy - r.bottom * size.height).abs() <= edgeBand) return 6;
    }
    if (r.contains(n)) return 8;
    return null;
  }

  /// 按部位更新裁剪框。min 为框的最小归一化尺寸，防止缩成一点
  Rect _updatedCropRect(int zone, Rect o, Offset pos) {
    const min = 0.05;
    var l = o.left, t = o.top, r = o.right, b = o.bottom;
    switch (zone) {
      case 0:
        l = math.min(pos.dx, r - min);
        t = math.min(pos.dy, b - min);
      case 1:
        r = math.max(pos.dx, l + min);
        t = math.min(pos.dy, b - min);
      case 2:
        r = math.max(pos.dx, l + min);
        b = math.max(pos.dy, t + min);
      case 3:
        l = math.min(pos.dx, r - min);
        b = math.max(pos.dy, t + min);
      case 4:
        t = math.min(pos.dy, b - min);
      case 5:
        r = math.max(pos.dx, l + min);
      case 6:
        b = math.max(pos.dy, t + min);
      case 7:
        l = math.min(pos.dx, r - min);
      case 8:
        final dx = pos.dx - _cropDragStart!.dx;
        final dy = pos.dy - _cropDragStart!.dy;
        l = (o.left + dx).clamp(0.0, 1.0 - o.width);
        t = (o.top + dy).clamp(0.0, 1.0 - o.height);
        r = l + o.width;
        b = t + o.height;
    }
    return Rect.fromLTRB(
      l.clamp(0.0, 1.0),
      t.clamp(0.0, 1.0),
      r.clamp(0.0, 1.0),
      b.clamp(0.0, 1.0),
    );
  }

  // ---------- 标注操作（画笔 / 箭头 / 马赛克 / 文字） ----------

  /// 正在拖动的文字标注下标（文字模式专用），null 表示不在拖动
  int? _dragTextIndex;

  /// 拖动开始时「锚点与手指」的偏移量，拖动全程保持，
  /// 避免文字突然跳到手指位置
  Offset _dragTextGrabOffset = Offset.zero;

  /// 正在抓取的箭头下标与操作：0=拖起点 1=拖终点 2=整体平移；
  /// index 为 null 表示不在操作已有箭头
  int? _dragArrowIndex;
  int? _arrowOp;

  /// 整体平移的基准：抓取时的两个端点 + 手指位置
  List<Offset> _arrowGrabOrig = const [];
  Offset _arrowGrabTouch = Offset.zero;

  /// 本次手势是否新建了笔迹（区分"画新箭头"和"操作旧箭头"，
  /// 决定 onPanEnd/onPanCancel 的收尾行为）
  bool _strokeCreatedThisGesture = false;

  void _addStroke(_Annotation stroke) {
    setState(() {
      _strokes.add(stroke);
      _modified = true;
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  /// 文字输入弹窗：新增与编辑共用，返回输入内容；
  /// 取消返回 null，确认空串表示删除（编辑场景）
  Future<String?> _promptText(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '输入标注文字',
            hintStyle: TextStyle(color: Colors.white38),
            counterStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 文字标注：点空白处写哪儿弹哪儿，确认后落一笔
  Future<void> _addTextAt(Offset normPos) async {
    final text = await _promptText('添加文字', '');
    if (text == null || text.isEmpty || !mounted) return;
    _addStroke(
      _Annotation(
        kind: _Tool.text,
        points: [normPos],
        color: _color,
        text: text,
      ),
    );
  }

  /// 编辑已有文字：预填原内容；清空后确认即删除该文字，取消不动
  Future<void> _editText(int index) async {
    final existing = _strokes[index];
    final text = await _promptText('编辑文字', existing.text);
    if (text == null || !mounted) return;
    setState(() {
      if (text.isEmpty) {
        _strokes.removeAt(index);
      } else if (text != existing.text) {
        _strokes[index] = _Annotation(
          kind: _Tool.text,
          points: existing.points,
          color: existing.color,
          text: text,
        );
        _modified = true;
      }
    });
  }

  /// 统一对象命中测试：文字（矩形）与箭头（头/尾/杆身）在任何工具
  /// 下都可直接抓取——"看到对象就能操作"，与当前画笔无关（微信式）。
  /// 返回 (下标, 操作)：0=箭头起点 1=箭头终点 2=箭头杆身 3=文字；
  /// 端点优先于杆身，从最上层标注向下找；未命中返回 null
  (int, int)? _hitObject(Offset normPos, Size boxSize) {
    final base = _base;
    if (base == null) return null;
    final px = Offset(normPos.dx * boxSize.width, normPos.dy * boxSize.height);
    // 图片像素 → 屏幕逻辑像素的缩放（画布保持图片宽高比，x/y 同比）
    final scale = boxSize.width / base.width;
    for (var i = _strokes.length - 1; i >= 0; i--) {
      final s = _strokes[i];
      if (s.kind == _Tool.text && s.points.isNotEmpty) {
        // 文字：按整个文字矩形判定（与绘制同一套排版量宽，外加
        // 8px 容差）；旧版只认锚点周围小圆，中段/边缘拖不动
        final center = Offset(
          s.points.first.dx * boxSize.width,
          s.points.first.dy * boxSize.height,
        );
        final p = _buildTextParagraph(
          s,
          base.width.toDouble(),
          const Color(0xFFFFFFFF),
        );
        final half = Offset(p.longestLine / 2, p.height / 2) * scale;
        if ((px.dx - center.dx).abs() <= half.dx + 8 &&
            (px.dy - center.dy).abs() <= half.dy + 8) {
          return (i, 3);
        }
      } else if (s.kind == _Tool.arrow && s.points.length >= 2) {
        final a = Offset(
          s.points[0].dx * boxSize.width,
          s.points[0].dy * boxSize.height,
        );
        final b = Offset(
          s.points[1].dx * boxSize.width,
          s.points[1].dy * boxSize.height,
        );
        if ((px - a).distance <= 30) return (i, 0);
        if ((px - b).distance <= 30) return (i, 1);
        // 点到线段距离：只认杆身中段（端点附近留给拖头/拖尾）
        final ab = b - a;
        final len2 = ab.distanceSquared;
        if (len2 > 0) {
          final t = ((px - a).dx * ab.dx + (px - a).dy * ab.dy) / len2;
          if (t > 0.08 && t < 0.92 && (px - (a + ab * t)).distance <= 22) {
            return (i, 2);
          }
        }
      }
    }
    return null;
  }

  /// 把未烘焙的标注栅格化进位图。无标注时直接返回（几何操作前的
  /// 强制步骤）。笔迹清空与位图提交在同一帧完成，提交失败时笔迹
  /// 保留在屏幕上，不丢标注
  Future<void> _bakeStrokes() async {
    final base = _base;
    if (base == null || _strokes.isEmpty) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // 烘焙必须先画底图（画布原点是透明的，不画底图则透明区域在
    // JPEG 里变纯黑——这正是"编辑后黑图"的根因），再栅格化标注
    canvas.drawImage(base, Offset.zero, Paint());
    _drawAnnotations(canvas, base, List.of(_strokes), pixelated: _pixelated);
    final img = await recorder.endRecording().toImage(base.width, base.height);
    await _swapBase(img, onCommitted: _strokes.clear);
  }

  // ---------- 位图切换与编码 ----------

  /// 用新位图原子化替换当前基准：探测有效性 → 重建马赛克纹理 →
  /// 一帧内同时提交 base/bytes/pixelated。任何一步失败都保持旧
  /// 状态不变并抛出（调用方 toast），不会出现"黑图已上屏、纹理
  /// 还是旧的"的错位状态。旧纹理等新帧渲染完成后再释放——全尺寸
  /// 位图每张十几 MB，不释放连续几次操作就会 OOM
  Future<void> _swapBase(
    ui.Image img, {
    VoidCallback? onCommitted,
    bool stableLum = true,
  }) async {
    final oldBase = _base;
    final oldPix = _pixelated;
    try {
      final encoded = await _encodeJpeg(img);
      final pix = await _buildPixelated(img);
      // 亮度突降校验：Impeller 黑图 bug 的输出是"底图全黑 + 矢量
      // 标注正常"，红色箭头/文字的亮度差会骗过单色探测，用均值
      // 亮度兜底——烘焙/旋转不该让画面整体明显变暗。裁剪会合法地
      // 改变均值（裁到暗部），传 stableLum: false 只做单色探测
      if (stableLum && _baseMeanLum > 24 && pix.meanLum < _baseMeanLum * 0.45) {
        throw Exception('位图亮度校验未通过（系统图形栈疑似输出异常）');
      }
      if (!mounted) {
        img.dispose();
        pix.full.dispose();
        return;
      }
      setState(() {
        _base = img;
        _bytes = encoded;
        _pixelated = pix.full;
        _baseMeanLum = pix.meanLum;
        onCommitted?.call();
      });
      // 旧纹理必须等"不包含它们的新帧"渲染完成后才能释放，
      // 立即 dispose 可能与光栅线程竞争导致 native 崩溃
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldBase?.dispose();
        oldPix?.dispose();
      });
    } catch (_) {
      // 探测/编码失败：丢弃坏图，旧基准原样保留
      img.dispose();
      rethrow;
    }
  }

  /// 由基准位图生成马赛克纹理：整图缩小 1/24 再以 none 采样放大回
  /// 原尺寸，得到块状像素化图，笔刷沿轨迹刷出时与原图坐标 1:1 对齐。
  /// 缩小产物同时充当基准位图的有效性探针，返回 (纹理, 均值亮度)
  Future<({ui.Image full, double meanLum})> _buildPixelated(
    ui.Image base,
  ) async {
    final smallW = math.max(1, base.width ~/ 24);
    final smallH = math.max(1, base.height ~/ 24);
    final small = await _resample(base, smallW, smallH, none: false);
    try {
      final meanLum = await _probeImage(small);
      final full = await _resample(small, base.width, base.height, none: true);
      return (full: full, meanLum: meanLum);
    } finally {
      small.dispose();
    }
  }

  /// 位图有效性探测：均匀抽样约 512 个点的亮度，整幅几乎单色
  /// （极差 < 12）即判定为坏图并抛出。返回采样均值亮度（0-255）。
  /// Impeller 的 Picture.toImage 在部分机型上有整幅输出黑图的
  /// 已知问题，真实照片/截图不可能完美单色
  Future<double> _probeImage(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw Exception('位图读取失败（系统图形栈疑似输出异常）');
    }
    final px = data.buffer.asUint8List();
    final pixels = px.lengthInBytes ~/ 4;
    if (pixels == 0) {
      throw Exception('空位图（系统图形栈疑似输出异常）');
    }
    final step = math.max(1, pixels ~/ 512);
    var lo = 255;
    var hi = 0;
    var sum = 0;
    var n = 0;
    for (var i = 0; i < pixels; i += step) {
      final o = i * 4;
      final l = (px[o] * 299 + px[o + 1] * 587 + px[o + 2] * 114) ~/ 1000;
      if (l < lo) lo = l;
      if (l > hi) hi = l;
      sum += l;
      n++;
    }
    if (hi - lo < 12) {
      throw Exception('位图近乎单色（系统图形栈疑似输出异常）');
    }
    return sum / math.max(1, n);
  }

  Future<ui.Image> _resample(
    ui.Image src,
    int w,
    int h, {
    required bool none,
  }) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = none ? FilterQuality.none : FilterQuality.medium,
    );
    return recorder.endRecording().toImage(w, h);
  }

  Future<Uint8List> _encodeJpeg(ui.Image img) async {
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final raw = png!.buffer.asUint8List();
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: img.width,
        minHeight: img.height,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return compressed.isNotEmpty ? compressed : raw;
    } catch (_) {
      return raw; // 压缩失败退回 PNG 字节，保证不丢图
    }
  }

  // ---------- 退出与完成 ----------

  Future<void> _finish() async {
    if (_busy) return;
    _setBusy(true);
    try {
      await _bakeStrokes();
      if (mounted) Navigator.of(context).pop(_bytes);
    } catch (_) {
      _setBusy(false);
      if (mounted) showAppToast(context, '保存失败，请重试');
    }
  }

  Future<void> _onBack() async {
    // 裁剪模式按返回 = 退出裁剪（标注未动，无需确认）
    if (_cropMode) {
      _cancelCrop();
      return;
    }
    if (!_modified) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '放弃编辑？',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          '当前修改不会被保存',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  void _setBusy(bool busy) {
    if (mounted) setState(() => _busy = busy);
  }

  // ---------- 手势 → 归一化坐标 ----------

  Offset _normalize(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    final base = _base;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.black,
            body: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: base == null
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _buildCanvas(base),
                ),
                if (!_cropMode) _buildPalette(),
                _cropMode ? _buildCropBar() : _buildToolbar(),
              ],
            ),
          ),
          // 异步操作遮罩：转圈并拦截点击
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black38,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _busy ? null : _onBack,
          ),
          Expanded(
            child: Text(
              '编辑图片',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _finish,
            child: const Text(
              '完成',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 画布：等比适配屏幕，手势按画布尺寸归一化。
  /// 注意：手势坐标必须取 AspectRatio 内层盒（图片实际显示区），
  /// 取外层 LayoutBuilder 盒会引入黑边偏移——箭头"起点偏上"、
  /// 文字命中框错位、画笔偏移都源于此
  Widget _buildCanvas(ui.Image base) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = base.width / base.height;
        return Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Builder(
              builder: (canvasContext) => GestureDetector(
                // 文字模式：点空白=新增文字，点已有文字=编辑
                onTapUp: _tool == _Tool.text && !_busy && !_cropMode
                    ? (d) {
                        final box =
                            canvasContext.findRenderObject()! as RenderBox;
                        final pos = _normalize(
                          box.globalToLocal(d.globalPosition),
                          box.size,
                        );
                        final hit = _hitObject(pos, box.size);
                        if (hit != null && hit.$2 == 3) {
                          _editText(hit.$1);
                        } else if (hit == null) {
                          _addTextAt(pos);
                        }
                      }
                    : null,
                // 所有工具：按下即命中已有对象（文字/箭头）则抓取操作，
                // 与当前工具无关——"看到对象就能操作"；未命中时绘制工具
                // 在按下瞬间创建笔迹（onPanStart 有 ~18px 拖动激活阈值，
                // 会让起点落后于指尖），文字模式空白处留给 onTapUp 新增
                onPanDown:
                    !_busy &&
                        !_cropMode &&
                        (_isDrawingTool || _tool == _Tool.text)
                    ? (d) {
                        final box =
                            canvasContext.findRenderObject()! as RenderBox;
                        final pos = _normalize(
                          box.globalToLocal(d.globalPosition),
                          box.size,
                        );
                        final grab = _hitObject(pos, box.size);
                        setState(() {
                          _strokeCreatedThisGesture = false;
                          _dragArrowIndex = null;
                          _arrowOp = null;
                          _dragTextIndex = null;
                          if (grab != null) {
                            final (i, op) = grab;
                            if (op == 3) {
                              // 文字：记住抓取偏移，拖动不跳位
                              _dragTextIndex = i;
                              _dragTextGrabOffset =
                                  _strokes[i].points.first - pos;
                            } else {
                              // 箭头：0=拖起点 1=拖终点 2=整体平移
                              _dragArrowIndex = i;
                              _arrowOp = op;
                              _arrowGrabOrig = List.of(_strokes[i].points);
                              _arrowGrabTouch = pos;
                            }
                            return;
                          }
                          if (_tool == _Tool.text) return;
                          _strokeCreatedThisGesture = true;
                          _strokes.add(
                            _Annotation(
                              kind: _tool,
                              points: [pos],
                              color: _color,
                            ),
                          );
                        });
                      }
                    : null,
                onPanUpdate:
                    !_busy &&
                        !_cropMode &&
                        (_isDrawingTool || _tool == _Tool.text)
                    ? (d) {
                        final box =
                            canvasContext.findRenderObject()! as RenderBox;
                        final pos = _normalize(
                          box.globalToLocal(d.globalPosition),
                          box.size,
                        );
                        setState(() {
                          // 拖动文字（任意工具下抓取均可）：锚点 = 手指 +
                          // 抓取偏移（不跳位），钳制在图内
                          if (_dragTextIndex != null) {
                            final i = _dragTextIndex;
                            if (i != null && i < _strokes.length) {
                              final s = _strokes[i];
                              final target = pos + _dragTextGrabOffset;
                              _strokes[i] = _Annotation(
                                kind: s.kind,
                                points: [
                                  Offset(
                                    target.dx.clamp(0.0, 1.0),
                                    target.dy.clamp(0.0, 1.0),
                                  ),
                                ],
                                color: s.color,
                                text: s.text,
                              );
                              _modified = true;
                            }
                            return;
                          }
                          // 操作已有箭头：拖头 / 拖尾 / 整体平移
                          final i = _dragArrowIndex;
                          if (i != null && i < _strokes.length) {
                            final s = _strokes[i];
                            Offset clamp01(Offset p) => Offset(
                              p.dx.clamp(0.0, 1.0),
                              p.dy.clamp(0.0, 1.0),
                            );
                            final pts = List.of(s.points);
                            switch (_arrowOp) {
                              case 0:
                                pts[0] = clamp01(pos);
                              case 1:
                                pts[1] = clamp01(pos);
                              default:
                                final delta = pos - _arrowGrabTouch;
                                pts[0] = clamp01(_arrowGrabOrig[0] + delta);
                                pts[1] = clamp01(_arrowGrabOrig[1] + delta);
                            }
                            _strokes[i] = _Annotation(
                              kind: s.kind,
                              points: pts,
                              color: s.color,
                            );
                            _modified = true;
                            return;
                          }
                          // 新笔迹延伸：仅当本次手势创建过笔迹。文字模式
                          // 空白处按下未创建，避免误接到上一条旧笔迹上
                          if (!_strokeCreatedThisGesture || _strokes.isEmpty) {
                            return;
                          }
                          final last = _strokes.last;
                          if (_tool == _Tool.arrow) {
                            // 箭头实时跟随：起点固定、终点刷新
                            if (last.points.length == 1) {
                              last.points.add(pos);
                            } else {
                              last.points[1] = pos;
                            }
                          } else {
                            last.points.add(pos);
                          }
                        });
                      }
                    : null,
                onPanEnd:
                    !_busy &&
                        !_cropMode &&
                        (_isDrawingTool || _tool == _Tool.text)
                    ? (_) => setState(() {
                        _dragTextIndex = null;
                        _dragArrowIndex = null;
                        _arrowOp = null;
                        if (_strokeCreatedThisGesture) {
                          // 单点也成笔（画笔/马赛克点一下=一个点），避免空笔迹；
                          // 文字与箭头操作不在此处标脏（是否改动由
                          // 拖动/编辑决定），否则按住未动会误触发退出确认
                          if (_tool != _Tool.arrow &&
                              _strokes.isNotEmpty &&
                              _strokes.last.points.length == 1) {
                            final pt = _strokes.last.points.first;
                            _strokes.last.points.add(
                              Offset(pt.dx + 0.001, pt.dy + 0.001),
                            );
                          }
                          _modified = true;
                          _strokeCreatedThisGesture = false;
                        }
                      })
                    : null,
                // 手势未成为拖动（如轻点后抬起）时收尾：新建的箭头残笔
                // 撤掉，画笔/马赛克的单点保留为"点一下=一个点"
                onPanCancel:
                    !_busy &&
                        !_cropMode &&
                        (_isDrawingTool || _tool == _Tool.text)
                    ? () => setState(() {
                        if (_strokeCreatedThisGesture) {
                          if (_tool == _Tool.arrow &&
                              _strokes.isNotEmpty &&
                              _strokes.last.points.length == 1) {
                            _strokes.removeLast();
                          } else {
                            _modified = true;
                          }
                          _strokeCreatedThisGesture = false;
                        }
                        _dragArrowIndex = null;
                        _arrowOp = null;
                        _dragTextIndex = null;
                      })
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      size: Size.infinite,
                      painter: _EditPainter(
                        base: base,
                        strokes: List.of(_strokes),
                        pixelated: _pixelated,
                      ),
                    ),
                    // 裁剪模式：遮罩 + 可拖拽裁剪框，盖在标注层之上
                    if (_cropMode && _cropRect != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) {
                          final box =
                              canvasContext.findRenderObject()! as RenderBox;
                          final pos = _normalize(
                            box.globalToLocal(d.globalPosition),
                            box.size,
                          );
                          final zone = _cropHitZone(pos, box.size);
                          setState(() {
                            _cropZone = zone;
                            _cropDragOrig = _cropRect;
                            _cropDragStart = pos;
                          });
                        },
                        onPanUpdate: (d) {
                          final box =
                              canvasContext.findRenderObject()! as RenderBox;
                          final pos = _normalize(
                            box.globalToLocal(d.globalPosition),
                            box.size,
                          );
                          final zone = _cropZone;
                          final orig = _cropDragOrig;
                          if (zone == null || orig == null) return;
                          setState(() {
                            _cropRect = _updatedCropRect(zone, orig, pos);
                          });
                        },
                        onPanEnd: (_) => setState(() {
                          _cropZone = null;
                          _cropDragOrig = null;
                          _cropDragStart = null;
                        }),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _CropPainter(_cropRect!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _isDrawingTool =>
      _tool == _Tool.pen || _tool == _Tool.arrow || _tool == _Tool.mosaic;

  /// 颜色选择行：画笔/箭头/文字激活时显示
  Widget _buildPalette() {
    const colors = [
      AppColors.expense,
      AppColors.warning,
      AppColors.primary,
      Colors.white,
      AppColors.textPrimary,
    ];
    final visible =
        _tool == _Tool.pen || _tool == _Tool.arrow || _tool == _Tool.text;
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final c in colors)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == c ? AppColors.primary : Colors.white24,
                    width: _color == c ? 2.5 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 裁剪模式的确认栏：取消 / 完成（主色胶囊，全 App 主按钮语言）
  Widget _buildCropBar() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF141414)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              TextButton(
                onPressed: _busy ? null : _cancelCrop,
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : _applyCrop,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    Widget tool(_Tool t, IconData icon, String label) {
      final active = _tool == t;
      return Expanded(
        child: InkWell(
          onTap: _busy ? null : () => setState(() => _tool = t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active ? AppColors.primary : Colors.white70,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: active ? AppColors.primary : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget action(IconData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: Colors.white70),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(color: Color(0xFF141414)),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            action(Icons.rotate_right, '旋转', _rotate),
            action(Icons.flip, '镜像', _flip),
            action(Icons.crop, '裁剪', _startCrop),
            tool(_Tool.pen, Icons.edit, '画笔'),
            tool(_Tool.arrow, Icons.north_east, '箭头'),
            tool(_Tool.mosaic, Icons.grain, '马赛克'),
            tool(_Tool.text, Icons.text_fields, '文字'),
            action(Icons.undo, '撤销', _undo),
          ],
        ),
      ),
    );
  }
}

// ---------- 标注数据模型与绘制 ----------

enum _Tool { pen, arrow, mosaic, text }

/// 一笔标注：坐标归一化（0~1 相对图片宽高），线宽相对图片宽度，
/// 保证烘焙前后、不同分辨率下视觉一致
class _Annotation {
  _Annotation({
    required this.kind,
    required this.points,
    required this.color,
    this.text = '',
  });

  final _Tool kind;

  /// 画笔/马赛克：轨迹点列；箭头：[起点, 终点]；文字：锚点单点
  final List<Offset> points;
  final Color color;
  final String text;

  double get widthFactor => switch (kind) {
    _Tool.pen => 0.006,
    _Tool.arrow => 0.005,
    _Tool.mosaic => 0.055,
    _Tool.text => 0.055,
  };
}

/// 标注绘制：实时预览与烘焙共用同一套逻辑，保证所见即所得。
/// 箭头带燕尾头；马赛克以像素化纹理为笔刷；文字带暗色投影保证
/// 在任意底色上可读
void _drawAnnotations(
  Canvas canvas,
  ui.Image base,
  List<_Annotation> strokes, {
  ui.Image? pixelated,
}) {
  final imgW = base.width.toDouble();
  final imgH = base.height.toDouble();
  for (final s in strokes) {
    final strokeWidth = s.widthFactor * imgW;
    switch (s.kind) {
      case _Tool.pen:
        final paint = Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(_pathOf(s.points, imgW, imgH), paint);
      case _Tool.arrow:
        if (s.points.length < 2) continue;
        final from = Offset(s.points[0].dx * imgW, s.points[0].dy * imgH);
        final to = Offset(s.points[1].dx * imgW, s.points[1].dy * imgH);
        final paint = Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(from, to, paint);
        // 燕尾头：两条与主线呈 ±156°（反向张开）的短线
        final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
        final headLen = math.max(strokeWidth * 3.5, imgW * 0.018);
        for (final spread in const [2.72, -2.72]) {
          canvas.drawLine(
            to,
            Offset(
              to.dx + headLen * math.cos(angle + spread),
              to.dy + headLen * math.sin(angle + spread),
            ),
            paint,
          );
        }
      case _Tool.mosaic:
        final pix = pixelated;
        if (pix == null) continue;
        final paint = Paint()
          ..shader = ui.ImageShader(
            pix,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(_pathOf(s.points, imgW, imgH), paint);
      case _Tool.text:
        _drawTextStroke(canvas, s, imgW, imgH);
    }
  }
}

/// 按绘制约束构建文字段落：投影/本体/命中量取共用同一套排版，
/// 保证量出来的宽高和实际画出来的完全一致
ui.Paragraph _buildTextParagraph(_Annotation s, double imgW, Color color) {
  final fontSize = s.widthFactor * imgW;
  return (ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: TextAlign.left, fontSize: fontSize),
        )
        ..pushStyle(ui.TextStyle(color: color))
        ..addText(s.text))
      .build()
    ..layout(ui.ParagraphConstraints(width: imgW * 0.9));
}

void _drawTextStroke(Canvas canvas, _Annotation s, double imgW, double imgH) {
  final anchor = Offset(s.points.first.dx * imgW, s.points.first.dy * imgH);
  // 居中于锚点；先画右下偏移的暗色投影再画本体，任意底色可读
  final shadow = _buildTextParagraph(
    s,
    imgW,
    Colors.black.withValues(alpha: 0.6),
  );
  final topLeft = Offset(
    anchor.dx - shadow.longestLine / 2,
    anchor.dy - shadow.height / 2,
  );
  canvas.drawParagraph(shadow, topLeft + const Offset(1.5, 1.5));
  canvas.drawParagraph(_buildTextParagraph(s, imgW, s.color), topLeft);
}

Path _pathOf(List<Offset> normPoints, double imgW, double imgH) {
  final path = Path();
  var first = true;
  for (final pt in normPoints) {
    final px = Offset(pt.dx * imgW, pt.dy * imgH);
    if (first) {
      path.moveTo(px.dx, px.dy);
    } else {
      path.lineTo(px.dx, px.dy);
    }
    first = false;
  }
  return path;
}

/// 实时预览画笔：底图 + 已画标注
class _EditPainter extends CustomPainter {
  _EditPainter({
    required this.base,
    required this.strokes,
    required this.pixelated,
  });

  final ui.Image base;
  final List<_Annotation> strokes;
  final ui.Image? pixelated;

  @override
  void paint(Canvas canvas, Size size) {
    // 画布缩放到图片像素坐标系：drawImage/stroke/马赛克纹理全部
    // 按 1:1 像素绘制（预览时由这里的 scale 统一映射到屏幕），
    // 否则大图按原始像素画会超出屏幕，表现为"只显示一半"
    final scaleX = size.width / base.width;
    final scaleY = size.height / base.height;
    canvas.scale(scaleX, scaleY);
    canvas.drawImage(base, Offset.zero, Paint());
    _drawAnnotations(canvas, base, strokes, pixelated: pixelated);
  }

  @override
  bool shouldRepaint(covariant _EditPainter old) =>
      old.base != base ||
      old.pixelated != pixelated ||
      !identical(old.strokes, strokes);
}

/// 裁剪模式叠加层：框外半透明遮罩 + 白色边框 + 三分线 + 角部手柄。
/// rect 为归一化坐标，paint 时换算回画布像素（与标注同坐标系）
class _CropPainter extends CustomPainter {
  _CropPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );
    // 四块遮罩：上、下、左、右
    final mask = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, r.top), mask);
    canvas.drawRect(Rect.fromLTRB(0, r.bottom, size.width, size.height), mask);
    canvas.drawRect(Rect.fromLTRB(0, r.top, r.left, r.bottom), mask);
    canvas.drawRect(Rect.fromLTRB(r.right, r.top, size.width, r.bottom), mask);
    // 三分线
    final third = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final x = r.left + r.width * i / 3;
      final y = r.top + r.height * i / 3;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), third);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), third);
    }
    // 边框 + 四角 L 形手柄
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r, border);
    final handle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 22.0;
    void corner(Offset c, int sx, int sy) {
      canvas.drawLine(c, Offset(c.dx + sx * len, c.dy), handle);
      canvas.drawLine(c, Offset(c.dx, c.dy + sy * len), handle);
    }

    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomRight, -1, -1);
    corner(r.bottomLeft, 1, -1);
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.rect != rect;
}
