import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/cloud_storage_provider.dart';
import '../../services/s3_compatible_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/show_toast.dart';
import '../../widgets/section_card.dart';

/// 图片云存储配置页
///
/// 用户在此接入自己的 S3 兼容对象存储（R2 / MinIO / OSS / COS 等），
/// 账单图片只上传到用户本人的存储空间，不经任何第三方服务器。
/// 「测试连接」为启用开关的前置门槛：真实上传一个测试对象再删除，
/// 通过后才允许打开「启用图片云存储」。
class CloudStoragePage extends StatefulWidget {
  const CloudStoragePage({super.key});

  @override
  State<CloudStoragePage> createState() => _CloudStoragePageState();
}

class _CloudStoragePageState extends State<CloudStoragePage> {
  late final TextEditingController _endpoint;
  late final TextEditingController _bucket;
  late final TextEditingController _accessKey;
  late final TextEditingController _secretKey;
  late final TextEditingController _region;

  /// Secret 输入框是否明文（默认打码防偷窥）
  bool _secretVisible = false;

  /// 参数语义折叠区展开状态
  bool _guideOpen = false;

  /// 测试连接进行中
  bool _testing = false;

  /// 最近一次测试结果：null 未测过 / true 通过 / false 失败
  bool? _testPassed;

  /// 失败原因（测试失败时展示）
  String? _testError;

  @override
  void initState() {
    super.initState();
    final cloud = context.read<CloudStorageProvider>();
    _endpoint = TextEditingController(text: cloud.endpoint ?? '');
    _bucket = TextEditingController(text: cloud.bucket ?? '');
    _accessKey = TextEditingController(text: cloud.accessKeyId ?? '');
    _secretKey = TextEditingController(text: cloud.secretAccessKey ?? '');
    _region = TextEditingController(text: cloud.region);
    // 已启用 = 之前测试通过过，无需重复测试即可维持开关可用
    if (cloud.enabled && cloud.isConfigured) _testPassed = true;
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _bucket.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _region.dispose();
    super.dispose();
  }

  bool get _fieldsFilled =>
      _endpoint.text.trim().isNotEmpty &&
      _bucket.text.trim().isNotEmpty &&
      _accessKey.text.trim().isNotEmpty &&
      _secretKey.text.trim().isNotEmpty;

