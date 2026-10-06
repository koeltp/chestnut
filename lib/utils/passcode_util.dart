import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PIN 与安全答案的哈希工具：随机盐 + SHA-256
///
/// 本地隐私锁的威胁模型是"防他人随手打开手机"，而非防本地逆向；
/// 加盐哈希存储明文不可逆，配合安全问题兜底已足够，无需引入 Keystore
class PasscodeUtil {
  PasscodeUtil._();

  /// 生成 16 字节随机盐（hex 字符串）
  static String generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// SHA-256(盐 + 原文)，返回 hex 字符串
  static String hash(String salt, String plain) {
    return sha256.convert(utf8.encode('$salt$plain')).toString();
  }

  /// 校验原文是否匹配已存哈希
  static bool verify(String salt, String plain, String expectedHash) {
    return hash(salt, plain) == expectedHash;
  }
}
