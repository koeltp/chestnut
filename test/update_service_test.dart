import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chestnut/services/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UpdateInfo.fromJson 清单解析', () {
    test('完整清单解析：sha256 归一小写，各字段就位', () {
      final info = UpdateInfo.fromJson(const {
        'versionCode': 6022,
        'versionName': '1.2.5',
        'apkUrl': 'https://example.com/chestnut-1.2.5.apk',
        'sha256': 'ABCDEF0123456789',
        'fileSize': 64789695,
        'forceUpdate': true,
        'releaseNotes': ['修复检查更新', '排序优化'],
        'publishedAt': '2026-10-24T06:12:05+00:00',
      });
      expect(info.versionCode, 6022);
      expect(info.versionName, '1.2.5');
      expect(info.sha256, 'abcdef0123456789');
      expect(info.fileSize, 64789695);
      expect(info.forceUpdate, isTrue);
      expect(info.releaseNotes, hasLength(2));
    });

    test('CI 产物的精简清单：无 sha/fileSize/forceUpdate 时安全缺省', () {
      final info = UpdateInfo.fromJson(const {
        'versionCode': 6020,
        'versionName': '1.2.4',
        'apkUrl': 'https://example.com/a.apk',
      });
      expect(info.sha256, isNull);
      expect(info.fileSize, isNull);
      expect(info.forceUpdate, isFalse);
      expect(info.releaseNotes, isEmpty);
    });

    test('releaseNotes 里的非字符串项被过滤而非崩溃', () {
      final info = UpdateInfo.fromJson(const {
        'versionCode': 1,
        'versionName': '1.0.0',
        'apkUrl': 'https://example.com/a.apk',
        'releaseNotes': ['ok', 42, null, ''],
      });
      expect(info.releaseNotes, ['ok', '']);
    });

    test('缺 versionCode/versionName/apkUrl 任一即抛"格式错误"', () {
      for (final broken in <Map<String, dynamic>>[
        {'versionName': '1.0.0', 'apkUrl': 'u'},
        {'versionCode': 1, 'apkUrl': 'u'},
        {'versionCode': 1, 'versionName': '1.0.0'},
        {'versionCode': 1, 'versionName': '1.0.0', 'apkUrl': ''},
      ]) {
        expect(
          () => UpdateInfo.fromJson(broken),
          throwsA(
            isA<UpdateException>().having(
              (e) => e.message,
              'message',
              '版本清单格式错误',
            ),
          ),
          reason: '清单 $broken 应判定为损坏',
        );
      }
    });
  });

  group('publishedAtLocalText 发布时间展示', () {
    test('ISO 时间转本地展示文本', () {
      const info = UpdateInfo(
        versionCode: 1,
        versionName: '1.0.0',
        apkUrl: 'u',
        publishedAt: '2026-10-24T06:12:05+00:00',
      );
      expect(info.publishedAtLocalText, matches(RegExp(r'^\d{4}-\d{2}-\d{2} ')));
    });

    test('缺失或非法值返回 null 而不是抛异常', () {
      const missing = UpdateInfo(versionCode: 1, versionName: '1', apkUrl: 'u');
      expect(missing.publishedAtLocalText, isNull);
      const bad = UpdateInfo(
        versionCode: 1,
        versionName: '1',
        apkUrl: 'u',
        publishedAt: 'not-a-date',
      );
      expect(bad.publishedAtLocalText, isNull);
    });
  });

  group('fetchLatestManifest 网络路径', () {
    test('200 + 合法 JSON → 解析出 UpdateInfo', () async {
      final body = jsonEncode({
        'versionCode': 6022,
        'versionName': '1.2.5',
        'apkUrl': 'https://example.com/a.apk',
      });
      var requestedPath = '';
      final service = UpdateService(
        client: MockClient((request) async {
          requestedPath = request.url.path;
          return http.Response(body, 200);
        }),
      );
      final info = await service.fetchLatestManifest();
      expect(info.versionCode, 6022);
      // 请求应打在固定直链上（Worker 反代域）
      expect(requestedPath, '/latest/download/latest.json');
    });

    test('连接异常 → "网络连接失败"', () async {
      final service = UpdateService(
        client: MockClient((request) async => throw Exception('boom')),
      );
      await expectLater(
        service.fetchLatestManifest(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            '网络连接失败，请稍后再试',
          ),
        ),
      );
    });

    test('HTTP 非 200 → 明确的状态码提示', () async {
      final service = UpdateService(
        client: MockClient((request) async => http.Response('no', 503)),
      );
      await expectLater(
        service.fetchLatestManifest(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            '版本服务暂不可用（HTTP 503）',
          ),
        ),
      );
    });

    test('200 但内容不是 JSON 对象 → "格式错误"', () async {
      final service = UpdateService(
        client: MockClient((request) async => http.Response('[1,2]', 200)),
      );
      await expectLater(
        service.fetchLatestManifest(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            '版本清单格式错误',
          ),
        ),
      );
    });
  });

  group('verifyApk 完整性校验', () {
    late Directory tmp;
    const bytes = [1, 2, 3, 4, 5, 6, 7, 8];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chestnut_update_test');
    });
    tearDown(() async => tmp.delete(recursive: true));

    File write(List<int> content) {
      final f = File('${tmp.path}${Platform.pathSeparator}a.apk');
      f.writeAsBytesSync(content);
      return f;
    }

    test('大小不符立即报错（不做无谓的哈希计算）', () async {
      final service = UpdateService();
      const info = UpdateInfo(
        versionCode: 1,
        versionName: '1',
        apkUrl: 'u',
        fileSize: 100,
        sha256: 'x',
      );
      await expectLater(
        service.verifyApk(write(bytes), info),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('安装包大小不符'),
          ),
        ),
      );
    });

    test('哈希不符报错，信息里带实际摘要便于排查', () async {
      final service = UpdateService();
      const info = UpdateInfo(
        versionCode: 1,
        versionName: '1',
        apkUrl: 'u',
        sha256: '0000000000000000000000000000000000000000000000000000000000000000',
      );
      await expectLater(
        service.verifyApk(write(bytes), info),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('哈希校验失败'),
          ),
        ),
      );
    });

    test('清单提供 size + sha 且全部匹配 → 通过；未提供则跳过对应校验', () async {
      final service = UpdateService();
      final file = write(bytes);
      // 用文件的真实摘要构造应匹配的清单
      final realSha =
          (await sha256.bind(file.openRead()).last).toString();
      final real = UpdateInfo(
        versionCode: 1,
        versionName: '1',
        apkUrl: 'u',
        fileSize: bytes.length,
        sha256: realSha,
      );
      await service.verifyApk(file, real);

      // 清单未给 size/sha 时不校验（空清单对任何文件都通过）
      const empty = UpdateInfo(versionCode: 1, versionName: '1', apkUrl: 'u');
      await service.verifyApk(file, empty);
    });
  });

  group('"以后再说"忽略标记', () {
    test('同版本视为已忽略，其他版本不受影响', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = UpdateService();
      await service.markIgnored(6022);
      expect(await service.isIgnored(6022), isTrue);
      expect(await service.isIgnored(6021), isFalse);
    });

    test('未记录过任何忽略时返回 false', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = UpdateService();
      expect(await service.isIgnored(1), isFalse);
    });
  });

  group('downloadApk 取消下载', () {
    test('下载中取消：抛 UpdateCancelledException，残包不残留', () async {
      // 真实本地服务端慢速吐流（首块后挂住），比 mock 更能验证
      // "关闭 client 中断在途流"这条真实链路
      final tmp = await Directory.systemTemp.createTemp('update_cancel_test');
      final prevProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var hangClosed = false;
      final sub = server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.contentLength = 16 << 20;
        request.response.add(List.filled(64 << 10, 1));
        await request.response.flush();
        // 首块之后挂住不关，模拟大包慢速下载
        while (!hangClosed) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });

      try {
        final service = UpdateService();
        final info = UpdateInfo(
          versionCode: 2,
          versionName: '9.9.9-test',
          apkUrl: 'http://127.0.0.1:${server.port}/x.apk',
        );
        final firstChunk = Completer<void>();
        final done = Completer<File>();
        unawaited(
          service.downloadApk(info, onProgress: (received, _) {
            if (received > 0 && !firstChunk.isCompleted) firstChunk.complete();
          }).then(done.complete, onError: done.completeError),
        );
        await firstChunk.future.timeout(const Duration(seconds: 5));
        service.cancelDownload();
        await expectLater(
          done.future,
          throwsA(isA<UpdateCancelledException>()),
        );
        // 下载目录里的残包已被清理
        expect(
          Directory(p.join(tmp.path, 'updates')).listSync(),
          isEmpty,
        );
      } finally {
        hangClosed = true;
        await sub.cancel();
        await server.close(force: true);
        PathProviderPlatform.instance = prevProvider;
        await tmp.delete(recursive: true);
      }
    });

    test('无进行中下载时取消是空操作', () {
      UpdateService().cancelDownload();
    });
  });
}

/// path_provider 的测试桩：downloadApk 需要临时目录落盘
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._tempPath);

  final String _tempPath;

  @override
  Future<String?> getTemporaryPath() async => _tempPath;
}
