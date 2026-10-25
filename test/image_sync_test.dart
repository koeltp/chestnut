import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/bill_image_repository.dart';
import 'package:chestnut/data/repositories/debt_note_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/services/s3_compatible_client.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  S3CompatibleClient dummyClient() => S3CompatibleClient(
        endpoint: 'https://example.invalid',
        bucket: 'test',
        accessKeyId: 'test',
        secretAccessKey: 'test',
      );

  group('BillImageRepository.watchSyncCount', () {
    test('计数随图片行的增改自动刷新（总数 + 未同步数）', () async {
      final billId = await db
          .into(db.bills)
          .insert(BillsCompanion.insert(
            type: BillType.expense,
            amountCents: 100,
            date: DateTime(2026, 10, 25),
          ));
      final repo = BillImageRepository(db);

      Future<int> insertImage(BillImageUploadState state) =>
          db.into(db.billImages).insert(BillImagesCompanion.insert(
                billId: billId,
                objectKey: 'chestnut/receipts/$billId-x-${state.index}.jpg',
                localPath: '/tmp/none.jpg',
                uploadState: state,
              ));

      // 初值：监听即发当前快照
      final first = await repo.watchSyncCount().first;
      expect(first, (total: 0, pending: 0));

      await insertImage(BillImageUploadState.pending);
      await insertImage(BillImageUploadState.pending);
      await insertImage(BillImageUploadState.done);

      final after = await repo.watchSyncCount().first;
      expect(after, (total: 3, pending: 2));

      // 状态变化后计数跟随
      final doneRow = await db.select(db.billImages).get();
      await (db.update(db.billImages)
            ..where((t) => t.id.equals(doneRow.first.id)))
          .write(BillImagesCompanion(
        uploadState: Value(BillImageUploadState.done),
      ));
      final updated = await repo.watchSyncCount().first;
      expect(updated, (total: 3, pending: 1));
    });
  });

  group('DebtNoteRepository.watchSyncCount', () {
    test('借据照片计数正确（总数 + 未同步数）', () async {
      final noteId = await db
          .into(db.debtNotes)
          .insert(DebtNotesCompanion.insert(
            direction: DebtDirection.lendOut,
            personName: '张三',
            amountCents: 50000,
            borrowedAt: DateTime(2026, 10, 25),
          ));
      final repo = DebtNoteRepository(db);

      await db.into(db.debtNoteImages).insert(DebtNoteImagesCompanion.insert(
            noteId: noteId,
            objectKey: 'chestnut/debt_photos/$noteId-1.jpg',
            localPath: '/tmp/none.jpg',
            uploadState: BillImageUploadState.pending,
          ));
      await db.into(db.debtNoteImages).insert(DebtNoteImagesCompanion.insert(
            noteId: noteId,
            objectKey: 'chestnut/debt_photos/$noteId-2.jpg',
            localPath: '/tmp/none.jpg',
            uploadState: BillImageUploadState.done,
          ));

      final count = await repo.watchSyncCount().first;
      expect(count, (total: 2, pending: 1));
    });
  });

  group('uploadPending 进度回调', () {
    test('每张待传图片回调一次 (done, total)，本地文件缺失时上传失败并清理', () async {
      final billId = await db
          .into(db.bills)
          .insert(BillsCompanion.insert(
            type: BillType.expense,
            amountCents: 100,
            date: DateTime(2026, 10, 25),
          ));
      final repo = BillImageRepository(db);
      for (var i = 0; i < 2; i++) {
        await db.into(db.billImages).insert(BillImagesCompanion.insert(
              billId: billId,
              objectKey: 'chestnut/receipts/test-$i.jpg',
              localPath: '/tmp/missing-$i.jpg',
              uploadState: BillImageUploadState.pending,
            ));
      }

      final progress = <(int, int)>[];
      final success = await repo.uploadPending(
        dummyClient(),
        onProgress: (done, total) => progress.add((done, total)),
      );

      // 本地文件不存在：全部失败，但进度照常逐步推进
      expect(success, 0);
      expect(progress, [(1, 2), (2, 2)]);
      // 缺文件的记录已被清理，未同步计数归零
      final count = await repo.watchSyncCount().first;
      expect(count, (total: 0, pending: 0));
    });

    test('无待传图片时不回调', () async {
      final repo = BillImageRepository(db);
      var called = false;
      final success = await repo.uploadPending(
        dummyClient(),
        onProgress: (_, _) => called = true,
      );
      expect(success, 0);
      expect(called, isFalse);
    });
  });
}
