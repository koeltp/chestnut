import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/asset_flow_view_repository.dart';
import 'package:chestnut/data/repositories/asset_repository.dart';
import 'package:chestnut/data/repositories/bill_image_repository.dart';
import 'package:chestnut/data/repositories/bill_repository.dart';
import 'package:chestnut/models/enums.dart';
import 'package:chestnut/models/summaries.dart';
import 'package:chestnut/pages/asset/asset_snapshot_history_page.dart';
import 'package:chestnut/pages/home/home_page.dart';
import 'package:chestnut/providers/asset_provider.dart';
import 'package:chestnut/providers/bill_provider.dart';
import 'package:chestnut/providers/cloud_storage_provider.dart';
import 'package:chestnut/widgets/stream_cache_mixin.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 流复用回归测试：build 内不新建查询流。
///
/// 背景：多个页面曾在 build 里直接调仓储方法创建 drift 流，每次重建都
/// 取消并重订阅一次查询（首帧全量查询被反复执行，重时拖死主线程）。
/// 这里用计数仓储/Provider 断言"范围不变时连续重建只建一次流"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 触发建库（预置分类随之可用）
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('首页：连续重建只建一次流水/汇总流，切月才换流', (tester) async {
    final flowRepo = _CountingFlowRepository(db);
    final billProvider = _CountingBillProvider(
      BillRepository(db),
      BillImageRepository(db),
      CloudStorageProvider(prefs),
    );

    late StateSetter rebuild;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BillProvider>.value(value: billProvider),
          Provider<AssetFlowViewRepository>.value(value: flowRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                // 非 const 实例：同 key 同类型，父级重建会触发 State.build，
                // 但 State 与已缓存的流应保持不变
                // ignore: prefer_const_constructors
                return HomePage();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(flowRepo.homeCalls, 1);
    expect(billProvider.summaryCalls, 1);

    // 两次无参数变化的重建：流实例复用，不再触发仓储查询
    rebuild(() {});
    await tester.pump();
    rebuild(() {});
    await tester.pump();
    expect(flowRepo.homeCalls, 1);
    expect(billProvider.summaryCalls, 1);

    // 切月：范围真正变化，恰好换一次流
    billProvider.changeMonth(DateTime(2026, 9));
    await tester.pump();
    expect(flowRepo.homeCalls, 2);
    expect(billProvider.summaryCalls, 2);

    // 冲刷 initState 里的 2 秒降级检查定时器，避免测试结束仍有挂起定时器
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('历史市值页：重复重建不重订阅快照流', (tester) async {
    final id = await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            name: '测试账户',
            kind: AssetKind.asset,
            category: '现金',
            valueCents: 100000,
          ),
        );
    final asset = await (db.select(
      db.assets,
    )..where((a) => a.id.equals(id))).getSingle();

    final provider = _CountingAssetProvider(AssetRepository(db), prefs);

    late StateSetter rebuild;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssetProvider>.value(value: provider),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AssetSnapshotHistoryPage(asset: asset);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(provider.snapshotCalls, 1);
    // 资产 id 不变：重建不应再创建快照流
    rebuild(() {});
    await tester.pump();
    rebuild(() {});
    await tester.pump();
    expect(provider.snapshotCalls, 1);
  });

  testWidgets('流缓存：切走再切回同一条件时给新流，不复用已订阅的实例', (tester) async {
    final host = GlobalKey<_SlotHostState>();
    await tester.pumpWidget(MaterialApp(home: _SlotHost(key: host)));
    final state = host.currentState!;
    expect(state.built.length, 1);
    final first = state.built.first;

    // 条件不变的重建：复用同一实例，不重订阅
    state.rebuild();
    await tester.pump();
    expect(state.built.last, same(first));

    // 条件变化：换新流
    state.setKey('b');
    await tester.pump();
    expect(state.built.last, isNot(same(first)));

    // 切回原条件：必须是新实例。drift 查询流是单订阅的，
    // 复用已经 listen 过的旧实例会抛
    // Bad state: Stream has already been listened to（统计页切月崩溃的根因）
    state.setKey('a');
    await tester.pump();
    expect(state.built.last, isNot(same(first)));
  });
}

/// 测试用宿主：每帧按当前 key 从 Mixin 取流并记录实例
class _SlotHost extends StatefulWidget {
  const _SlotHost({super.key});

  @override
  State<_SlotHost> createState() => _SlotHostState();
}

class _SlotHostState extends State<_SlotHost> with StreamCacheMixin<_SlotHost> {
  final List<Stream<int>> built = [];
  String _key = 'a';

  void rebuild() => setState(() {});

  void setKey(String key) => setState(() => _key = key);

  @override
  Widget build(BuildContext context) {
    built.add(ensureSingleStream<int>('slot', _key, () => Stream.value(1)));
    return const SizedBox.shrink();
  }
}

/// 计数版流水视图仓储：记录 watchHomeFlow 被调用的次数
class _CountingFlowRepository extends AssetFlowViewRepository {
  _CountingFlowRepository(super.db);

  int homeCalls = 0;

  @override
  Stream<FlowView> watchHomeFlow(HomePeriod period, DateTime month) {
    homeCalls++;
    // 用同步空流代替 drift 查询：测试只关心"建了几次流"，
    // 不引入真实数据库订阅带来的悬挂清理定时器
    return const Stream<FlowView>.empty();
  }
}

/// 计数版账单 Provider：记录首页汇总流的创建次数
class _CountingBillProvider extends BillProvider {
  _CountingBillProvider(super.repo, super.imageRepo, super.cloud);

  int summaryCalls = 0;

  @override
  Stream<MonthSummary> homeSummaryStream() {
    summaryCalls++;
    // 同上：只计数，不订阅真实 drift 流
    return Stream.value(MonthSummary.empty);
  }
}

/// 计数版资产 Provider：记录快照流的创建次数
class _CountingAssetProvider extends AssetProvider {
  _CountingAssetProvider(super.repo, super.prefs);

  int snapshotCalls = 0;

  @override
  Stream<List<AssetSnapshot>> snapshotStream(int assetId) {
    snapshotCalls++;
    // 同上：只计数，不订阅真实 drift 流
    return Stream.value(const <AssetSnapshot>[]);
  }
}
