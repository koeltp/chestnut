import 'dart:convert';
import 'dart:io';

import 'package:chestnut/services/system_downloader.dart';
import 'package:chestnut/services/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('系统下载器生命周期', () {
    const channelName = 'test/system_downloader';
    late Directory tmp;
    late Map<String, Object? Function(Object? args)> handlers;
    final startArgs = <Object?>[];
    final cancelArgs = <Object?>[];
    var cleanupCount = 0;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chestnut_dl_test');
      startArgs.clear();
      cancelArgs.clear();
      cleanupCount = 0;
      handlers = {};
      handlers['cancel'] = (_) => 1;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        final handler = handlers[call.method];
        if (handler == null) throw MissingPluginException();
        switch (call.method) {
          case 'start':
            startArgs.add(call.arguments);
          case 'cancel':
            cancelArgs.add(call.arguments);
          case 'cleanup':
            cleanupCount++;
        }
        return handler(call.arguments);
      });
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), null);
      await tmp.delete(recursive: true);
    });

    UpdateService service() => UpdateService(
          downloader: SystemDownloader(channel: const MethodChannel(channelName)),
        );

    UpdateInfo info({String? sha256, int? fileSize}) => UpdateInfo(
          versionCode: 6029,
          versionName: '9.9.9',
          apkUrl: 'https://example.com/chestnut-9.9.9.apk',
          sha256: sha256,
          fileSize: fileSize,
        );

    /// 用真实字节构造一条"系统下载完成"的记录，返回待校验文件
    Future<File> seedCompletedDownload(
      UpdateService svc,
      List<int> content,
    ) async {
      final file = File('${tmp.path}${Platform.pathSeparator}seed.apk');
      await file.writeAsBytes(content);
      handlers['start'] = (_) => 4242;
      handlers['cleanup'] = (_) => null;
      handlers['query'] = (_) => {
            'status': SystemDownloadStatus.successful,
            'received': content.length,
            'total': content.length,
            'localUri': Uri.file(file.path).toString(),
            'reason': 0,
          };
      await svc.startDownload(info());
      return file;
    }

    test('startDownload：入队带缓存穿透参数，凭据落库，目录被清理', () async {
      handlers['start'] = (_) => 42;
      handlers['cleanup'] = (_) => null;
      final svc = service();
      await svc.startDownload(info());
      expect(cleanupCount, 1, reason: '下载前应清理历史残留');
      expect(startArgs, hasLength(1));
      final args = startArgs.single as Map<Object?, Object?>;
      expect(args['fileName'], 'chestnut-9.9.9.apk');
      expect((args['url'] as String).contains('t='), isTrue,
          reason: 'CDN 缓存穿透时间戳必须带上');
      expect(args['title'], '栗子记账 v9.9.9');

      // 凭据已落库：能查到进行中快照
      handlers['query'] = (_) => {
            'status': SystemDownloadStatus.running,
            'received': 10,
            'total': 100,
            'localUri': '',
            'reason': 0,
          };
      final snapshot = await svc.pollDownloadSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.status, SystemDownloadStatus.running);
      expect(snapshot.received, 10);
      expect(snapshot.total, 100);
    });

    test('startDownload：入队失败（原生异常）转可展示的 UpdateException', () async {
      handlers['cleanup'] = (_) => null;
      handlers['start'] = (_) =>
          throw PlatformException(code: 'DOWNLOAD_ERROR', message: 'boom');
      await expectLater(
        service().startDownload(info()),
        throwsA(
          isA<UpdateException>()
              .having((e) => e.message, 'message', '无法开始下载，请稍后再试'),
        ),
      );
    });

    test('pollDownloadSnapshot：无下载记录返回 null', () async {
      expect(await service().pollDownloadSnapshot(), isNull);
    });

    test('consumeDownloadedApk：完成 → 校验通过 → 返回文件并清记录', () async {
      final svc = service();
      final file = await seedCompletedDownload(svc, [1, 2, 3, 4]);
      // seedCompletedDownload 未带 sha/size 清单：校验直接放行
      final result = await svc.consumeDownloadedApk();
      expect(result.path, file.path);
      // 记录已清：再查无下载
      expect(await svc.pollDownloadSnapshot(), isNull);
    });

    test('consumeDownloadedApk：哈希不符 → 删残包清记录并抛可展示异常', () async {
      final svc = service();
      final file = await seedCompletedDownload(svc, [1, 2, 3, 4]);
      handlers['start'] = (_) => 4242;
      handlers['cleanup'] = (_) => null;
      handlers['query'] = (_) => {
            'status': SystemDownloadStatus.successful,
            'received': 4,
            'total': 4,
            'localUri': Uri.file(file.path).toString(),
            'reason': 0,
          };
      // 清单给的 sha 与文件实际内容不符
      await svc.startDownload(
        info(
          sha256:
              '0000000000000000000000000000000000000000000000000000000000000000',
        ),
      );
      await expectLater(
        svc.consumeDownloadedApk(),
        throwsA(
          isA<UpdateException>()
              .having((e) => e.message, 'message', contains('哈希校验失败')),
        ),
      );
      expect(await file.exists(), isFalse, reason: '校验失败的残包应被删除');
      expect(await svc.pollDownloadSnapshot(), isNull, reason: '记录应被清掉');
    });

    test('consumeDownloadedApk：非本地路径（content://）→ 报错清记录', () async {
      final svc = service();
      handlers['start'] = (_) => 4242;
      handlers['cleanup'] = (_) => null;
      handlers['query'] = (_) => {
            'status': SystemDownloadStatus.successful,
            'received': 4,
            'total': 4,
            'localUri': 'content://downloads/x.apk',
            'reason': 0,
          };
      await svc.startDownload(info());
      await expectLater(
        svc.consumeDownloadedApk(),
        throwsA(
          isA<UpdateException>()
              .having((e) => e.message, 'message', '无法定位下载的安装包'),
        ),
      );
      expect(await svc.pollDownloadSnapshot(), isNull);
    });

    test('cancelDownload：有记录 → 通知系统取消并清记录；无记录 → 空操作', () async {
      final svc = service();
      handlers['start'] = (_) => 4242;
      handlers['cleanup'] = (_) => null;
      handlers['query'] = (_) => {
            'status': SystemDownloadStatus.running,
            'received': 1,
            'total': 10,
            'localUri': '',
            'reason': 0,
          };
      await svc.startDownload(info());
      await svc.cancelDownload();
      expect(cancelArgs, hasLength(1));
      expect(
        ((cancelArgs.single as Map<Object?, Object?>)['id'] as num).toInt(),
        4242,
      );
      expect(await svc.pollDownloadSnapshot(), isNull);

      // 无记录时不再发系统调用
      cancelArgs.clear();
      await svc.cancelDownload();
      expect(cancelArgs, isEmpty);
    });

    test('reusePendingDownload：同版本复用，不同版本取消旧任务', () async {
      final svc = service();
      handlers['start'] = (_) => 4242;
      handlers['cleanup'] = (_) => null;
      handlers['query'] = (_) => {
            'status': SystemDownloadStatus.running,
            'received': 1,
            'total': 10,
            'localUri': '',
            'reason': 0,
          };
      await svc.startDownload(info());

      // 同版本：复用，不动系统任务
      expect(await svc.reusePendingDownload(6029), isTrue);
      expect(cancelArgs, isEmpty);

      // 不同版本（清单已变/已装更新）：取消旧任务并清记录
      expect(await svc.reusePendingDownload(6030), isFalse);
      expect(cancelArgs, hasLength(1));
      expect(await svc.pollDownloadSnapshot(), isNull);
    });
  });
}
