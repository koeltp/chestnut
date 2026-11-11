import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/bill_repository.dart';
import 'package:chestnut/data/repositories/budget_repository.dart';
import 'package:chestnut/data/repositories/category_repository.dart';
import 'package:chestnut/models/summaries.dart';
import 'package:chestnut/pages/budget/budget_page.dart';
import 'package:chestnut/providers/budget_provider.dart';
import 'package:chestnut/providers/category_provider.dart';
import 'package:chestnut/providers/settings_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：预算流的值可为空（null = 该月未设预算）。
/// 早期用 `hasData` 判断加载态，而 `hasData` 的定义是 `data != null`，
/// 于是切到未设预算的月份后整页永久停在转圈。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('预算页：切到未设预算的月份不应停在整页 loading', (tester) async {
    // budget_mode = -1 表示"未选模式"：避免 initState 的自动填充逻辑
    // 去跑真实数据库查询（fake zone 里不会完成）
    SharedPreferences.setMockInitialValues({'budget_mode': -1});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BudgetProvider>(
            create: (_) =>
                _EmptyBudgetProvider(BudgetRepository(db), BillRepository(db)),
          ),
          ChangeNotifierProvider<CategoryProvider>(
            create: (_) => CategoryProvider(CategoryRepository(db)),
          ),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(prefs),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: BudgetPage())),
      ),
    );
    // 首帧只完成订阅，流事件需要真实事件循环推进一次
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    // 主体已按"未设预算"渲染 = 没有卡在整页 loading
    expect(find.text('尚未设置预算'), findsOneWidget);
    expect(find.text('分类预算'), findsOneWidget);
    for (var i = 0; i < 14; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();
      await tester.pump();
    }

    // 2025-09 没有预算：流发出 null，早期用 hasData 判断会把 null
    // 当成"还没加载"，整页永久转圈
    expect(find.text('尚未设置预算'), findsOneWidget);
    expect(find.text('分类预算'), findsOneWidget);

    await db.close();
  });
}

/// 用同步流替代 drift 查询流：widget test 的 fake zone 驱动不了真实
/// 数据库查询，这里只验证页面在"流会正常发数据"时的加载态判断
class _EmptyBudgetProvider extends BudgetProvider {
  _EmptyBudgetProvider(super.repo, super.billRepo);

  @override
  Future<Budget?> getBudget(DateTime month) async => null;

  @override
  Stream<Budget?> budgetStream(DateTime month) => Stream<Budget?>.value(null);

  @override
  Stream<MonthSummary> summaryStream(DateTime month) =>
      Stream<MonthSummary>.value(MonthSummary.empty);

  @override
  Stream<List<Budget>> categoryBudgetsStream(DateTime month) =>
      Stream<List<Budget>>.value(const []);

  @override
  Stream<List<CategorySummary>> categorySummaryStream(DateTime month) =>
      Stream<List<CategorySummary>>.value(const []);
}
