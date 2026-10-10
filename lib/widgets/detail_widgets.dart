import 'dart:io';

import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/app_colors.dart';

/// 详情弹窗共享组件：操作胶囊 / 信息行 / 照片缩略图
///
/// 账单详情与借条详情共用，保证两个弹窗视觉语言一致。
/// 任一侧未来长出明显差异时再拆回独立实现。

/// 操作胶囊：常规操作浅灰底；[danger] 为 true 时红底红字（删除）
class DetailPill extends StatelessWidget {
  const DetailPill(
    this.text, {
    super.key,
    required this.onTap,
    this.danger = false,
  });

  final String text;
  final VoidCallback onTap;

  /// 危险操作（删除）：红色系提示破坏性
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: danger
              ? AppColors.expense.withValues(alpha: 0.08)
              : AppColors.fill,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: danger ? AppColors.expense : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 信息行：左侧字段名，右侧值（child 自行右对齐/折行）；
/// [onTap] 非空时整行可点（如分类跳转）
class DetailInfoRow extends StatelessWidget {
  const DetailInfoRow({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            // 值拿满标签右侧全部宽度：短值靠右（child 自行右对齐），
            // 长值（地址/备注）自动折行
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// 缩略图：56px 圆角；本地文件缺失显示占位；上传未完成时右上角
/// 状态角标（上传中转圈，等待/失败感叹号，点击重传）
class DetailPhotoThumb extends StatelessWidget {
  const DetailPhotoThumb({
    super.key,
    required this.file,
    required this.uploadState,
    required this.onTap,
    required this.onRetry,
  });

  /// 本地文件：null = 本地缺失且云端未拉回，显示占位
  final File? file;
  final BillImageUploadState uploadState;

  /// 点击缩略图：全屏预览
  final VoidCallback onTap;

  /// 点击状态角标：手动重传
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final uploading = uploadState == BillImageUploadState.uploading;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: file == null
                ? _placeholder()
                : Image.file(
                    file!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    // 文件半路被清（罕见）：退占位，不影响其余图
                    errorBuilder: (_, _, _) => _placeholder(),
                  ),
          ),
        ),
        // 未上传角标：上传中转圈，等待/失败感叹号；点角标手动重传
        if (uploadState != BillImageUploadState.done)
          Positioned(
            right: -3,
            top: -3,
            child: GestureDetector(
              onTap: uploading ? null : onRetry,
              child: Container(
                width: 16,
                height: 16,
                // 半透明黑圆底：角标浮在照片上，白底遇白图会隐身
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: uploading
                    ? const Padding(
                        padding: EdgeInsets.all(3),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppColors.expense,
                      ),
              ),
            ),
          ),
      ],
    );
  }

  /// 占位格：浅灰底 + 图片图标
  Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.fill,
      child: const Icon(
        Icons.image_outlined,
        size: 20,
        color: AppColors.textSecondary,
      ),
    );
  }
}
