import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositories/debt_note_repository.dart';
import '../../models/enums.dart';
import '../../providers/asset_provider.dart';
import '../../providers/cloud_storage_provider.dart';
import '../../providers/debt_note_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/money_util.dart';
import '../../utils/show_toast.dart';
import '../../widgets/app_segmented.dart';
import '../../widgets/asset_pick_sheet.dart';
import '../../widgets/form_rows.dart';
import '../../widgets/photo_viewer_page.dart';
import '../../widgets/section_card.dart';

/// 全屏页：添加 / 编辑借条（借出 / 借入）
///
/// [existing] 为 null = 新增；非 null = 编辑（方向可改——借条无快照
/// 语义，改方向即换统计口径，聚合流实时刷新）。
/// 借据照片多张：选图即压缩暂存，保存时转正到 debt_photos/{id}/。
class DebtNoteEditPage extends StatefulWidget {
  const DebtNoteEditPage({super.key, this.existing, this.initialDirection});

  final DebtNote? existing;

  /// 新增时的方向预选：从资产分类选"借出/借入"进入时带上
  final DebtDirection? initialDirection;

  @override
  State<DebtNoteEditPage> createState() => _DebtNoteEditPageState();
}

class _DebtNoteEditPageState extends State<DebtNoteEditPage> {
  late DebtDirection _direction = widget.existing?.direction ??
      widget.initialDirection ??
      DebtDirection.lendOut;
  late final TextEditingController _person = TextEditingController(
    text: widget.existing?.personName,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : MoneyUtil.centsToYuanTrimmed(widget.existing!.amountCents),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note,
  );
  late DateTime _borrowedAt =
      widget.existing?.borrowedAt ?? DateTime.now();
  late DateTime? _repayDueAt = widget.existing?.repayDueAt;
  late int? _relatedAssetId = widget.existing?.relatedAssetId;

  /// 已入库照片（编辑态初始化时载入；删除只改本地副本，保存时统一落库）
  List<DebtNoteImage> _existingPhotos = [];

  /// 本次新选的暂存照片（保存时转正）；页面退出未保存时统一清理
  final List<String> _stagedPhotos = [];

  /// 编辑态被移除的已有照片 id（保存时统一删记录/文件/云端对象）
  final Set<int> _removedPhotoIds = {};

  /// 暂存照片是否已被保存流程消费（消费后 dispose 不再清理文件）
  bool _photoConsumed = false;

  /// 选图/压缩进行中：添加格显示转圈并防重入
  bool _adding = false;

