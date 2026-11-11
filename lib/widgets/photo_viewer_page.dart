import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../theme/app_colors.dart';

/// 全屏图片查看页：黑底 + 双指缩放/拖动 + 左右滑动切换多张，右上角关闭。
/// 图片面板与详情弹窗的大图预览共用本组件。
///
/// 传入 [onEdit] 时底部常驻操作栏（微信式动线）：左侧「编辑」直达编辑器、
/// 右侧 [confirmText] 主按钮（靛蓝胶囊，全 App 主按钮语言）确认收场；
/// 不传则保持纯浏览形态，无底栏
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.paths,
    this.initialIndex = 0,
    this.openHeroTag,
    this.onEdit,
    this.confirmText = '完成',
  });

  /// 可切换的全部图片（本地文件路径）
  final List<String> paths;

  /// 打开时定位到第几张
  final int initialIndex;

  /// 被点缩略图的 Hero 标签：打开/关闭时从缩略图位置飞出/飞回；
  /// null 不启用 Hero 动画
  final Object? openHeroTag;

  /// 编辑回调：非空时底部常驻操作栏，参数为当前图片路径。
  /// 编辑完成后由调用方关闭本页处理结果
  final void Function(String path)? onEdit;

  /// 底栏主按钮文案：确认选图场景用「完成」，纯查看场景用「关闭」
  final String confirmText;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late int _index = widget.initialIndex.clamp(0, widget.paths.length - 1);
  late final PageController _controller = PageController(initialPage: _index);

  /// 底栏高度估算：内容 48 + 纵向留白 12，用于多图页码的底部让位
  static const double _bottomBarExtent = 60;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.paths.length > 1;
    // 直接用 PageView + PhotoView（而非 PhotoViewGallery）：gallery 的
    // options 不透传 strictScale，而缩放"松手弹回"必须靠它根治——
    // 双指快抬/捏过头的瞬间 scale 不会越界，松手就没有越界回弹动画
    final gallery = PageView.builder(
      controller: _controller,
      itemCount: widget.paths.length,
      onPageChanged: (i) => setState(() => _index = i),
      itemBuilder: (_, i) => PhotoView(
        imageProvider: FileImage(File(widget.paths[i])),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
        strictScale: true,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.openHeroTag == null
                ? gallery
                : Hero(tag: widget.openHeroTag!, child: gallery),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
          // 页码：无底栏时贴底居中；有底栏时让位到操作栏上方
          if (multiple)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: EdgeInsets.only(
                    bottom: widget.onEdit != null ? _bottomBarExtent + 16 : 20,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${_index + 1}/${widget.paths.length}',
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
              ),
            ),
          // 底部常驻操作栏：编辑直达 + 主按钮收场，入口一眼可见
          if (widget.onEdit != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  height: _bottomBarExtent,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.92),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => widget.onEdit!(widget.paths[_index]),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit, size: 18, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                '编辑',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: Text(
                          widget.confirmText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
