import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/app_colors.dart';

/// 更新弹窗结果：true = 已成功拉起系统安装器；其余（忽略/取消）调用方无需处理
Future<bool?> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<bool>(
    context: context,
    // 强更不可点遮罩关闭；下载中也通过内部 PopScope 防误关
    barrierDismissible: !info.forceUpdate,
    builder: (_) => _UpdateDialog(info: info),
  );
}

/// 更新流程状态：展示 → 下载中（进度）→ 失败（可重试）
enum _Phase { idle, downloading, error }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final _service = UpdateService();

  var _phase = _Phase.idle;
  var _received = 0;
  var _total = -1;
  String? _error;

  UpdateInfo get _info => widget.info;

  /// 下载 → 校验 → 安装，任一环节失败就地转错误态（可重试）
  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      // 清单一般会带大小；没有则等响应头 contentLength 回填
      _total = _info.fileSize ?? -1;
      _error = null;
    });
    try {
      final file = await _service.downloadApk(
        _info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      // 校验失败会抛 UpdateException，由下方统一 catch 转错误态
      await _service.verifyApk(file, _info);
      if (!mounted) return;
      final launched = await _service.installApk(file);
      if (!mounted) return;
      if (launched) {
        // 已跳到系统安装界面，更新弹窗使命完成
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _phase = _Phase.error;
          _error = '无法打开安装器，请在系统设置允许安装后重试';
        });
      }
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.message;
      });
    }
  }

  /// "以后再说"：记住该版本，本次启动不再自动弹出
  Future<void> _dismiss() async {
    await _service.markIgnored(_info.versionCode);
    if (mounted) Navigator.of(context).pop(false);
  }

  /// 0..1 进度；总大小未知时返回 null（走不确定进度条）
  double? get _progress =>
      _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;

  String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    // 强更或下载进行中禁止系统返回键关闭，避免更新流程半途而废
    final canPop = !_info.forceUpdate && _phase != _Phase.downloading;
    return PopScope(
      canPop: canPop,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildNotes(),
              if (_phase == _Phase.downloading) ...[
                const SizedBox(height: 16),
                _buildProgress(),
              ],
              if (_phase == _Phase.error) ...[
                const SizedBox(height: 12),
                _buildError(),
              ],
              const SizedBox(height: 18),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  /// 头部：Logo + 发现新版本 + 版本与发布日期
  Widget _buildHeader() {
    return Row(
      children: [
        Image.asset('assets/images/logo.png', width: 42, height: 42),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '发现新版本',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (_info.forceUpdate) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.expense.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '重要',
                      style: TextStyle(fontSize: 10, color: AppColors.expense),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _info.publishedAt == null
                  ? 'v${_info.versionName}'
                  : 'v${_info.versionName} · ${_info.publishedAt}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 更新内容：清单没写条目时给一句兜底文案
  Widget _buildNotes() {
    final notes = _info.releaseNotes.isEmpty
        ? const ['修复了若干问题，优化使用体验']
        : _info.releaseNotes;
    return ConstrainedBox(
      // 条目再多也不顶满屏幕：限高滚动
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7, right: 8),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        note,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 下载进度：已知总大小显示确定进度+百分比，否则不确定进度条+已下大小
  Widget _buildProgress() {
    final value = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: AppColors.fill,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value == null
              ? '正在下载 · ${_mb(_received)} MB'
              : '正在下载 ${(value * 100).toStringAsFixed(0)}%'
                  ' · ${_mb(_received)}/${_mb(_total)} MB',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 16, color: AppColors.expense),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _error ?? '下载失败，请重试',
            style: const TextStyle(fontSize: 13, color: AppColors.expense),
          ),
        ),
      ],
    );
  }

  /// 底部按钮：随状态在 忽略/更新/重试/取消 之间切换
  Widget _buildActions() {
    switch (_phase) {
      case _Phase.downloading:
        return _filledButton('正在下载…', enabled: false);
      case _Phase.error:
        return Row(
          children: [
            if (!_info.forceUpdate) ...[
              Expanded(child: _subtleButton('取消', onTap: _dismiss)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _filledButton('重试', onTap: _startDownload),
            ),
          ],
        );
      case _Phase.idle:
        if (_info.forceUpdate) {
          return _filledButton('立即更新', onTap: _startDownload);
        }
        return Row(
          children: [
            Expanded(child: _subtleButton('以后再说', onTap: _dismiss)),
            const SizedBox(width: 12),
            Expanded(
              child: _filledButton('立即更新', onTap: _startDownload),
            ),
          ],
        );
    }
  }

  /// 主按钮：蓝底白字；下载中置灰不可点
  Widget _filledButton(String text, {VoidCallback? onTap, bool enabled = true}) {
    return SizedBox(
      height: 42,
      child: FilledButton(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.fill,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// 次按钮：浅灰底深字（忽略/取消）
  Widget _subtleButton(String text, {required VoidCallback onTap}) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.fill,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
