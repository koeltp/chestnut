import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/bill_image_repository.dart';
import '../../data/repositories/debt_note_repository.dart';
import '../../providers/cloud_storage_provider.dart';
import '../../providers/image_sync_status_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/show_toast.dart';
import '../../widgets/section_card.dart';

/// 图片同步状态页：小票凭证与借据照片的上传统计 + 手动补传入口。
/// 上传失败会留待下次启动自动补传，本页提供随时手动兜底；
/// 计数走 watch 流，上传状态一变数字即时刷新
class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key});

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  bool _uploading = false;
  var _done = 0;
  var _total = 0;

  Future<void> _startUpload() async {
    final client = context.read<CloudStorageProvider>().createClient();
    if (client == null) {
      showAppToast(context, '云存储未启用，请先配置并启用');
      return;
    }
    final status = context.read<ImageSyncStatusProvider>().counts;
    setState(() {
      _uploading = true;
      _done = 0;
      _total = status.pendingTotal;
    });
    final billRepo = context.read<BillImageRepository>();
    final debtRepo = context.read<DebtNoteRepository>();
    final billPending = status.receiptPending;
    var success = 0;
    try {
      success += await billRepo.uploadPending(
        client,
        onProgress: (done, _) {
          if (mounted) setState(() => _done = done);
        },
      );
      // 借据阶段的进度叠加小票阶段的完成数，合计进度连续
      success += await debtRepo.uploadPending(
        client,
        onProgress: (done, _) {
          if (mounted) setState(() => _done = billPending + done);
        },
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
    if (!mounted) return;
    final failed = _total - success;
    showAppToast(
      context,
      failed <= 0
          ? '补传完成 · 共 $success 张'
          : '补传完成 · 成功 $success 张，失败 $failed 张',
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<ImageSyncStatusProvider>().counts;
    final cloudEnabled = context.watch<CloudStorageProvider>().enabled;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('同步状态')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          24,
        ),
        children: [
          if (!cloudEnabled)
            const _DisabledHint()
          else ...[
            _buildStatsCard(status),
            const SizedBox(height: AppDimens.gapSection),
            _buildUploadButton(status.pendingTotal),
            const SizedBox(height: 14),
            const Text(
              '上传失败会留待下次启动或切回应用时自动补传，'
              '这里可随时手动兜底；单张失败也可在对应详情里点击重传',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsCard(ImageSyncCounts status) {
    final pending = status.pendingTotal;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '图片云同步',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pending == 0
                ? '全部图片已同步 · 共 ${status.total} 张'
                : '未同步 $pending 张（共 ${status.total} 张）',
            style: TextStyle(
              fontSize: 13,
              color: pending == 0 ? AppColors.textSecondary : AppColors.expense,
            ),
          ),
          const SizedBox(height: 10),
          _buildStatRow('小票凭证', status.receiptTotal, status.receiptPending),
          const SizedBox(height: 6),
          _buildStatRow('借据照片', status.debtTotal, status.debtPending),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int total, int pending) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '$total 张 · 未同步 $pending 张',
            style: TextStyle(
              fontSize: 13,
              color: pending > 0 ? AppColors.expense : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadButton(int pending) {
    final Widget child;
    if (_uploading) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('补传中 $_done/$_total'),
        ],
      );
    } else if (pending == 0) {
      child = const Text('全部已同步，无需补传');
    } else {
      child = Text('立即补传（$pending 张）');
    }
    return SizedBox(
      height: 44,
      child: FilledButton(
        // 补传中防重入；无未同步时不可点
        onPressed: _uploading || pending == 0 ? null : _startUpload,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 未启用云存储时的占位提示（入口已隐藏，此为直接访问的兜底）
class _DisabledHint extends StatelessWidget {
  const _DisabledHint();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '未启用图片云存储',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '先在图片云存储页配置并启用你的云存储，'
            '启用后小票凭证与借据照片会自动上传同步',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
