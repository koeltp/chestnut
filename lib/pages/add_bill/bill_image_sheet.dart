import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/database.dart';
import '../../data/repositories/bill_image_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/show_toast.dart';
import '../../widgets/photo_viewer_page.dart';

/// 账单图片面板（bottom sheet，与标签面板同款心智）
///
/// 首次添加与后续管理共用同一个面板：已选图 3 列网格（右上角 × 删除、
/// 点图全屏预览）+「添加」格（拍照 / 相册多选）。选图即压缩并暂存到
/// 本地（离线可看），账单保存时才转正入库并触发上传——面板内只改
/// 工作副本，所有变更通过 [onChanged] 实时回传给记一笔页。
Future<void> showBillImageSheet(
  BuildContext context, {
  required BillImageRepository repo,
  required List<BillImage> existing,
  required List<String> staged,
  required void Function(List<BillImage> existing, List<String> staged)
      onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BillImageSheet(
      repo: repo,
      initialExisting: existing,
      initialStaged: staged,
      onChanged: onChanged,
    ),
  );
}

class BillImageSheet extends StatefulWidget {
  const BillImageSheet({
    super.key,
    required this.repo,
    required this.initialExisting,
    required this.initialStaged,
    required this.onChanged,
  });

  final BillImageRepository repo;
  final List<BillImage> initialExisting;
  final List<String> initialStaged;
  final void Function(List<BillImage> existing, List<String> staged) onChanged;

  @override
  State<BillImageSheet> createState() => _BillImageSheetState();
}

class _BillImageSheetState extends State<BillImageSheet> {
  /// 已入库图片的工作副本（编辑模式回显；删除在保存时统一落库）
  late final List<BillImage> _existing = List.of(widget.initialExisting);

  /// 暂存图片路径的工作副本（本次新加、尚未入库）
  late final List<String> _staged = List.of(widget.initialStaged);

  /// 选图/压缩进行中：添加格显示转圈并防重入
  bool _adding = false;

  void _notify() => widget.onChanged(List.of(_existing), List.of(_staged));

  /// 全部图片数量（已入库 + 暂存），面板标题旁计数
  int get _count => _existing.length + _staged.length;

  /// 添加图片：先选来源（拍照 / 相册多选），拿到的原图统一走
  /// 压缩暂存（长边 1800 JPEG q80）。Android 13+ 相册走系统
  /// Photo Picker 免权限；拍照权限由 image_picker 内部处理
  Future<void> _addImages() async {
    if (_adding) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _adding = true);
    try {
      final picker = ImagePicker();
      final picked = source == ImageSource.camera
          ? [await picker.pickImage(source: ImageSource.camera)]
          : await picker.pickMultiImage();
      for (final xfile in picked) {
        if (xfile == null) continue;
        final bytes = await xfile.readAsBytes();
        final path = await widget.repo.photos.stage(bytes);
        _staged.add(path);
      }
      _notify();
    } catch (_) {
      if (mounted) showAppToast(context, '添加图片失败，请重试');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// 删除一张图：暂存图立即删临时文件；已入库图只从工作副本移除，
  /// 记录 / 本地文件 / 云端对象由记一笔页在保存时统一清理
  Future<void> _remove({BillImage? existing, String? staged}) async {
    if (existing != null) {
      setState(() => _existing.remove(existing));
    } else if (staged != null) {
      setState(() => _staged.remove(staged));
      await widget.repo.photos.discard(staged);
    }
    _notify();
  }

  /// 全屏预览：从被点的那张进入，左右滑可看面板内其余图片
  void _preview(int index, String openHeroTag) {
    // 与网格一致的混排顺序：已入库图在前、暂存图在后
    final paths = [
      ..._existing.map((e) => e.localPath),
      ..._staged,
    ];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(
          paths: paths,
          initialIndex: index,
          openHeroTag: openHeroTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pagePadding,
            16,
            AppDimens.pagePadding,
            AppDimens.pagePadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行：账单图片 + 计数 + ✕ 关闭
              Row(
                children: [
                  Text(
                    _count > 0 ? '账单图片（$_count）' : '账单图片',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 图片网格：外层滚动兜底多图撑高，网格本身不滚
              Flexible(
                child: SingleChildScrollView(
                  child: _buildGrid(),
                ),
              ),
              const SizedBox(height: 12),
              // 底部全宽保存：关闭面板，胶囊随 onChanged 已同步为图片(N)
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusControl),
                    ),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 图片网格：已入库图 + 暂存图按序混排，末尾追加「添加」格。
  /// 固定 56px 正方形格（与详情弹窗缩略图同尺寸），Wrap 流式换行
  Widget _buildGrid() {
    final paths = <String>[
      ..._existing.map((e) => e.localPath),
      ..._staged,
    ];
    final cells = <Widget>[
      for (final image in _existing)
        _ThumbCell(
          path: image.localPath,
          heroTag: 'db-${image.id}',
          onRemove: () => _remove(existing: image),
          onTap: () => _preview(
            paths.indexOf(image.localPath),
            'db-${image.id}',
          ),
        ),
      for (final path in _staged)
        _ThumbCell(
          path: path,
          heroTag: path,
          onRemove: () => _remove(staged: path),
          onTap: () => _preview(paths.indexOf(path), path),
        ),
      _AddCell(busy: _adding, onTap: _addImages),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: cells);
  }
}

/// 缩略图格：圆角方图 + 右上角 × 删除；点击全屏预览
class _ThumbCell extends StatelessWidget {
  const _ThumbCell({
    required this.path,
    required this.heroTag,
    required this.onRemove,
    required this.onTap,
  });

  final String path;
  final Object heroTag;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(path),
                // 与详情弹窗缩略图同尺寸：56px 正方形
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                // 本地文件缺失（缓存被清等）显示占位图标不崩
                errorBuilder: (_, _, _) => Container(
                  width: 56,
                  height: 56,
                  color: AppColors.fill,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 右上角删除：红底圆 + 白 ×（内嵌，避免越界被裁）
        Positioned(
          top: 3,
          right: 3,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: AppColors.expense,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// 「添加」格：浅灰底 + 加号；选图压缩中显示转圈并禁点
class _AddCell extends StatelessWidget {
  const _AddCell({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        // 与缩略图同尺寸：56px 正方形
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: busy
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const Center(
                child: Icon(Icons.add, size: 24, color: AppColors.textSecondary),
              ),
      ),
    );
  }
}
