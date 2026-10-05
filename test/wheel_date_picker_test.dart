import 'package:chestnut/pages/add_bill/wheel_date_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 日期/时间滚轮回归测试（循环跨月/跨年模型）
void main() {
  /// 弹出日期滚轮（每列独立，按 key 查找）
  Future<void> pumpDatePicker(WidgetTester tester, DateTime initial) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: WheelDatePicker(
              initial: initial,
              initialMinute: 8 * 60 + 30,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 读取三列选中项文本，拼接为"YYYY年M月D日"（用于断言跨月结果）
  String datePillText(WidgetTester tester) {
    String selText(String key) =>
        ((find.byKey(ValueKey(key)).evaluate().single.widget as Center).child!
                as Text)
            .data!;
    return '${selText('year_selected')}年'
        '${selText('month_selected')}'
        '${selText('day_selected')}日';
  }

  /// 单元格高度 44；负 offset = 前进（露出下一格）
  Future<void> dragWheel(WidgetTester tester, String key, int cells) async {
    await tester.drag(find.byKey(ValueKey(key)), Offset(0, -44.0 * cells));
    await tester.pumpAndSettle();
  }

  // ---------- 日列循环跨月 ----------

  testWidgets('9月30 向前一格 → 2026年10月1日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 9, 30));
    await dragWheel(tester, 'day_wheel', 1);
    expect(datePillText(tester), '2026年10月1日');
  });

  testWidgets('9月30 连续向前 3 格 → 2026年10月3日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 9, 30));
    await dragWheel(tester, 'day_wheel', 3);
    expect(datePillText(tester), '2026年10月3日');
  });

  testWidgets('9月1 向后一格 → 2026年8月31日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 9, 1));
    await tester.drag(
      find.byKey(const ValueKey('day_wheel')),
      const Offset(0, 44),
    );
    await tester.pumpAndSettle();
    expect(datePillText(tester), '2026年8月31日');
  });

  testWidgets('2月28 向前一格 → 2026年3月1日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 2, 28));
    await dragWheel(tester, 'day_wheel', 1);
    expect(datePillText(tester), '2026年3月1日');
  });

  testWidgets('12月31 向前一格 → 跨年 2027年1月1日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 12, 31));
    await dragWheel(tester, 'day_wheel', 1);
    expect(datePillText(tester), '2027年1月1日');
  });

  testWidgets('1月1 向后一格 → 跨年 2025年12月31日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 1, 1));
    await tester.drag(
      find.byKey(const ValueKey('day_wheel')),
      const Offset(0, 44),
    );
    await tester.pumpAndSettle();
    expect(datePillText(tester), '2025年12月31日');
  });

  // ---------- 月列循环跨年 ----------

  testWidgets('12月 向前一个月 → 2027年1月', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 12, 31));
    await dragWheel(tester, 'month_wheel', 1);
    expect(datePillText(tester), '2027年1月31日');
  });

  testWidgets('1月 向后一个月 → 2025年12月（跨年）', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 1, 31));
    await tester.drag(
      find.byKey(const ValueKey('month_wheel')),
      const Offset(0, 44),
    );
    await tester.pumpAndSettle();
    expect(datePillText(tester), '2025年12月31日');
  });

  testWidgets('1月31 切到 2月 → 日号越界收敛 2月28日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 1, 31));
    await dragWheel(tester, 'month_wheel', 1);
    expect(datePillText(tester), '2026年2月28日');
  });

  // ---------- 月内与年列 ----------

  testWidgets('日列月内向前 3 格 → 9月13日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 9, 10));
    await dragWheel(tester, 'day_wheel', 3);
    expect(datePillText(tester), '2026年9月13日');
  });

  testWidgets('年列向前一年 → 2027年2月28日', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 2, 28));
    await dragWheel(tester, 'year_wheel', 1);
    expect(datePillText(tester), '2027年2月28日');
  });

  testWidgets('拖月列后日列继续跨月滚动仍正确（组合操作）', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 9, 30));
    await dragWheel(tester, 'month_wheel', 1); // → 10月30
    await dragWheel(tester, 'day_wheel', 1); // → 10月31
    expect(datePillText(tester), '2026年10月31日');
  });

  // ---------- 鼠标滚轮：每次精确一格 ----------

  /// 向滚轮列中心发送一格滚轮事件（120px，SDK 默认会跳 2~3 格）
  Future<void> sendScroll(WidgetTester tester, String key, double dy) async {
    final center = tester.getCenter(find.byKey(ValueKey(key)));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  testWidgets('鼠标滚轮向下 120px → 9月30 前进一格为 10月1（不跳格）', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 9, 30));
    await sendScroll(tester, 'day_wheel', 120);
    expect(datePillText(tester), '2026年10月1日');
  });

  testWidgets('鼠标滚轮向上 120px → 10月1 回退一格为 9月30（不跳格）', (tester) async {
    await pumpDatePicker(tester, DateTime(2026, 10, 1));
    await sendScroll(tester, 'day_wheel', -120);
    expect(datePillText(tester), '2026年9月30日');
  });

  // ---------- 返回值 ----------

  testWidgets('点确定返回所选日期与时间', (tester) async {
    (DateTime, int)? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<(DateTime, int)>(
                    context: context,
                    builder: (_) => WheelDatePicker(
                      initial: DateTime(2026, 9, 30),
                      initialMinute: 17 * 60 + 53,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 快捷行显示时间胶囊
    expect(find.text('时间 17:53'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked?.$1, DateTime(2026, 9, 30));
    expect(picked?.$2, 17 * 60 + 53);
  });

  testWidgets('时间胶囊弹出钟面选择器，确定后时间不变回传', (tester) async {
    (DateTime, int)? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<(DateTime, int)>(
                    context: context,
                    builder: (_) => WheelDatePicker(
                      initial: DateTime(2026, 9, 30),
                      initialMinute: 17 * 60 + 53,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 点击时间入口 → 弹出 Material 钟面时间选择器 → 直接确定（时间不变）
    await tester.tap(find.byKey(const ValueKey('time_chip')));
    await tester.pumpAndSettle();
    // 钟面弹窗出现（测试 locale 为英文，确认按钮是 OK）
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // 回到底部弹窗，再确定
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked?.$1, DateTime(2026, 9, 30));
    expect(picked?.$2, 17 * 60 + 53);
  });
}
