import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chestnut/widgets/stream_cache_mixin.dart';

/// StreamCacheMixin 单元测试：在 testWidgets 环境下直接操作 mixin 实例。
///
/// 复用 StatefulBuilder 的 State 测试方法：把 mixin 混入一个简单的
/// Widget State，通过 GlobalKey 拿到实例后验证缓存行为。
///
/// 重点覆盖单订阅约束：drift 查询流只能 listen 一次，任何"复用已订阅
/// 实例"的行为都会让页面抛 Bad state: Stream has already been listened to。
void main() {
  testWidgets('相同 slot + key 返回同一 Stream 实例', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(home: _CacheTest(key: key)));
    await tester.pumpAndSettle();

    var factoryCalls = 0;
    Stream<int> factory() {
      factoryCalls++;
      return Stream.value(42);
    }

    final state = key.currentState!;
    final a = state.ensureSingleStream<int>('bills', 'x', factory);
    final b = state.ensureSingleStream<int>('bills', 'x', factory);
    final c = state.ensureSingleStream<int>('bills', 'x', factory);

    expect(a, same(b));
    expect(b, same(c));
    expect(factoryCalls, 1);
  });

  testWidgets('不同 key 返回不同 Stream 实例', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(home: _CacheTest(key: key)));
    await tester.pumpAndSettle();

    var factoryCalls = 0;
    Stream<int> factory() {
      factoryCalls++;
      return Stream.value(42);
    }

    final state = key.currentState!;
    final a = state.ensureSingleStream<int>('bills', '2026-11', factory);
    final b = state.ensureSingleStream<int>('bills', '2024-07', factory);

    expect(a, isNot(same(b)));
    expect(factoryCalls, 2);
  });

  testWidgets('切走再切回同一 key：必须给新实例（旧实例已订阅过）', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(home: _CacheTest(key: key)));
    await tester.pumpAndSettle();

    final state = key.currentState!;
    final first = state.ensureSingleStream<int>(
      'bills',
      '2024-07',
      () => Stream.value(1),
    );
    state.ensureSingleStream<int>('bills', '2024-08', () => Stream.value(2));
    final back = state.ensureSingleStream<int>(
      'bills',
      '2024-07',
      () => Stream.value(3),
    );

    // drift 流是单订阅的：复用 first 会让新订阅抛
    // Bad state: Stream has already been listened to
    expect(back, isNot(same(first)));
  });

  testWidgets('不同 slot 互不影响', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(home: _CacheTest(key: key)));
    await tester.pumpAndSettle();

    final state = key.currentState!;
    final bills = state.ensureSingleStream<int>(
      'bills',
      'k',
      () => Stream.value(1),
    );
    final compare = state.ensureSingleStream<int>(
      'compare',
      'k',
      () => Stream.value(2),
    );

    expect(bills, isNot(same(compare)));
  });

  testWidgets('ensureFuture: 相同 key 多次调用返回同一 Future 实例', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(home: _CacheTest(key: key)));
    await tester.pumpAndSettle();

    var factoryCalls = 0;
    Future<int> factory() async {
      factoryCalls++;
      return 42;
    }

    final state = key.currentState!;
    final a = state.ensureFuture<int>('x', factory);
    final b = state.ensureFuture<int>('x', factory);

    expect(a, same(b));
    expect(factoryCalls, 1);
    expect(await a, 42);
  });

  testWidgets('invalidateAll 同时清空 Future 与流槽位', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(home: _CacheTest(key: key)));
    await tester.pumpAndSettle();

    var streamCalls = 0;
    Stream<int> streamFactory() {
      streamCalls++;
      return Stream.value(1);
    }

    var futureCalls = 0;
    Future<int> futureFactory() async {
      futureCalls++;
      return 1;
    }

    final state = key.currentState!;
    state.ensureSingleStream<int>('bills', 'k', streamFactory);
    await state.ensureFuture<int>('tags', futureFactory);
    expect(streamCalls, 1);
    expect(futureCalls, 1);

    state.invalidateAll();
    state.ensureSingleStream<int>('bills', 'k', streamFactory);
    await state.ensureFuture<int>('tags', futureFactory);
    expect(streamCalls, 2);
    expect(futureCalls, 2);
  });

  testWidgets('invalidate 不存在的 key 不报错', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(home: _CacheTest(key: key)));
    await tester.pumpAndSettle();
    expect(() => key.currentState!.invalidate('nonexistent'), returnsNormally);
  });
}

class _CacheTest extends StatefulWidget {
  const _CacheTest({super.key});

  @override
  State<_CacheTest> createState() => _CacheTestState();
}

class _CacheTestState extends State<_CacheTest>
    with StreamCacheMixin<_CacheTest> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
