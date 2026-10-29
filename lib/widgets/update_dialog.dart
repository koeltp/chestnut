import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/settings/changelog_page.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';

/// 更新弹窗结果：installed = 已拉起系统安装器；goBackup = 用户选择先去备份，
/// 调用方负责跳转备份页；backgrounded = 转入后台下载（下载继续，弹窗关闭）；
/// dismissed = 忽略/取消
enum UpdateDialogResult { installed, goBackup, backgrounded, dismissed }

/// 弹出更新弹窗；弱更点遮罩关闭返回 null（等效 dismissed）
Future<UpdateDialogResult?> showUpdateDialog(
  BuildContext context,
  UpdateInfo info,
) {
  return showDialog<UpdateDialogResult>(
    context: context,
    // 强更不可点遮罩关闭；弱更随时可关——下载已交给系统 DownloadManager，
    // 关弹窗 = 转后台继续下，回来看进度/安装即可
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

  /// 进度轮询器：下载已托管给系统 DownloadManager，
  /// 弹窗只负责每 500ms 问一次系统"下到哪了"
  Timer? _pollTimer;

  UpdateInfo get _info => widget.info;

  @override
  void initState() {
    super.initState();
    _resumePendingIfNeeded();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 弹窗打开时接管后台下载：存在同版本的待续下载（上次转后台/进程被杀）
  /// 就直接进入下载态恢复进度显示；版本不一致的旧任务由服务取消清退
  Future<void> _resumePendingIfNeeded() async {
    final resumed = await _service.reusePendingDownload(_info.versionCode);
    if (!resumed || !mounted) return;
    final snapshot = await _service.pollDownloadSnapshot();
    if (!mounted) return;
    if (snapshot == null || snapshot.isActive) {
      // 还在下（或刚被接管）：直接恢复进度显示
      if (snapshot != null) {
        setState(() {
          _phase = _Phase.downloading;
          _received = snapshot.received;
          _total = snapshot.total;
        });
        _beginPolling();
      }
      return;
    }
    // 完成态/失败态不走轮询，就地收尾
    if (snapshot.isSuccessful) {
      await _finishInstall();
    } else {
      setState(() {
        _phase = _Phase.error;
        _error = '下载中断了，点"重试"接着来';
      });
    }
  }

  /// 发起下载：任务交给系统下载器，本地只记录凭据并开始轮询进度。
  /// 失败就地转错误态（可重试）
  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      // 清单一般会带大小；系统下载器入队后从查询里回填
      _total = _info.fileSize ?? -1;
      _error = null;
    });
    try {
      await _service.startDownload(_info);
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.message;
      });
      return;
    }
    if (!mounted) return;
    _beginPolling();
  }

  void _beginPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_pollOnce());
    });
  }

  /// 轮询一次系统下载状态：进行中刷新进度；完成走校验安装；
  /// 失败转错误态；记录消失（被系统清理/外部取消）回到展示态
  Future<void> _pollOnce() async {
    final snapshot = await _service.pollDownloadSnapshot();
    if (!mounted) return;
    if (snapshot == null) {
      _pollTimer?.cancel();
      setState(() => _phase = _Phase.idle);
      return;
    }
    if (snapshot.isSuccessful) {
      _pollTimer?.cancel();
      await _finishInstall();
      return;
    }
    if (snapshot.isFailed) {
      _pollTimer?.cancel();
      setState(() {
        _phase = _Phase.error;
        _error = '下载中断了，点"重试"接着来（已下载部分系统会自动续传）';
      });
      return;
    }
    setState(() {
      _received = snapshot.received;
      _total = snapshot.total;
    });
  }

  /// 下载完成 → 校验 → 安装，校验/定位失败转错误态（可重试）
  Future<void> _finishInstall() async {
    setState(() {
      // -1 哨兵 = 校验阶段：进度条转不确定态，文案切"正在校验"
      _received = -1;
      _total = -1;
    });
    try {
      final file = await _service.consumeDownloadedApk();
      final launched = await _service.installApk(file);
      if (!mounted) return;
      if (launched) {
        // 已跳到系统安装界面，更新弹窗使命完成
        Navigator.of(context).pop(UpdateDialogResult.installed);
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
    if (mounted) {
      Navigator.of(context).pop(UpdateDialogResult.dismissed);
    }
  }

  /// "取消下载"：让系统删除任务与半途文件，回到展示态
  Future<void> _cancelDownload() async {
    _pollTimer?.cancel();
    await _service.cancelDownload();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _received = 0;
      _total = -1;
    });
  }

  /// "后台下载"：关弹窗继续下（系统托管），通知栏可见进度，
  /// 下次打开更新弹窗自动恢复进度显示
  void _backgroundDownload() {
    _pollTimer?.cancel();
    Navigator.of(context).pop(UpdateDialogResult.backgrounded);
  }

  /// "去备份"：关闭弹窗，由调用方跳转备份页（备份方式由用户在页内自选）。
  /// 下载未开始时直接关；下载中关掉即转后台，互不影响
  void _goBackup() {
    _pollTimer?.cancel();
    Navigator.of(context).pop(UpdateDialogResult.goBackup);
  }

  /// 0..1 进度；总大小未知（-1）时返回 null（走不确定进度条）
  double? get _progress =>
      _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;

  /// 体积按 10^6 进制显示（MB），与 Android 系统安装器、应用商店口径一致；
  /// 若按 1024（MiB）显示，用户会看到下载 61.8、安装时变 64.8 的困惑
  String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    // 强更禁止系统返回键关闭；弱更随时可关（关 = 下载转后台）
    final canPop = !_info.forceUpdate;
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
              // 更新前备份引导：数据无价，给用户一个顺手兜底的入口
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(width: 5),
                    Text(
                      '更新前建议先备份数据',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 只在展示态给入口：下载/重试中途跳走会打断更新流程
              if (_phase == _Phase.idle) _buildFullLogLink(),
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
            // 发布时间缺失/解析失败时不显示日期段，只留版本号
            Text(
              switch (_info.publishedAtLocalText) {
                null => 'v${_info.versionName}',
                final date => 'v${_info.versionName} · $date',
              },
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

  /// 下载进度：已知总大小显示确定进度+百分比，否则不确定进度条；
  /// _received = -1 表示校验阶段，显示"正在校验"
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
          switch (value) {
            null when _received < 0 => '正在校验安装包…',
            null => '正在下载 · ${_mb(_received)} MB',
            final v => '正在下载 ${(v * 100).toStringAsFixed(0)}%'
                ' · ${_mb(_received)}/${_mb(_total)} MB',
          },
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

  /// 查看全部更新记录：跳应用内更新记录页。
  /// 先推页面再关弹窗：页面路由压在弹窗之上，弹窗随后关闭，
  /// 顺序反了会用已销毁的弹窗 context 跳转
  Widget _buildFullLogLink() {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          final nav = Navigator.of(context);
          nav.push(
            MaterialPageRoute<void>(builder: (_) => const ChangelogPage()),
          );
          nav.pop();
        },
        icon: const Icon(Icons.history, size: 16),
        label: const Text('查看全部更新记录', style: TextStyle(fontSize: 13)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// 底部按钮：随状态在 更新/重试/取消/后台下载 之间切换
  Widget _buildActions() {
    switch (_phase) {
      case _Phase.downloading:
        // 弱更：可取消（删任务回展示态）也可转后台（关弹窗继续下）；
        // 强更必须完成更新流程，不给取消、不给转后台。
        // 遮罩/返回键对强更仍然锁死
        return _info.forceUpdate
            ? _filledButton('正在下载…', enabled: false)
            : Row(
                children: [
                  Expanded(
                    child: _subtleButton(
                      '取消下载',
                      onTap: () => unawaited(_cancelDownload()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _filledButton('后台下载', onTap: _backgroundDownload),
                  ),
                ],
              );
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
        // 主按钮独占一行；次按钮行：去备份恒有，以后再说仅弱更有
        // （强更去备份关闭后下次启动仍会自动弹出，不丢提醒）
        return Column(
          children: [
            _filledButton('立即更新', onTap: _startDownload),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _subtleButton('去备份', onTap: _goBackup)),
                if (!_info.forceUpdate) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _subtleButton('以后再说', onTap: _dismiss),
                  ),
                ],
              ],
            ),
          ],
        );
    }
  }

  /// 主按钮：蓝底白字；置灰表示不可点
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
