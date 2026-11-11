import 'package:chestnut/theme/app_colors.dart';
import 'package:chestnut/widgets/empty_state_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// EmptyStateCard 组件的 Widget 冒烟测试
///
/// 三种预设构造函数 + 自定义构造函数都应正确渲染图标、主副文案、
/// 以及"带/不带 action 按钮"两种形态
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    ),
    home: Scaffold(body: child),
  );

  testWidgets('.none 构造函数：渲染主副文案', (tester) async {
    await tester.pumpWidget(wrap(const EmptyStateCard.none()));
    expect(find.text('这个月还没有记账'), findsOneWidget);
    expect(find.text('点击下方 + 记下第一笔吧'), findsOneWidget);
    // 不应有 OutlinedButton（none 不带 action）
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('.none 支持自定义 periodLabel', (tester) async {
    await tester.pumpWidget(
      wrap(const EmptyStateCard.none(periodLabel: '2025 年还没有记账')),
    );
    expect(find.text('2025 年还没有记账'), findsOneWidget);
  });

  testWidgets('.filtered 构造函数：渲染清除筛选按钮', (tester) async {
    var cleared = false;
    await tester.pumpWidget(
      wrap(EmptyStateCard.filtered(onClear: () => cleared = true)),
    );
    expect(find.text('当前筛选条件下暂无账单'), findsOneWidget);
    expect(find.text('清除筛选'), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);

    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
  });

  testWidgets('.customRange 构造函数：渲染调整区间按钮', (tester) async {
    var adjusted = false;
    await tester.pumpWidget(
      wrap(EmptyStateCard.customRange(onAdjust: () => adjusted = true)),
    );
    expect(find.text('该范围内暂无账单'), findsOneWidget);
    expect(find.text('调整区间'), findsOneWidget);
    expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);

    await tester.tap(find.text('调整区间'));
    await tester.pumpAndSettle();
    expect(adjusted, isTrue);
  });

  testWidgets('.custom 构造函数：完全自定义内容', (tester) async {
    var actionCalled = false;
    await tester.pumpWidget(
      wrap(
        EmptyStateCard.custom(
          icon: Icons.cloud_off_outlined,
          title: '网络不可用',
          subtitle: '检查网络连接后重试',
          actionLabel: '重试',
          onAction: () => actionCalled = true,
        ),
      ),
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('网络不可用'), findsOneWidget);
    expect(find.text('检查网络连接后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(actionCalled, isTrue);
  });

  testWidgets('.custom 不带 action 时不渲染按钮', (tester) async {
    await tester.pumpWidget(
      wrap(
        EmptyStateCard.custom(
          icon: Icons.cloud_off_outlined,
          title: '网络不可用',
          subtitle: '请稍后再试',
        ),
      ),
    );
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
