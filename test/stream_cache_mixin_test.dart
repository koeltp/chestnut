import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chestnut/widgets/stream_cache_mixin.dart';

/// StreamCacheMixin 单元测试：在 testWidgets 环境下直接操作 mixin 实例。
///
/// 复用 StatefulBuilder 的 State 测试方法：把 mixin 混入一个简单的
/// Widget State，通过 GlobalKey 拿到实例后验证缓存行为。
void main() {
  testWidgets('ensureStream: 相同 key 多次调用返回同一 Stream 实例', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(
      home: _CacheTest(key: key),
    ));
    await tester.pumpAndSettle();

    var factoryCalls = 0;
    Stream<int> factory() {
      factoryCalls++;
      return Stream.value(42);
    }

    final state = key.currentState!;
    final a = state.ensureStream<int>('x', factory);
    final b = state.ensureStream<int>('x', factory);
    final c = state.ensureStream<int>('x', factory);

    expect(a, same(b));
    expect(b, same(c));
    expect(factoryCalls, 1);
  });

  testWidgets('ensureStream: 不同 key 返回不同 Stream 实例', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(
      home: _CacheTest(key: key),
    ));
    await tester.pumpAndSettle();

    var factoryCalls = 0;
    Stream<int> factory() {
      factoryCalls++;
      return Stream.value(42);
    }

    final state = key.currentState!;
    final a = state.ensureStream<int>('a', factory);
    final b = state.ensureStream<int>('b', factory);

    expect(a, isNot(same(b)));
    expect(factoryCalls, 2);
  });

  testWidgets('ensureFuture: 相同 key 多次调用返回同一 Future 实例', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(
      home: _CacheTest(key: key),
    ));
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

  testWidgets('invalidate 清除指定 key，invalidateAll 清空全部', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(
      home: _CacheTest(key: key),
    ));
    await tester.pumpAndSettle();

    var factoryCalls = 0;
    Stream<int> factory() {
      factoryCalls++;
      return Stream.value(1);
    }

    final state = key.currentState!;
    state.ensureStream<int>('keep', factory);
    state.ensureStream<int>('remove', factory);
    expect(factoryCalls, 2);

    // invalidate 单 key：只有被清的那个重建
    state.invalidate('remove');
    state.ensureStream<int>('keep', factory);
    state.ensureStream<int>('remove', factory);
    expect(factoryCalls, 3);

    // invalidateAll 全清
    state.invalidateAll();
    state.ensureStream<int>('keep', factory);
    state.ensureStream<int>('remove', factory);
    expect(factoryCalls, 5);
  });

  testWidgets('invalidate 不存在的 key 不报错', (tester) async {
    final key = GlobalKey<_CacheTestState>();
    await tester.pumpWidget(MaterialApp(
      home: _CacheTest(key: key),
    ));
    await tester.pumpAndSettle();
    expect(() => key.currentState!.invalidate('nonexistent'), returnsNormally);
  });
}

class _CacheTest extends StatefulWidget {
  const _CacheTest({super.key});

  @override
  State<_CacheTest> createState() => _CacheTestState();
}

class _CacheTestState extends State<_CacheTest> with StreamCacheMixin<_CacheTest> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
