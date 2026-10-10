import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/repositories/debt_note_repository.dart';
import '../models/enums.dart';
import '../pages/asset/debt_note_edit_page.dart';
import '../providers/asset_provider.dart';
import '../providers/cloud_storage_provider.dart';
import '../providers/debt_note_provider.dart';
import '../theme/app_colors.dart';
import '../utils/money_util.dart';
import '../utils/show_toast.dart';
import 'detail_widgets.dart';
import 'photo_viewer_page.dart';

/// 借条详情底部弹窗：点击明细条目中的借条时展示完整信息
///
/// 与账单详情同交互：修改（编辑该借条）/ 删除（二次确认，级联删照片
/// 并恢复关联账户余额）；借据照片 56px 横滑缩略图，点击全屏预览
Future<void> showDebtNoteDetailSheet(
  BuildContext context, {
  required DebtNote note,
}) {
  // 同步取好依赖，删除时不再跨 async gap 访问 context
  final provider = context.read<DebtNoteProvider>();
  final repo = context.read<DebtNoteRepository>();
  final cloud = context.read<CloudStorageProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => _DebtDetailBody(
      note: note,
      hostContext: context,
      provider: provider,
      repo: repo,
      cloud: cloud,
    ),
  );
}

class _DebtDetailBody extends StatefulWidget {
  const _DebtDetailBody({
    required this.note,
    required this.hostContext,
    required this.provider,
    required this.repo,
    required this.cloud,
  });

  /// 打开弹窗时的借条快照：纯静态展示面板，所有变更从本弹窗发起、
  /// 发起即先关弹窗
  final DebtNote note;

  /// 宿主页 context：弹窗 pop 后用宿主 context 压栈编辑页
  final BuildContext hostContext;
  final DebtNoteProvider provider;
  final DebtNoteRepository repo;
  final CloudStorageProvider cloud;

  @override
  State<_DebtDetailBody> createState() => _DebtDetailBodyState();
}

class _DebtDetailBodyState extends State<_DebtDetailBody> {
  /// 该借条的借据照片（流订阅：上传状态变化自动刷新）
  List<DebtNoteImage> _images = [];
  StreamSubscription<List<DebtNoteImage>>? _imageSub;

  /// imageId → 本地文件（null = 本地缺失且云端拉回失败，显示占位）
  final Map<int, File?> _localFiles = {};

  @override
  void initState() {
    super.initState();
    _imageSub = widget.repo
        .watchPhotosByNoteId(widget.note.id)
        .listen((images) {
      if (!mounted) return;
      setState(() => _images = images);
      unawaited(_ensureFiles(images));
    });
  }

  @override
  void dispose() {
    unawaited(_imageSub?.cancel());
    super.dispose();
  }

  /// 确保每张图有本地文件（本地优先，缺失按 objectKey 云端拉回）；
  /// 拉取失败缓存 null 显示占位，重开弹窗可重试
  Future<void> _ensureFiles(List<DebtNoteImage> images) async {
    for (final img in images) {
      if (_localFiles.containsKey(img.id)) continue;
      final local = File(img.localPath);
      if (await local.exists()) {
        if (mounted) setState(() => _localFiles[img.id] = local);
        continue;
      }
      final client = widget.cloud.createClient();
      if (client == null) {
        if (mounted) setState(() => _localFiles[img.id] = null);
        continue;
      }
      final file = await widget.repo.ensureLocalFile(img, client);
      if (!mounted) return;
      setState(() => _localFiles[img.id] = file);
    }
  }

