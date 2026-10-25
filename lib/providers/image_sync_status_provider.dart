import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/bill_image_repository.dart';
import '../data/repositories/debt_note_repository.dart';

/// 两类图片的同步计数快照（watch 流的最新值）
class ImageSyncCounts {
  const ImageSyncCounts({
    this.receiptTotal = 0,
    this.receiptPending = 0,
    this.debtTotal = 0,
    this.debtPending = 0,
  });

  /// 小票凭证：总数 / 未同步数
  final int receiptTotal;
  final int receiptPending;

  /// 借据照片：总数 / 未同步数
  final int debtTotal;
  final int debtPending;

  /// 未同步总数：我的页入口与云存储页顶栏的红点角标用
  int get pendingTotal => receiptPending + debtPending;

  /// 图片总量：同步页展示规模用
  int get total => receiptTotal + debtTotal;
}

/// 图片云同步状态：聚合小票与借据两表的计数 watch 流，
/// 数据库图片行任何变化（上传成功/失败/增删）自动重新发射。
/// 同步页统计、云存储页顶栏角标、我的页入口红点三处共用
class ImageSyncStatusProvider extends ChangeNotifier {
  ImageSyncStatusProvider(
    BillImageRepository billImages,
    DebtNoteRepository debtNotes,
  ) {
    // drift 的 watch 监听即发当前值，两路各自到达后刷新
    _subs.add(
      billImages.watchSyncCount().listen((v) {
        _receipt = v;
        notifyListeners();
      }),
    );
    _subs.add(
      debtNotes.watchSyncCount().listen((v) {
        _debt = v;
        notifyListeners();
      }),
    );
  }

  final _subs = <StreamSubscription<({int total, int pending})>>[];

  var _receipt = const (total: 0, pending: 0);
  var _debt = const (total: 0, pending: 0);

  ImageSyncCounts get counts => ImageSyncCounts(
        receiptTotal: _receipt.total,
        receiptPending: _receipt.pending,
        debtTotal: _debt.total,
        debtPending: _debt.pending,
      );

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}
