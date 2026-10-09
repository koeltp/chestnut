import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// 全屏图片查看页：黑底 + 双指缩放/拖动 + 左右滑动切换多张，右上角关闭。
/// 图片面板与详情弹窗的大图预览共用本组件
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.paths,
    this.initialIndex = 0,
    this.openHeroTag,
  });

  /// 可切换的全部图片（本地文件路径）
  final List<String> paths;

  /// 打开时定位到第几张
  final int initialIndex;

  /// 被点缩略图的 Hero 标签：打开/关闭时从缩略图位置飞出/飞回；
  /// null 不启用 Hero 动画
  final Object? openHeroTag;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late int _index = widget.initialIndex.clamp(0, widget.paths.length - 1);
  late final PageController _controller = PageController(initialPage: _index);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.paths.length > 1;
    final gallery = PhotoViewGallery.builder(
      pageController: _controller,
      itemCount: widget.paths.length,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      onPageChanged: (i) => setState(() => _index = i),
      builder: (_, i) => PhotoViewGalleryPageOptions(
        imageProvider: FileImage(File(widget.paths[i])),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
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
                  child: const Icon(
                    Icons.close,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // 页码放底部居中：不与关闭按钮挤一角，滑动切换时位置反馈醒目
          if (multiple)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 20),
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
        ],
      ),
    );
  }
}