  /// 全屏预览：从被点那张进入，左右滑看其余照片
  void _preview(DebtNoteImage img) {
    final paths = <String>[];
    var index = 0;
    for (final i in _images) {
      final file = _localFiles[i.id];
      if (file == null) continue;
      if (identical(i, img)) index = paths.length;
      paths.add(file.path);
    }
    if (paths.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(
          paths: paths,
          initialIndex: index,
          openHeroTag: img.localPath,
        ),
      ),
    );
  }

  /// 手动重传（"未上传"角标点击）：结果 toast，状态由流刷新
  Future<void> _reupload(DebtNoteImage img) async {
    final client = widget.cloud.createClient();
    if (client == null) {
      if (mounted) showAppToast(context, '云存储未启用，请先到"我的-图片云存储"配置');
      return;
    }
    final ok = await widget.repo.uploadOne(img, client);
    if (mounted) {
      showAppToast(context, ok ? '上传成功' : '上传失败，请检查网络后重试');
    }
  }

  /// 编辑：先关详情，再用宿主 context 进编辑页（流自动刷新列表）
  void _openEditor() {
    Navigator.of(context).pop();
    Navigator.of(widget.hostContext).push(
      MaterialPageRoute<void>(
        builder: (_) => DebtNoteEditPage(existing: widget.note),
      ),
    );
  }

  /// 删除（二次确认）：确认后先关详情再写库，列表由流自动刷新
  Future<void> _confirmDelete(BuildContext sheetContext) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: const Text('删除借条'),
        content: const Text('确定删除这条借条吗？照片一并删除，关联账户余额将同步恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    await widget.provider.deleteDebtNote(
      widget.note,
      client: widget.cloud.createClient(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLendOut = widget.note.direction == DebtDirection.lendOut;
    final isLend = isLendOut; // 借出 = 钱出去（红），借入 = 钱进来（绿）
    final amountColor = isLend ? AppColors.expense : AppColors.income;
    return SafeArea(
      child: SingleChildScrollView(
        // 边距与账单详情弹窗完全一致
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：标题 + 操作胶囊（删除红底红字提示危险操作）
            Row(
              children: [
                const Text(
                  '借条详情',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                DetailPill('修改', onTap: _openEditor),
                const SizedBox(width: 8),
                DetailPill(
                  '删除',
                  danger: true,
                  onTap: () => _confirmDelete(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DetailInfoRow(
              label: '金额',
              child: Text(
                '${isLend ? '-' : '+'}¥'
                '${MoneyUtil.centsToYuanGroupedTrimmed(widget.note.amountCents)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            // 借据照片条：56px 圆角横滑缩略图（点击全屏预览）
            if (_images.isNotEmpty) ...[
              const Divider(height: 1, color: AppColors.divider),
              DetailInfoRow(
                label: '借据',
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final img = _images[i];
                      return DetailPhotoThumb(
                        file: _localFiles[img.id],
                        uploadState: img.uploadState,
                        onTap: () => _preview(img),
                        onRetry: () => unawaited(_reupload(img)),
                      );
                    },
                  ),
                ),
              ),
            ],
            const Divider(height: 1, color: AppColors.divider),
            DetailInfoRow(
              label: '对方',
              child: Text(
                isLendOut
                    ? '借出给 ${widget.note.personName}'
                    : '向 ${widget.note.personName} 借入',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            DetailInfoRow(
              label: '借款日期',
              child: Text(
                _fmtDate(widget.note.borrowedAt),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            DetailInfoRow(
              label: '约定还款日',
              child: Text(
                widget.note.repayDueAt == null
                    ? '未约定'
                    : _fmtDate(widget.note.repayDueAt!),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  color: widget.note.repayDueAt == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            // 关联账户按 id 查名（流快照；已删除的账户显示兜底文案）
            DetailInfoRow(
              label: '关联账户',
              child: FutureBuilder<Map<int, Asset>>(
                future: context.read<AssetProvider>().assetsMapStream().first,
                builder: (context, snapshot) {
                  final id = widget.note.relatedAssetId;
                  String text = '不关联';
                  if (id != null) {
                    final match = snapshot.data?[id];
                    text = match == null ? '已删除的账户' : match.name;
                  }
                  return Text(
                    text,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      color: id == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            DetailInfoRow(
              label: '计入统计',
              child: Text(
                widget.note.includeInTotal ? '计入' : '未计入',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  color: widget.note.includeInTotal
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            // 备注：无备注不占行
            if (widget.note.note != null && widget.note.note!.isNotEmpty) ...[
              const Divider(height: 1, color: AppColors.divider),
              DetailInfoRow(
                label: '备注',
                child: Text(
                  widget.note.note!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
