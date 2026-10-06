import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/show_toast.dart';
import '../../widgets/help_sheet.dart';
import '../../widgets/section_card.dart';

/// 备份与恢复页
///
/// 分工：导出文件是"用户资产"（分享到微信/网盘或存到自选位置，
/// App 内不留副本）；历史备份是"系统保险"（升级/降级/导入前的
/// 自动留底，私有目录内可见可恢复）。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  /// 正在执行的备份操作（'share'/'save'/'import'），null = 空闲。
  ///
  /// 记录"谁在忙"而非单纯忙/不忙：转圈只给真正在干活的行，
  /// 其余行显示灰箭头表示被锁；非空期间全部入口禁用防并发
  String? _busyAction;

  /// 历史备份列表；null = 正在扫描。所有变更后统一走 _refresh 重扫
  List<InternalBackup>? _backups;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// 重新扫描私有目录的历史备份，扫完才更新界面。
  /// 删除/恢复后调用，杜绝缓存快照滞留导致的「删了还在」
  Future<void> _refresh() async {
    final result = await BackupService().listInternalBackups();
    if (!mounted) return;
    setState(() => _backups = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('备份与恢复'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 24),
            color: AppColors.textSecondary,
            onPressed: _showHelp,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          24,
        ),
        children: [
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _menuItem(
                  action: 'share',
                  icon: Icons.ios_share,
                  color: AppColors.primary,
                  title: '分享备份',
                  subtitle: '发送到微信/网盘等任一应用',
                  onTap: _export,
                ),
                const Divider(indent: 16, endIndent: 16),
                _menuItem(
                  action: 'save',
                  icon: Icons.download_outlined,
                  color: AppColors.income,
                  title: '保存到手机',
                  subtitle: '选位置保存，文件管理器随时可见',
                  onTap: _saveToDevice,
                ),
                const Divider(indent: 16, endIndent: 16),
                _menuItem(
                  action: 'import',
                  icon: Icons.restore_outlined,
                  color: AppColors.income,
                  title: '导入备份',
                  subtitle: '选择备份文件，覆盖恢复全部数据',
                  onTap: _import,
                ),
                const Divider(indent: 16, endIndent: 16),
                _switchItem(
                  icon: Icons.event_available_outlined,
                  color: AppColors.primary,
                  title: '每日自动备份',
                  subtitle: '自动保存最近 7 天的备份',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapSection),
          _buildHistoryCard(),
          const SizedBox(height: AppDimens.gapSection),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '备份包含全部账单、分类与预算数据。建议定期导出并保存到网盘，'
              '换机或重装时导入即可完整恢复；导入会覆盖当前数据，导入前会'
              '自动把当前数据备份一份，选错了能找回来。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个菜单项（与我的页菜单同样式）。
  ///
  /// [action] 标识本行操作：页面有操作在执行时，本行是执行者则
  /// 显示转圈，否则显示灰箭头（禁用态）；空闲时正常箭头
  Widget _menuItem({
    required String action,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final pageBusy = _busyAction != null;
    final rowBusy = _busyAction == action;
    return InkWell(
      onTap: pageBusy ? null : onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
          vertical: AppDimens.gapLg,
        ),
        child: Row(
          children: [
            Container(
              width: AppDimens.iconTile,
              height: AppDimens.iconTile,
              decoration: BoxDecoration(
                color: AppColors.tint(color),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: AppDimens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (rowBusy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.chevron_right,
                color: pageBusy
                    // 其他操作执行中：灰箭头表达"被锁住"，不转圈
                    ? AppColors.textSecondary.withValues(alpha: 0.35)
                    : AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  /// 开关型设置项：与菜单项同样式，右侧为 Switch（每日自动备份）
  Widget _switchItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    final enabled = context.watch<SettingsProvider>().autoBackupEnabled;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapLg,
      ),
      child: Row(
        children: [
          Container(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            decoration: BoxDecoration(
              color: AppColors.tint(color),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: AppDimens.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: _busyAction != null
                ? null
                : (v) => context
                      .read<SettingsProvider>()
                      .setAutoBackupEnabled(v),
          ),
        ],
      ),
    );
  }

  /// 历史备份卡：私有目录里的自动留底，可见即可恢复
  ///
  /// 降级/导入的兜底文件都在 App 私有目录，文件管理器看不到；这里
  /// 把系统留底变成显式条目，数据"消失"时用户有处可寻。
  Widget _buildHistoryCard() {
    final backups = _backups;
    return SectionCard(
      padding: EdgeInsets.zero,
      // 显式列表状态：扫描完成前占位；删除/恢复后统一 _refresh 重扫，
      // 避免缓存 Future 换绑时旧快照滞留（「删了还在」的根因）
      child: backups == null
          ? const SizedBox(height: 56)
          : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Text(
                  '历史备份',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  '以下为系统自动生成的备份，点击可恢复，长按可删除',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              if (backups.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    '暂无历史备份（升级、装回旧版或恢复数据时会自动生成）',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                for (final (i, backup) in backups.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _backupTile(backup),
                ],
            ],
        ),
    );
  }

  /// 单条历史备份：点击恢复，长按删除
  Widget _backupTile(InternalBackup backup) {
    final blocked = backup.blocked;
    final corrupted = backup.corrupted;
    final subtitle = corrupted
        ? '文件已损坏，无法恢复'
        : blocked
            ? '来自更新版本（v${backup.fileVersion}），请先升级 App 再恢复'
            // 时间精确到秒：一分钟内连续多次导入的留底也能分清先后
            : '${DateFormat('yyyy/MM/dd HH:mm:ss').format(backup.modifiedAt)} · '
            '${(backup.sizeBytes / 1024).toStringAsFixed(0)} KB';
    final enabled = !blocked && !corrupted && _busyAction == null;
    return InkWell(
      onTap: enabled ? () => _restoreFromPath(backup.path) : null,
      onLongPress: _busyAction != null ? null : () => _confirmDelete(backup),
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
          vertical: 12,
        ),
        child: Row(
          children: [
            Icon(
              _kindIcon(backup.kind),
              size: 20,
              color: blocked || corrupted
                  ? AppColors.textSecondary
                  : AppColors.primary,
            ),
            const SizedBox(width: AppDimens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kindName(backup.kind),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: blocked || corrupted
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              blocked || corrupted ? Icons.info_outline : Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(BackupKind kind) {
    switch (kind) {
      case BackupKind.upgradeBackup:
        return Icons.system_update_alt;
      case BackupKind.downgradeBackup:
        return Icons.history;
      case BackupKind.beforeRestore:
        return Icons.save_alt;
      case BackupKind.dailyBackup:
        return Icons.event_available;
    }
  }

  String _kindName(BackupKind kind) {
    switch (kind) {
      case BackupKind.upgradeBackup:
        return '升级前备份';
      case BackupKind.downgradeBackup:
        return '降级前备份';
      case BackupKind.beforeRestore:
        return '导入前备份';
      case BackupKind.dailyBackup:
        return '每日备份';
    }
  }

  /// 长按删除一份历史备份（文件越积越多时供用户手动清理）
  Future<void> _confirmDelete(InternalBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份'),
        content: Text(
          '删除后该份「${_kindName(backup.kind)}」无法找回，确定删除？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await BackupService().deleteInternalBackup(backup);
    } catch (e) {
      // 删除失败必须给提示，否则用户以为点了没反应
      _toast('删除失败：$e');
      return;
    }
    if (!mounted) return;
    await _refresh();
  }

  /// 帮助说明：底部弹出面板（图标化要点，替代系统默认弹窗）
  void _showHelp() {
    HelpSheet.show(
      context,
      title: '备份与恢复说明',
      items: [
        HelpSheetItem(
          icon: Icons.ios_share,
          title: '分享备份',
          description: '生成完整备份文件发送到微信/网盘等，App 内不留副本',
        ),
        HelpSheetItem(
          icon: Icons.download_outlined,
          title: '保存到手机',
          description: '快照存到你选的位置（如下载目录），卸载应用也不会删除',
        ),
        HelpSheetItem(
          icon: Icons.restore_outlined,
          title: '导入备份',
          description: '从备份文件恢复全部数据，会覆盖当前数据；导入前会自动把当前数据备份一份，选错了能找回来',
        ),
        HelpSheetItem(
          icon: Icons.history,
          title: '历史备份',
          description: '升级、装回旧版或导入前自动生成的保险，点击可恢复，长按可删除',
        ),
        HelpSheetItem(
          icon: Icons.event_available,
          title: '每日备份',
          description: '打开开关后，每天第一次打开应用时自动备份一次，自动保留最近 7 天',
        ),
        HelpSheetItem(
          icon: Icons.shield_outlined,
          title: '数据安全',
          description: '备份文件包含全部账单数据，请妥善保管，建议保存到网盘的私密空间',
        ),
      ],
    );
  }

  /// 导出完整快照并调起系统分享
  ///
  /// fileNameOverrides 把私有目录的英文规范文件名换成用户能看懂的
  /// 中文名（微信会话里显示、对方保存后可搜索）；私有目录文件名
  /// 保持英文前缀，供启动清理识别，两不相扰。快照不立即删除——
  /// 微信从 FileProvider 异步读取，当场删会分享失败；下次启动时
  /// 由 cleanupExportTemp 统一清理。
  Future<void> _export() async {
    setState(() => _busyAction = 'share');
    try {
      final db = context.read<AppDatabase>();
      final file = await BackupService().exportBackup(db);
      if (!mounted) return;
      final stamp = p.basenameWithoutExtension(
        file.path,
      ).replaceFirst('chestnut_export_', '');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/x-sqlite3')],
          fileNameOverrides: ['栗子记账备份_$stamp.sqlite'],
          text: '栗子记账数据备份',
        ),
      );
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  /// 快照保存到用户自选位置（SAF 存储目录选择器，默认下载目录）
  ///
  /// 与分享互补：微信等 App 接收的文件存它们的私有目录，系统文件
  /// 管理器看不到；SAF 保存的文件落在本机公开位置，卸载应用也不删。
  /// bytes 已读入内存写入目标，私有临时文件当场删除。
  Future<void> _saveToDevice() async {
    setState(() => _busyAction = 'save');
    try {
      final db = context.read<AppDatabase>();
      final source = await BackupService().exportBackup(db);
      final stamp = p.basenameWithoutExtension(
        source.path,
      ).replaceFirst('chestnut_export_', '');
      final saved = await FilePicker.saveFile(
        dialogTitle: '保存备份',
        fileName: '栗子记账备份_$stamp.sqlite',
        bytes: await source.readAsBytes(),
        type: FileType.any,
      );
      // 临时文件用完即弃：保存成功/取消都不留私有副本
      if (await source.exists()) await source.delete();
      if (!mounted) return;
      // file_picker 13 的 saveFile 返回 Uri，转字符串后解析
      _toast(
        saved == null ? '已取消保存' : _friendlySavePath(saved.toString()),
      );
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  /// 把 SAF 返回的 content 内部地址翻译成小白能看懂的位置
  ///
  /// 系统保存器返回的是形如 content://…/document/primary%3ADownload%
  /// 2F文件名 的内部地址，不能直接展示；主存储（primary）部分可解析
  /// 出真实目录，翻译成「下载/文件名」这样的人话；SD 卡、第三方文档
  /// 应用等解析不出，退回通用提示。
  String _friendlySavePath(String saved) {
    final i = saved.indexOf('document/');
    if (i < 0) return '已保存到所选位置';
    final raw = Uri.decodeFull(saved.substring(i + 'document/'.length));
    final fileName = p.basename(raw);

    // raw: 前缀 = 厂商直接给真实路径（如 vivo 下载提供器）
    if (raw.startsWith('raw:')) {
      final realPath = raw.substring('raw:'.length);
      if (realPath.startsWith('/storage/emulated/0/Download/')) {
        return '已保存到 下载/${p.basename(realPath)}';
      }
      return '已保存到 ${p.basename(realPath)}（所选位置）';
    }

    // 主存储：primary:Download/xxx → /storage/emulated/0/Download/xxx
    if (!raw.startsWith('primary:')) return '已保存到所选位置';
    final realPath = raw.replaceFirst('primary:', '/storage/emulated/0/');
    const dirNames = {
      '/storage/emulated/0/Download': '下载',
      '/storage/emulated/0/Documents': '文档',
      '/storage/emulated/0/DCIM': '相册',
      '/storage/emulated/0/Pictures': '图片',
    };
    for (final entry in dirNames.entries) {
      if (realPath.startsWith('${entry.key}/')) {
        return '已保存到 ${entry.value}/$fileName';
      }
    }
    // 其它主存储位置：去掉存储根前缀，显示「目录/文件名」
    return '已保存到 '
        '${p.dirname(realPath).replaceFirst('/storage/emulated/0/', '')}'
        '/$fileName';
  }

  /// 选择备份文件后进入公共恢复流程
  ///
  /// 不按扩展名过滤：Android 各 ROM 对 sqlite 这类未知扩展的 MIME
  /// 归类不一，custom 过滤既滤不掉无关文件、还可能把备份文件一起
  /// 藏掉；选到不合规文件由预检兜底提示。
  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null || !mounted) return; // 用户取消选择
    await _restoreFromPath(path);
  }

  /// 公共恢复流程：预检 → 强确认 → 暂存待恢复 → 退出应用
  ///
  /// 外部导入与"历史备份"列表点击共用（内部文件无需文件选择器）
  Future<void> _restoreFromPath(String path) async {
    setState(() => _busyAction = 'import');
    String? error;
    try {
      error = await BackupService().validateBackup(path);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
    if (!mounted) return;
    if (error != null) {
      _toast(error);
      return;
    }

    // 强确认：覆盖式操作，用户必须明确知晓后果
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入备份'),
        content: const Text(
          '导入将覆盖当前全部账单、分类与预算数据。\n\n'
          '· 导入后应用会自动关闭，重新打开即生效\n'
          '· 导入前会自动把当前数据备份一份，选错了可找回',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('确定导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyAction = 'import');
    try {
      await BackupService().stageRestore(path);
      if (!mounted) return;
      // 退出应用，下次启动在数据库打开前完成文件替换
      _toast('导入成功，应用即将关闭，重新打开后生效');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await SystemNavigator.pop();
      exit(0);
    } catch (e) {
      _toast('导入失败：$e');
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _toast(String message) {
    // 带路径/结果说明的提示信息量大，8 秒保证读得完
    showAppToast(context, message, duration: const Duration(seconds: 8));
  }
}
