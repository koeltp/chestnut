import 'package:flutter/material.dart';

/// 流/异步缓存 Mixin：按 key 复用 Stream 或 Future 实例。
///
/// 页面在 build 里调 [ensureSingleStream] / [ensureFuture]，避免
/// StreamBuilder 在 rebuild 时反复取消/重订阅查询（首帧全量查询被重复执行）。
///
/// 流的缓存只能做到"最近一次"：drift 查询流是单订阅的，同一个实例
/// 只能 listen 一次，哪怕上一次订阅已经 cancel，再 listen 仍会抛
/// `Bad state: Stream has already been listened to`。所以绝不能按 key
/// 无限复用流实例——条件一变（切月、切筛选）就换新流，切回来也给新流。
///
/// 使用：
/// ```dart
/// class _HomePageState extends State<HomePage> with StreamCacheMixin<HomePage> {
///   @override
///   Widget build(BuildContext context) {
///     final flowStream = ensureSingleStream(
///       'flow',
///       '${period}-${month.year}-${month.month}',
///       () => repo.watchHomeFlow(period, month),
///     );
///     return StreamBuilder(stream: flowStream, ...);
///   }
/// }
/// ```
mixin StreamCacheMixin<T extends StatefulWidget> on State<T> {
  final Map<String, dynamic> _cache = {};

  /// 单槽流缓存：一个调用点（[slot]）只保留最近一次的流。
  /// [key] 不变时返回同一实例（避免重复订阅），[key] 一变就重新建流，
  /// 旧实例直接丢弃、绝不复用——它是单订阅流，已经 listen 过就废了。
  Stream<S> ensureSingleStream<S>(
    String slot,
    String key,
    Stream<S> Function() factory,
  ) {
    final cached = _slots[slot];
    if (cached != null && cached.$1 == key && cached.$2 is Stream<S>) {
      return cached.$2 as Stream<S>;
    }
    final stream = factory();
    _slots[slot] = (key, stream);
    return stream;
  }

  /// 每个调用点最近一次的 (key, stream)
  final Map<String, (String, Stream<dynamic>)> _slots = {};

  /// 按 [key] 缓存并返回 Future：相同 key 多次调用返回同一实例，
  /// 避免每次 build 重跑 Future（如 BudgetPage 的历史数据加载）。
  /// Future 可以被多次 await，没有单订阅限制，按 key 缓存是安全的。
  Future<S> ensureFuture<S>(String key, Future<S> Function() factory) {
    final cached = _cache[key];
    if (cached is Future<S>) return cached;
    final future = factory();
    _cache[key] = future;
    return future;
  }

  /// 清除指定 key 的缓存（下次 ensure 会重新调用 factory）
  void invalidate(String key) => _cache.remove(key);

  /// 清空全部缓存（页面状态大变动时用，如切换账户）
  void invalidateAll() {
    _cache.clear();
    _slots.clear();
  }
}
