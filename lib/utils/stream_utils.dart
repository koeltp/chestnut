import 'dart:async';

/// 合并多条流：等所有流都至少发射一次后，任一流发射都带着全部
/// 最新值重新发射。结果列表下标与入参顺序一一对应
///
/// 个人记账 App 的数据量下，视图组装统一走本工具而不引入 rxdart。
/// 入参不得为空流列表（空列表直接发射一次空结果）。
Stream<List<Object?>> combineLatest(List<Stream<Object?>> streams) {
  final controller = StreamController<List<Object?>>();
  final values = List<Object?>.filled(streams.length, null);
  final ready = List<bool>.filled(streams.length, false);
  final subs = <StreamSubscription<Object?>>[];

  void forwardPause() {
    for (final s in subs) {
      s.pause();
    }
  }

  void forwardResume() {
    for (final s in subs) {
      s.resume();
    }
  }

  controller
    ..onListen = () {
      if (streams.isEmpty) {
        controller.add(const []);
        return;
      }
      for (var i = 0; i < streams.length; i++) {
        final index = i;
        subs.add(
          streams[i].listen(
            (value) {
              values[index] = value;
              ready[index] = true;
              if (ready.every((e) => e)) {
                controller.add(List<Object?>.unmodifiable(values));
              }
            },
            onError: controller.addError,
          ),
        );
      }
    }
    ..onPause = forwardPause
    ..onResume = forwardResume
    ..onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    };
  return controller.stream;
}

/// 流的最新切换扩展
extension SwitchLatest<T> on Stream<T> {
  /// 上游每发射一次就换订新的内部流，旧内部流被取消；下游只收到
  /// 最新内部流的事件。用于「图片 id 流随账单列表变化而换查询」
  /// 这类有依赖关系的串联
  Stream<R> switchMapLatest<R>(Stream<R> Function(T event) convert) {
    final controller = StreamController<R>();
    StreamSubscription<T>? sourceSub;
    StreamSubscription<R>? innerSub;

    // 代次标记：旧内部流的 cancel 是异步的，可能在生效前再漏一个
    // 事件出来，用代次丢弃过期事件
    var generation = 0;

    controller
      ..onListen = () {
        sourceSub = listen(
          (event) {
            final current = ++generation;
            unawaited(innerSub?.cancel());
            innerSub = convert(event).listen(
              (value) {
                if (current == generation) controller.add(value);
              },
              onError: (Object error, StackTrace stack) {
                if (current == generation) controller.addError(error, stack);
              },
            );
          },
          onError: controller.addError,
          onDone: () async {
            await innerSub?.cancel();
            await controller.close();
          },
        );
      }
      ..onPause = () {
        sourceSub?.pause();
        innerSub?.pause();
      }
      ..onResume = () {
        sourceSub?.resume();
        innerSub?.resume();
      }
      ..onCancel = () async {
        await innerSub?.cancel();
        await sourceSub?.cancel();
      };
    return controller.stream;
  }
}
