import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/bill_image_repository.dart';
import 'package:chestnut/data/repositories/debt_note_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/services/photo_staging_service.dart';
import 'package:chestnut/services/s3_compatible_client.dart';

/// 图片编辑"删旧存新"替换链路测试：
/// 覆盖账单图片与借据照片的 replaceImage / replacePhoto——
/// 新记录继承 sort、旧记录/旧文件/云端对象整链清理、状态回 pending
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('BillImageRepository.replaceImage', () {
    test('替换后旧记录/旧文件/云端对象清理，新记录继承 sort 回 pending', () async {
      // 照片流转走真实文件系统：应用支持目录重定向到临时目录
      final tempDir = await Directory.systemTemp.createTemp('bill_edit_test');
      final originalProvider = PathProviderPlatform.instance;
      addTearDown(() async {
        PathProviderPlatform.instance = originalProvider;
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      PathProviderPlatform.instance = _FakePathProvider(tempDir);

      final billId = await db
          .into(db.bills)
          .insert(
            BillsCompanion.insert(
              type: BillType.expense,
              amountCents: 100,
              date: DateTime(2026, 10, 25),
            ),
          );
      final repo = BillImageRepository(db);

      // 两张图入库：验证替换第一张时继承的是原 sort 而非追加到末位。
      // 暂存传非法字节（压缩必然失败退回原图），无需真 JPEG
      final staged = [
        await PhotoStagingService(dirName: 'receipts')
            .stage(Uint8List.fromList([1, 2, 3])),
        await PhotoStagingService(dirName: 'receipts')
            .stage(Uint8List.fromList([4, 5, 6])),
      ];
      final attached = await repo.attachStagedImages(
        billId,
        DateTime(2026, 10, 25),
        staged,
      );
      expect(attached, hasLength(2));
      final target = attached[0];
      final client = _FakeS3();
      await repo.uploadImages(attached, client);

      final created = await repo.replaceImage(
        target,
        Uint8List.fromList([7, 8, 9]),
        client: client,
      );

      // 新记录：新 id、继承原 sort、按账单月份落 objectKey、状态回 pending
      expect(created, isNotNull);
      expect(created!.id, isNot(target.id));
      expect(created.sort, target.sort);
      expect(created.billId, billId);
      expect(created.uploadState, BillImageUploadState.pending);
      expect(
        created.objectKey,
        startsWith('chestnut/receipts/202610/20261025_${billId}_'),
      );
      expect(created.localPath, isNot(target.localPath));

      // 旧记录/旧本地文件/云端旧对象整链清理；新文件已落盘
      final images = await repo.getImagesByBillId(billId);
      expect(images.map((i) => i.id), [created.id, attached[1].id]);
      expect(await File(target.localPath).exists(), isFalse);
      expect(client.deletedKeys, contains(target.objectKey));
      expect(await File(created.localPath).exists(), isTrue);
    });
  });

  group('DebtNoteRepository.replacePhoto', () {
    test('替换借据照片：按借款月落目录，旧照片整链清理', () async {
      final tempDir = await Directory.systemTemp.createTemp('debt_edit_test');
      final originalProvider = PathProviderPlatform.instance;
      addTearDown(() async {
        PathProviderPlatform.instance = originalProvider;
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      PathProviderPlatform.instance = _FakePathProvider(tempDir);

      final repo = DebtNoteRepository(db);
      final noteId = await db
          .into(db.debtNotes)
          .insert(
            DebtNotesCompanion.insert(
              direction: DebtDirection.lendOut,
              personName: '老王',
              amountCents: 3000,
              borrowedAt: DateTime(2026, 11, 1),
            ),
          );

      final staged = await PhotoStagingService(dirName: 'debt_photos')
          .stage(Uint8List.fromList([1, 2, 3]));
      final attached = await repo.attachStagedPhotos(
        noteId,
        DateTime(2026, 11, 1),
        [staged],
      );
      expect(attached, hasLength(1));
      final target = attached[0];

      final client = _FakeS3();
      final created = await repo.replacePhoto(
        target,
        Uint8List.fromList([9, 9, 9]),
        client: client,
      );

      expect(created, isNotNull);
      expect(created!.id, isNot(target.id));
      expect(created.sort, target.sort);
      expect(
        created.objectKey,
        startsWith('chestnut/debt_photos/202611/20261101_${noteId}_'),
      );
      expect(created.uploadState, BillImageUploadState.pending);

      final photos = await repo.getPhotosByNoteId(noteId);
      expect(photos.map((p) => p.id), [created.id]);
      expect(await File(target.localPath).exists(), isFalse);
      expect(client.deletedKeys, contains(target.objectKey));
      expect(await File(created.localPath).exists(), isTrue);
    });
  });
}

/// path_provider 假实现：应用支持目录重定向到临时目录，
/// 供暂存/转正走真实文件系统
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);

  final Directory dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

/// S3 客户端假实现：只记录调用，不发网络请求
class _FakeS3 extends S3CompatibleClient {
  _FakeS3()
    : super(
        endpoint: 'https://fake.example.com',
        bucket: 'chestnut-test',
        accessKeyId: 'test',
        secretAccessKey: 'test',
      );

  /// 收到过的 DELETE 对象键
  final deletedKeys = <String>[];

  @override
  Future<void> putObject(
    String key,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  }) async {}

  @override
  Future<Uint8List> getObject(String key) async => Uint8List.fromList([1]);

  @override
  Future<void> deleteObject(String key) async {
    deletedKeys.add(key);
  }
}