  /// 测试连接：先持久化填写内容（避免"测过了但没保存"的假通过），
  /// 再用新配置真实 PUT + DELETE 一个测试对象
  Future<void> _testConnection() async {
    if (!_fieldsFilled) {
      showAppToast(context, '请先填写 Endpoint、桶名与两组密钥');
      return;
    }
    setState(() {
      _testing = true;
      _testError = null;
    });
    final cloud = context.read<CloudStorageProvider>();
    await cloud.saveConfig(
      endpoint: _endpoint.text,
      bucket: _bucket.text,
      accessKeyId: _accessKey.text,
      secretAccessKey: _secretKey.text,
      region: _region.text,
    );
    final client = cloud.createClient();
    if (client == null) {
      if (mounted) setState(() => _testing = false);
      return;
    }
    try {
      await client.testConnection();
      client.close();
      if (!mounted) return;
      setState(() => _testPassed = true);
    } on S3ClientException catch (e) {
      client.close();
      if (!mounted) return;
      setState(() {
        _testPassed = false;
        _testError = e.message;
      });
    } catch (e) {
      client.close();
      if (!mounted) return;
      setState(() {
        _testPassed = false;
        _testError = '连接失败：$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 打开博客上的开通教程（Cloudflare R2 的创建与密钥获取步骤）
  Future<void> _openTutorial() async {
    final uri = Uri.parse(
      'https://www.taipi.top/docs/article/栗子记账图片云存储配置教程.html',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showAppToast(context, '无法打开浏览器，请手动访问 taipi.top');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudStorageProvider>();
    // 开关放行条件：本次会话测试通过，或此前已处于启用态
    final canEnable = _testPassed == true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('图片云存储')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapSection,
          AppDimens.pagePadding,
          24,
        ),
        children: [
          _buildIntro(),
          const SizedBox(height: AppDimens.gapSection),
          _buildConfigCard(),
          const SizedBox(height: AppDimens.gapSection),
          _buildEnableCard(cloud, canEnable),
          if (cloud.isConfigured) ...[
            const SizedBox(height: AppDimens.gapSection),
            _buildUnlink(cloud),
          ],
        ],
      ),
    );
  }

  /// 顶部说明卡
  Widget _buildIntro() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '接入你自己的云存储',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '给账单附上小票、发票等凭证图片。图片只在你主动添加时上传到'
            '你自己配置的云存储空间，栗子记账不经手、不中转、不备份到'
            '任何第三方服务器。未配置时此功能完全隐藏。',
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

  /// 配置卡：四项必填 + 区域（可选）+ 参数折叠说明 + 测试连接
  Widget _buildConfigCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(
            controller: _endpoint,
            label: 'Endpoint',
            hint: '如 https://<账户ID>.r2.cloudflarestorage.com',
          ),
          const SizedBox(height: 12),
          _field(controller: _bucket, label: '桶名（Bucket）', hint: '存储桶名称'),
          const SizedBox(height: 12),
          _field(controller: _accessKey, label: 'Access Key ID', hint: '访问密钥 ID'),
          const SizedBox(height: 12),
          _field(
            controller: _secretKey,
            label: 'Secret Access Key',
            hint: '访问密钥 Secret',
            obscure: !_secretVisible,
            suffix: IconButton(
              icon: Icon(
                _secretVisible ? Icons.visibility_off : Icons.visibility,
                size: 20,
                color: AppColors.textSecondary,
              ),
              onPressed: () =>
                  setState(() => _secretVisible = !_secretVisible),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            controller: _region,
            label: '区域（可选）',
            hint: '默认 auto（R2 填 auto 即可）',
          ),
          // 参数语义折叠区：只讲标准四字段语义，开通步骤引导去博客教程
          const Divider(height: 20, color: AppColors.divider),
          InkWell(
            onTap: () => setState(() => _guideOpen = !_guideOpen),
            borderRadius: BorderRadius.circular(AppDimens.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '这些参数是什么意思？',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Icon(
                    _guideOpen
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          if (_guideOpen)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '· Endpoint：对象存储的服务地址，在服务商控制台的桶概览里'
                '可以找到（R2 为"S3 API"后面的地址）\n'
                '· 桶名：你创建的存储桶（Bucket）的名字\n'
                '· Access Key ID / Secret Access Key：用于签名验证的访问'
                '密钥对，R2 在"管理 R2 API 令牌"里创建\n'
                '· 区域：部分服务商需要填写，R2 留空即可（自动为 auto）',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 12),
          // 测试连接：真实上传一个测试对象再删掉，成功后才放行启用开关
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusControl),
                ),
              ),
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 18),
              label: Text(
                _testing ? '正在测试连接…' : '测试连接',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          if (_testPassed != null) ...[
            const SizedBox(height: 8),
            Text(
              _testPassed!
                  ? '连接成功，可以启用图片云存储了'
                  : _testError ?? '连接失败，请检查各项配置',
              style: TextStyle(
                fontSize: 12,
                color: _testPassed! ? AppColors.income : AppColors.expense,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // 开通教程外链：注册 / 建桶 / 拿密钥的完整步骤在博客文章里
          Center(
            child: TextButton(
              onPressed: _openTutorial,
              child: const Text(
                '没有云存储？查看开通教程',
                style: TextStyle(fontSize: 13, color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 启用卡：与"我的"页开关项同款样式；测试通过才放行
  Widget _buildEnableCard(CloudStorageProvider cloud, bool canEnable) {
    final enabled = cloud.enabled && cloud.isConfigured;
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            decoration: const BoxDecoration(
              color: AppColors.fill,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_upload_outlined,
              color: AppColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: AppDimens.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '启用图片云存储',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? '已启用 · ${cloud.bucket}'
                      : canEnable
                          ? '测试通过，可开启'
                          : '需先通过"测试连接"',
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
            onChanged: canEnable
                ? (v) => context.read<CloudStorageProvider>().setEnabled(v)
                : null,
          ),
        ],
      ),
    );
  }

  /// 解除绑定：清空配置并关闭启用（已存的图片记录不受影响）
  Widget _buildUnlink(CloudStorageProvider cloud) {
    return Center(
      child: TextButton(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('解除绑定'),
              content: const Text(
                '将清空云存储配置并停止图片上传。已保存的图片记录不受影响，'
                '重新绑定后可继续上传。确定解除吗？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('解除'),
                ),
              ],
            ),
          );
          if (confirmed == true && mounted) {
            await context.read<CloudStorageProvider>().clearConfig();
            if (!mounted) return;
            setState(() {
              _endpoint.clear();
              _bucket.clear();
              _accessKey.clear();
              _secretKey.clear();
              _region.text = 'auto';
              _testPassed = null;
              _testError = null;
            });
          }
        },
        style: TextButton.styleFrom(foregroundColor: AppColors.expense),
        child: const Text('解除绑定', style: TextStyle(fontSize: 13)),
      ),
    );
  }

  /// 单个输入行：上方小标签 + 输入框（统一浅灰底圆角）。
  /// 有内容时输入框尾部显示 × 清除按钮（一键清空重填）；
  /// [suffix] 为附加按钮（如 Secret 的可见性切换），排在清除按钮右侧
  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            filled: true,
            fillColor: AppColors.fill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusControl),
              borderSide: BorderSide.none,
            ),
            // 监听文本变化：有内容才显示 ×；附加按钮与 × 并排
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.isNotEmpty;
                if (!hasText && suffix == null) {
                  return const SizedBox.shrink();
                }
                final clear = !hasText
                    ? null
                    : GestureDetector(
                        onTap: controller.clear,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.cancel,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                if (suffix == null) return clear!;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [?clear, suffix],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
