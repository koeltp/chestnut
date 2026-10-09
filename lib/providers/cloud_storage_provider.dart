import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/s3_compatible_client.dart';

/// 图片云存储配置（用户自配的 S3 兼容对象存储）
///
/// 图片不经任何开发者服务器：用户在配置页填自己的 Endpoint / 桶 /
/// 密钥，App 直接与该存储通信。未配置或未启用时，App 内不出现任何
/// 图片入口（记一笔胶囊、列表角标、详情缩略图条全部隐藏）。
class CloudStorageProvider extends ChangeNotifier {
  CloudStorageProvider(this._prefs);

  final SharedPreferences _prefs;

  static const _kEndpoint = 'cloud_storage_endpoint';
  static const _kBucket = 'cloud_storage_bucket';
  static const _kAccessKey = 'cloud_storage_access_key';
  static const _kSecretKey = 'cloud_storage_secret_key';
  static const _kRegion = 'cloud_storage_region';
  static const _kEnabled = 'cloud_storage_enabled';

  String? get endpoint => _prefs.getString(_kEndpoint);

  String? get bucket => _prefs.getString(_kBucket);

  String? get accessKeyId => _prefs.getString(_kAccessKey);

  String? get secretAccessKey => _prefs.getString(_kSecretKey);

  /// 区域；留空按 R2 惯例取 auto
  String get region => _prefs.getString(_kRegion) ?? 'auto';

  /// 是否已启用（配置齐全且用户打开开关后，App 内才出现图片入口）
  bool get enabled => _prefs.getBool(_kEnabled) ?? false;

  /// 四项必填配置是否齐全（区域可选）
  bool get isConfigured =>
      (endpoint?.isNotEmpty ?? false) &&
      (bucket?.isNotEmpty ?? false) &&
      (accessKeyId?.isNotEmpty ?? false) &&
      (secretAccessKey?.isNotEmpty ?? false);

  /// 保存四项配置；区域为空存 auto。配置变更后要求重新测试连接，
  /// 避免带着旧配置的"已启用"状态继续上传到错误目标
  Future<void> saveConfig({
    required String endpoint,
    required String bucket,
    required String accessKeyId,
    required String secretAccessKey,
    required String region,
  }) async {
    await _prefs.setString(_kEndpoint, endpoint.trim());
    await _prefs.setString(_kBucket, bucket.trim());
    await _prefs.setString(_kAccessKey, accessKeyId.trim());
    await _prefs.setString(_kSecretKey, secretAccessKey.trim());
    await _prefs.setString(_kRegion, region.trim().isEmpty ? 'auto' : region.trim());
    await _prefs.setBool(_kEnabled, false);
    notifyListeners();
  }

  /// 切换启用开关（配置页在测试连接成功后才放行）
  Future<void> setEnabled(bool value) async {
    if (value == enabled) return;
    await _prefs.setBool(_kEnabled, value);
    notifyListeners();
  }

  /// 解除绑定：清空全部配置与启用状态
  Future<void> clearConfig() async {
    await _prefs.remove(_kEndpoint);
    await _prefs.remove(_kBucket);
    await _prefs.remove(_kAccessKey);
    await _prefs.remove(_kSecretKey);
    await _prefs.remove(_kRegion);
    await _prefs.setBool(_kEnabled, false);
    notifyListeners();
  }

  /// 按当前配置构建客户端；未配置齐全时返回 null
  S3CompatibleClient? createClient() {
    if (!isConfigured) return null;
    return S3CompatibleClient(
      endpoint: endpoint!,
      bucket: bucket!,
      accessKeyId: accessKeyId!,
      secretAccessKey: secretAccessKey!,
      region: region,
    );
  }
}
