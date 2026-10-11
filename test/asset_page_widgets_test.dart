import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/asset_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/pages/asset/asset_archived_section.dart';
import 'package:chestnut/pages/asset/asset_summary_cards.dart';
import 'package:chestnut/providers/asset_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 资产页核心组件的 widget 冒烟测试
///
/// 数据层逻辑已由 asset_repository_test 覆盖；这里保障页面组件的
/// 行为接线不回归：金额模糊/明文切换、负债率展示、归档折叠区的
/// 出现与恢复。用内存库 + 真 Provider，走真实数据流而非 mock。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AssetProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    final prefs = await SharedPreferences.getInstance();
    provider = AssetProvider(AssetRepository(db), prefs);
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap(Widget child) => MultiProvider(
    providers: [ChangeNotifierProvider<AssetProvider>.value(value: provider)],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('净值卡：默认模糊显示占位，点击切换明文', (tester) async {
    const summary = AssetSummary(
      assetCents: 1234500,
      liabilityCents: 120000,
      assetCount: 1,
      liabilityCount: 1,
      lendOutCents: 0,
      borrowInCents: 0,
      lendOutAllCents: 0,
      borrowInAllCents: 0,
    );
    // 未存过开关状态时默认模糊（与生产口径一致）
    await tester.pumpWidget(wrap(NetValueCard(summary: summary)));
    expect(find.text('¥ ****'), findsNWidgets(3)); // 净值 + 总资产 + 总负债

    // 点整卡切换明文：净值与两列全部显示真实金额
    await tester.tap(find.byType(NetValueCard));
    await tester.pumpAndSettle();
    expect(find.text('¥ ****'), findsNothing);
    expect(find.text('¥11,145'), findsOneWidget); // 净值 = 12345 − 1200
    expect(find.text('¥12,345'), findsOneWidget); // 总资产
    expect(find.text('-¥1,200'), findsOneWidget); // 总负债
  });

  testWidgets('负债率卡：展示项数、百分比与进度条', (tester) async {
    const summary = AssetSummary(
      assetCents: 1000000,
      liabilityCents: 500000,
      assetCount: 2,
      liabilityCount: 1,
      lendOutCents: 0,
      borrowInCents: 0,
      lendOutAllCents: 0,
      borrowInAllCents: 0,
    );
    // 模糊态只模糊金额，百分比与项数照常展示
    await tester.pumpWidget(wrap(LiabilityRateCard(summary: summary)));
    expect(find.text('负债率'), findsOneWidget);
    expect(find.text('2 项资产 | 1 项负债'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('负债占资产的 ****'), findsOneWidget);
  });

  testWidgets('已归档折叠区：归档后出现，恢复后消失', (tester) async {
    // 数据库写入走真实异步（drift），须在 runAsync 内执行，
    // 否则 FakeAsync 环境下 await 真实 IO 会永远挂起。
    // 用 select 直接查询拿资产对象（不走流订阅，避免遗留取消 Timer）
    late Asset asset;
    await tester.runAsync(() async {
      await provider.addAsset(
        name: '测试储蓄卡',
        kind: AssetKind.asset,
        category: '现金',
        valueCents: 100000,
      );
      asset = (await db.select(db.assets).get()).single;
    });

    // 未归档：不渲染折叠区
    await tester.pumpWidget(wrap(const ArchivedSection()));
    await tester.pumpAndSettle();
    expect(find.text('已归档 (1)'), findsNothing);

    // 归档：折叠区出现并展示资产行
    await tester.runAsync(
      () => provider.setArchived(asset, archived: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('已归档 (1)'), findsOneWidget);

    // 展开折叠区后可见归档资产行
    await tester.tap(find.text('已归档 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('测试储蓄卡'), findsOneWidget);

    // 点「恢复」：资产回到未归档列表，折叠区随之消失
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('已归档 (1)'), findsNothing);

    // drift 的流取消订阅经过 microtask 后才安排 0ms 关闭 Timer，
    // 推进两帧把它彻底消化，避免测试结束残留 pending timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  });
}