  /// 已有照片的本地文件解析 Future（按图片缓存避免重复触发云端回源）
  final Map<int, Future<File?>> _existingFileFutures = {};

  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _loadExistingPhotos();
  }

  /// 编辑态载入已有照片列表（页面不订阅流，操作后本地快照刷新）
  Future<void> _loadExistingPhotos() async {
    final existing = widget.existing;
    if (existing == null) return;
    final photos =
        await context.read<DebtNoteProvider>().photosByNoteId(existing.id);
    if (mounted) setState(() => _existingPhotos = photos);
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    // 未保存就退出：清掉暂存照片，避免垃圾文件堆积
    if (!_photoConsumed) {
      final provider = context.read<DebtNoteProvider>();
      for (final path in _stagedPhotos) {
        provider.discardStagedPhoto(path);
      }
    }
    super.dispose();
  }

  /// 备注的统一空串归一：与数据库 nullable 口径一致（空串存 null）
  String? get _noteText {
    final text = _note.text.trim();
    return text.isEmpty ? null : text;
  }

  // ---------- 照片 ----------

  /// 添加借据照片：先选来源（拍照/相册多选），选完逐张压缩暂存
  Future<void> _pickPhotos() async {
    if (_adding) return;
    // 收起键盘：金额/备注可能持有焦点，避免选图面板弹出时键盘闪现
    FocusManager.instance.primaryFocus?.unfocus();
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
      if (!mounted) return;
      final provider = context.read<DebtNoteProvider>();
      for (final xfile in picked) {
        if (xfile == null) continue;
        final bytes = await xfile.readAsBytes();
        final path = await provider.stagePhoto(bytes);
        _stagedPhotos.add(path);
      }
      setState(() {});
    } catch (_) {
      if (mounted) showAppToast(context, '添加照片失败，请重试');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// 删除一张新暂存图：立即清临时文件
  void _removeStaged(String path) {
    setState(() => _stagedPhotos.remove(path));
    context.read<DebtNoteProvider>().discardStagedPhoto(path);
  }

  /// 删除一张已有照片：只改本地副本，记录/文件/云端对象保存时统一清
  void _removeExisting(DebtNoteImage image) {
    setState(() {
      _existingPhotos.remove(image);
      _removedPhotoIds.add(image.id);
    });
  }

  /// 全屏预览：从被点的那张进入，左右滑可看本借条其余照片
  void _preview(int index) {
    final paths = [
      ..._existingPhotos.map((e) => e.localPath),
      ..._stagedPhotos,
    ];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(paths: paths, initialIndex: index),
      ),
    );
  }

  /// 已有照片云端回源：本地优先，缓存缺失且 objectKey 可用时拉回落盘
  Future<File?> _ensureExistingFile(DebtNoteImage image) async {
    final cloud = context.read<CloudStorageProvider>();
    final repo = context.read<DebtNoteRepository>();
    final local = File(image.localPath);
    if (await local.exists()) return local;
    final client = cloud.createClient();
    if (client == null) return null;
    return repo.ensureLocalFile(image, client);
  }

  /// 手动重传（上传角标点击）：结果 toast，完成后按库里最新状态
  /// 刷新本地快照（文件已丢的记录会被仓储作废删除）
  Future<void> _reupload(DebtNoteImage image) async {
    final cloud = context.read<CloudStorageProvider>();
    final repo = context.read<DebtNoteRepository>();
    final client = cloud.createClient();
    if (client == null) {
      showAppToast(context, '云存储未启用，请先到"我的-图片云存储"配置');
      return;
    }
    _replacePhoto(image.copyWith(uploadState: BillImageUploadState.uploading));
    final ok = await repo.uploadOne(image, client);
    if (!mounted) return;
    final photos =
        await repo.getPhotosByNoteId(widget.existing!.id);
    if (!mounted) return;
    setState(() => _existingPhotos = photos);
    showAppToast(context, ok ? '上传成功' : '上传失败，请检查网络后重试');
  }

  /// 按图片 id 替换本地快照中的上传状态（改库后立即刷新角标）
  void _replacePhoto(DebtNoteImage image) {
    setState(() {
      _existingPhotos = [
        for (final p in _existingPhotos) p.id == image.id ? image : p,
      ];
    });
  }

  // ---------- 日期与关联账户 ----------

  Future<void> _pickBorrowedAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _borrowedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _borrowedAt = picked);
  }

  Future<void> _pickRepayDueAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repayDueAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 30)),
    );
    if (picked != null) setState(() => _repayDueAt = picked);
  }

  /// 选择关联账户：统一账户选择面板（与记一笔同风格，支持"不关联"）。
  /// 关联是纯参考信息（提示钱的来源/去向），不改动账户余额。
  Future<void> _pickRelatedAsset() async {
    final assets = await context.read<AssetProvider>().activeStream().first;
    if (!mounted) return;
    final result = await showAssetPickSheet(
      context,
      assets: assets,
      allowNone: true,
    );
    // 下滑关闭等取消操作返回 null，保持原选择不变
    if (result == null || !mounted) return;
    setState(() => _relatedAssetId = result.$1?.id);
  }

  /// 关联账户显示名：按 id 从资产流里查（查不到说明已归档/删除）
  Widget _relatedAssetName() {
    return FutureBuilder<List<Asset>>(
      future: context.read<AssetProvider>().activeStream().first,
      builder: (context, snapshot) {
        final id = _relatedAssetId;
        String text = '选填，钱的来源/去向';
        if (id != null) {
          final match = snapshot.data?.where((a) => a.id == id).toList();
          text = (match == null || match.isEmpty)
              ? '已删除的账户'
              : match.single.name;
        }
        return Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: id == null ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        );
      },
    );
  }

  // ---------- 保存 / 删除 ----------

  Future<void> _save() async {
    final person = _person.text.trim();
    final cents = MoneyUtil.yuanToCents(_amount.text.trim());
    if (person.isEmpty) {
      showAppToast(context, '请填写借款人姓名');
      return;
    }
    if (cents == null || cents <= 0) {
      showAppToast(context, '请输入正确的金额');
      return;
    }
    // pop 前捕获依赖：上传是异步任务，不能依赖已销毁页面的 context
    final provider = context.read<DebtNoteProvider>();
    final repo = context.read<DebtNoteRepository>();
    final cloud = context.read<CloudStorageProvider>();
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final DebtNote note;
      if (existing == null) {
        _photoConsumed = true;
        note = await provider.addDebtNote(
          direction: _direction,
          personName: person,
          amountCents: cents,
          borrowedAt: _borrowedAt,
          repayDueAt: _repayDueAt,
          note: _noteText,
          relatedAssetId: _relatedAssetId,
          includeInTotal: _includeInTotal,
          stagedPhotoPaths: List.of(_stagedPhotos),
        );
      } else {
        note = await provider.updateDebtNote(
          existing,
          personName: person,
          amountCents: cents,
          borrowedAt: _borrowedAt,
          repayDueAt: _repayDueAt,
          note: _noteText,
          relatedAssetId: _relatedAssetId,
          includeInTotal: _includeInTotal,
          removedPhotoIds: List.of(_removedPhotoIds),
          stagedPhotoPaths: List.of(_stagedPhotos),
          // 删图时同步清被删照片的云端对象（与账单同口径）
          client: cloud.createClient(),
        );
        _photoConsumed = true;
      }
      // 保存后异步上传未完成照片（新图 pending，编辑前失败/等待的旧图
      // 顺带补传）：未配云存储时跳过，pending 状态留给启动补传兜底——
      // 与账单图片完全同口径
      final client = cloud.createClient();
      if (client != null) {
        final photos = await repo.getPhotosByNoteId(note.id);
        final pending = photos
            .where((p) => p.uploadState != BillImageUploadState.done)
            .toList();
        if (pending.isNotEmpty) unawaited(repo.uploadPhotos(pending, client));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  late bool _includeInTotal = widget.existing?.includeInTotal ?? true;

  Future<void> _delete() async {
    final existing = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除借条'),
        content: Text('删除「${existing.personName}」的这条借条？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final cloud = context.read<CloudStorageProvider>();
    final provider = context.read<DebtNoteProvider>();
    await provider.deleteDebtNote(
      existing,
      client: cloud.createClient(),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final isLendOut = _direction == DebtDirection.lendOut;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑借条' : '记借条'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              // 删除仅编辑态提供
              if (_editing) ...[
                TextButton(
                  onPressed: _saving ? null : _delete,
                  child: const Text(
                    '删除',
                    style: TextStyle(color: AppColors.expense),
                  ),
                ),
                const SizedBox(width: AppDimens.gapMd),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusControl,
                      ),
                    ),
                  ),
                  child: Text(_saving ? '保存中…' : '保存借条'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, AppDimens.gapSection, 16, 24),
        children: [
          // 方向切换独立成卡：借出/借入决定全页语义
          SectionCard(
            padding: const EdgeInsets.all(AppDimens.gapMd),
            child: AppSegmented<DebtDirection>(
              options: const [
                (DebtDirection.lendOut, '借出（别人欠我）'),
                (DebtDirection.borrowIn, '借入（我欠别人）'),
              ],
              colors: const [AppColors.income, AppColors.expense],
              selected: _direction,
              onChanged: (d) => setState(() => _direction = d),
              fit: AppSegmentedFit.stretch,
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          // 基本信息：对方 / 金额 / 日期
          FormRowsCard(rows: [
            FormInputRow(
              label: isLendOut ? '借款人（对方）' : '出借人（对方）',
              controller: _person,
              hint: '姓名',
              maxLength: 20,
              textInputAction: TextInputAction.next,
            ),
            FormInputRow(
              label: '金额（元）',
              controller: _amount,
              hint: '0.00',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // 最多两位小数：金额按分入库，防输入超精度小数
              inputFormatters: MoneyUtil.amountInputFormatters,
              textInputAction: TextInputAction.next,
            ),
            FormRow(
              label: '借款日期',
              onTap: _pickBorrowedAt,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    df.format(_borrowedAt),
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            FormRow(
              label: '约定还款日期',
              onTap: _pickRepayDueAt,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _repayDueAt == null ? '选填' : df.format(_repayDueAt!),
                    style: TextStyle(
                      fontSize: 15,
                      color: _repayDueAt == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  // 有值显示 ×（一键清除），没值显示 >：两者互斥不同时出现。
                  // × 与 > 同为 22×22 盒子，切换时位置不跳
                  if (_repayDueAt != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _repayDueAt = null),
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: Icon(
                          Icons.close,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    const Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: AppDimens.gapMd),
          // 选项：关联账户 + 计入统计开关
          FormRowsCard(rows: [
            FormRow(
              label: '关联账户',
              onTap: _pickRelatedAsset,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _relatedAssetName(),
                  // 有值显示 ×（一键取消关联），没值显示 >：两者互斥。
                  // × 与 > 同为 22×22 盒子，切换时位置不跳
                  if (_relatedAssetId != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _relatedAssetId = null),
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: Icon(
                          Icons.close,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    const Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
            FormSwitchRow(
              label: isLendOut ? '计入总借出' : '计入总借入',
              subtitle: '关闭后仅台账记录，不参与净值统计',
              value: _includeInTotal,
              onChanged: (v) => setState(() => _includeInTotal = v),
            ),
          ]),
          const SizedBox(height: AppDimens.gapMd),
          // 借据照片独立一张卡（多图网格）
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '借据照片',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    // 有照片时标题旁计数（与账单图片面板同口径）
                    if (_photoCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '（$_photoCount）',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppDimens.gapSm),
                _buildPhotoArea(),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapMd),
          // 备注独立一张卡
          FormRowsCard(rows: [
            FormInputRow(label: '备注', controller: _note, hint: '选填', maxLength: 50),
          ]),
        ],
      ),
    );
  }

  /// 照片总数（已入库 + 新暂存），标题旁计数用
  int get _photoCount => _existingPhotos.length + _stagedPhotos.length;

  /// 借据照片区：已入库图 + 新暂存图混排网格，末尾「添加」格。
  /// 尺寸与账单图片面板一致：56px 方格流式换行（约一行 5 张），
  /// 已有图右上角红 × 删除，非 done 状态外缘叠上传角标（点击重传）
  Widget _buildPhotoArea() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final image in _existingPhotos) _existingThumb(image),
        for (final path in _stagedPhotos) _stagedThumb(path),
        _addPhotoCell(),
      ],
    );
  }

  /// 新暂存图缩略图：本地文件必然存在，直接渲染
  Widget _stagedThumb(String path) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () =>
              _preview(_existingPhotos.length + _stagedPhotos.indexOf(path)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _photoPlaceholder(),
            ),
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: _deleteBadge(() => _removeStaged(path)),
        ),
      ],
    );
  }

  /// 已有照片缩略图：本地优先、缺失时按 objectKey 从云端拉回；
  /// 角标口径与账单详情一致（上传中转圈、等待/失败橙点，点击重传）
  Widget _existingThumb(DebtNoteImage image) {
    return FutureBuilder<File?>(
      future: _existingFileFutures.putIfAbsent(
        image.id,
        () => _ensureExistingFile(image),
      ),
      builder: (context, snap) {
        final file = snap.data;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              // 未就绪不打开预览（等云端拉回后刷新）
              onTap: file == null
                  ? null
                  : () => _preview(_existingPhotos.indexOf(image)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: file != null
                    ? Image.file(
                        file,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _photoPlaceholder(),
                      )
                    : _photoPlaceholder(),
              ),
            ),
            Positioned(
              top: 3,
              right: 3,
              child: _deleteBadge(() => _removeExisting(image)),
            ),
            // 上传状态角标：外缘叠放，避免与删除角标重叠
            if (image.uploadState != BillImageUploadState.done)
              Positioned(right: -3, top: -3, child: _uploadBadge(image)),
          ],
        );
      },
    );
  }

  /// 「添加」格：浅灰底 + 加号（与账单图片面板同款）；选图压缩中显示转圈并禁点
  Widget _addPhotoCell() {
    return GestureDetector(
      onTap: _adding ? null : _pickPhotos,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: _adding
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

  /// 删除角标：红底圆 + 白 ×（与账单图片面板右上角删除同款）
  Widget _deleteBadge(VoidCallback onRemove) {
    return GestureDetector(
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
    );
  }

  /// 56x56 照片占位：拉取中/拉取失败/裂图共用
  Widget _photoPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.fill,
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        size: 20,
        color: AppColors.textSecondary,
      ),
    );
  }

  /// 上传状态角标：上传中转圈，等待/失败橙点；点角标手动重传
  Widget _uploadBadge(DebtNoteImage image) {
    final uploading = image.uploadState == BillImageUploadState.uploading;
    return GestureDetector(
      onTap: uploading ? null : () => _reupload(image),
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
    );
  }
}
