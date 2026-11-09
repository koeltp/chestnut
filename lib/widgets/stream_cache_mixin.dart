import 'package:flutter/material.dart';

/// 流/异步缓存 Mixin：按 key 复用 Stream 或 Future 实例。
///
/// 页面在 build 里调 [ensureStream] / [ensureFuture]，用 key 作为缓存键。
/// 每次 build 都会被调用，但 key 相同就返回同一实例——避免 StreamBuilder
/// 在 rebuild 时反复取消/重订阅 drift 查询（首帧全量查询被重复执行）。
///
/// 需要强制刷新时调 [invalidate] 或 [invalidateAll]。
///
/// 使用：
/// ```dart
/// class _HomePageState extends State<HomePage> with StreamCacheMixin<HomePage> {
///   @override
///   Widget build(BuildContext context) {
///     final flowStream = ensureStream(
///       'flow-${period}-${month.year}-${month.month}',
///       () => repo.watchHomeFlow(period, month),
///     );
///     return StreamBuilder(stream: flowStream, ...);
///   }
/// }
/// ```
mixin StreamCacheMixin<T extends StatefulWidget> on State<T> {
  final Map<String, dynamic> _cache = {};

  /// 按 [key] 缓存并返回 Stream：相同 key 多次调用返回同一实例，
  /// 避免每次 build 新建 Stream 导致 StreamBuilder 重订阅
  Stream<S> ensureStream<S>(String key, Stream<S> Function() factory) {
    final cached = _cache[key];
    if (cached is Stream<S>) return cached;
    final stream = factory();
    _cache[key] = stream;
    return stream;
  }

  /// 按 [key] 缓存并返回 Future：相同 key 多次调用返回同一实例，
  /// 避免每次 build 重跑 Future（如 BudgetPage 的历史数据加载）
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
  void invalidateAll() => _cache.clear();
}
