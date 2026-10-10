import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../models/enums.dart';
import '../database.dart';
import '../tables/assets.dart';

/// 单日净值点：(日期 `yyyy-MM-dd`, 净值分)
typedef NetValuePoint = (String day, int netCents);

/// 余额不足：资产账户资金流出后余额不能为负
///
/// 统一在 [AssetRepository.applyAccountDelta] 收口抛出；调用方事务随之
/// 回滚，页面层 catch 后直接把 [toString] 的中文信息 toast 给用户
class InsufficientBalanceException implements Exception {
  InsufficientBalanceException(this.accountName);

  /// 流出资产的账户名
  final String accountName;

  @override
  String toString() => '「$accountName」余额不足';
}

/// 资产页汇总快照：净值卡 / 负债率卡 / 借入借出卡共用
///
/// 口径说明：
/// · 资产侧合计 = 未归档且计入总资产的账户市值（不含借条）；
/// · 借条按方向并入两侧——借出计入总资产、借入计入总负债；
/// · "全部"口径（含不计入统计的借条）仅供借入借出卡展示台账总量。
class AssetSummary {
  const AssetSummary({
    required this.assetCents,
    required this.liabilityCents,
    required this.assetCount,
    required this.liabilityCount,
    required this.lendOutCents,
    required this.borrowInCents,
    required this.lendOutAllCents,
    required this.borrowInAllCents,
  });

  /// 账户资产合计（分，不含借条）
  final int assetCents;

  /// 账户负债合计（分，恒为正数，不含借条）
  final int liabilityCents;

  /// 参与净值的资产账户数
  final int assetCount;

  /// 参与净值的负债账户数
  final int liabilityCount;

  /// 计入总资产的借出合计（分）
  final int lendOutCents;

  /// 计入总负债的借入合计（分）
  final int borrowInCents;

  /// 全部借出合计（分，含"不计入统计"的借条）
  final int lendOutAllCents;

  /// 全部借入合计（分，含"不计入统计"的借条）
  final int borrowInAllCents;

  /// 总资产 = 账户资产 + 借出
  int get totalAssetCents => assetCents + lendOutCents;

  /// 总负债 = 账户负债 + 借入
  int get totalLiabilityCents => liabilityCents + borrowInCents;

  /// 净值 = 总资产 − 总负债（分，可为负）
  int get netCents => totalAssetCents - totalLiabilityCents;

  /// 负债率 = 总负债 / 总资产（0.0~1.0，总资产为 0 时记 0）
  double get liabilityRate {
    if (totalAssetCents <= 0) return 0;
    return (totalLiabilityCents / totalAssetCents).clamp(0.0, 1.0);
  }

  /// 不含借条的快照净值（净值曲线末点口径：曲线历史全部来自
  /// 资产快照，末点若混入借条会与历史点口径不一致出现跳变）
  int get snapshotNetCents => assetCents - liabilityCents;
}

/// 资产仓储：资产/负债的增改、归档与净值聚合
///
/// 快照原则：市值的每一次变化都落一条 [AssetSnapshots]（只增不删），
/// 净值曲线、涨跌基准都从快照推导，资产表只保存"当前值"。
class AssetRepository {
  AssetRepository(this._db);

  final AppDatabase _db;

  /// 监听未归档资产（资产在前、负债在后，同组按 sortOrder）
  Stream<List<Asset>> watchActive() {
    return (_db.select(_db.assets)
          ..where((a) => a.archived.equals(false))
          ..orderBy([
            (a) => OrderingTerm.asc(a.kind),
            (a) => OrderingTerm.asc(a.sortOrder),
            (a) => OrderingTerm.asc(a.id),
          ]))
        .watch();
  }

  /// 监听已归档资产（按归档时间倒序，最近归档的在前）
  Stream<List<Asset>> watchArchived() {
    return (_db.select(_db.assets)
          ..where((a) => a.archived.equals(true))
          ..orderBy([(a) => OrderingTerm.desc(a.updatedAt)]))
        .watch();
  }

  /// 监听全部资产（含已归档）：账单条目"金额下方账户小字"按 id 查名用，
  /// 归档账户照常显示名字，只有删除后才兜底"已删除账户"
  Stream<List<Asset>> watchAll() {
    return (_db.select(_db.assets)
          ..orderBy([(a) => OrderingTerm.asc(a.id)]))
        .watch();
  }

  /// 监听资产页汇总（净值卡/负债率卡/借入借出卡共用一份数据源）
  ///
  /// 资产表与借条表在一条 SQL 里分别聚合，任一表变化都会重新发射。
  /// include_in_net=false 的账户与 include_in_total=false 的借条
  /// 不参与"计入"口径，但计入"全部"口径供台账展示。
  Stream<AssetSummary> watchSummary() {
    return _db
        .customSelect(
          '''
          SELECT
            (SELECT COALESCE(SUM(value_cents), 0) FROM assets
              WHERE archived = 0 AND include_in_net = 1 AND kind = 0
            ) AS asset_cents,
            (SELECT COALESCE(SUM(value_cents), 0) FROM assets
              WHERE archived = 0 AND include_in_net = 1 AND kind = 1
            ) AS liability_cents,
            (SELECT COUNT(*) FROM assets
              WHERE archived = 0 AND include_in_net = 1 AND kind = 0
            ) AS asset_count,
            (SELECT COUNT(*) FROM assets
              WHERE archived = 0 AND include_in_net = 1 AND kind = 1
            ) AS liability_count,
            (SELECT COALESCE(SUM(amount_cents), 0) FROM debt_notes
              WHERE direction = 0 AND include_in_total = 1
            ) AS lend_out_cents,
            (SELECT COALESCE(SUM(amount_cents), 0) FROM debt_notes
              WHERE direction = 1 AND include_in_total = 1
            ) AS borrow_in_cents,
            (SELECT COALESCE(SUM(amount_cents), 0) FROM debt_notes
              WHERE direction = 0
            ) AS lend_out_all_cents,
            (SELECT COALESCE(SUM(amount_cents), 0) FROM debt_notes
              WHERE direction = 1
            ) AS borrow_in_all_cents
          ''',
          readsFrom: {_db.assets, _db.debtNotes},
        )
        .watch()
        .map((rows) {
          final r = rows.first;
          return AssetSummary(
            assetCents: r.read<int>('asset_cents'),
            liabilityCents: r.read<int>('liability_cents'),
            assetCount: r.read<int>('asset_count'),
            liabilityCount: r.read<int>('liability_count'),
            lendOutCents: r.read<int>('lend_out_cents'),
            borrowInCents: r.read<int>('borrow_in_cents'),
            lendOutAllCents: r.read<int>('lend_out_all_cents'),
            borrowInAllCents: r.read<int>('borrow_in_all_cents'),
          );
        });
  }

  /// 监听历史净值序列（不含今天：当天净值随资产表实时变化，由 UI 以
  /// 当前值补上最后一点，保证曲线末点与卡片数字始终一致）
  ///
  /// 聚合口径：按日取每项资产当天最后一条快照，净值 = Σ资产 − Σ负债；
  /// 当日尚无快照的资产不计入（快照在创建/更新市值时落，天然满足）。
  /// 已归档资产的历史快照保留参与聚合，避免曲线回溯断层。
  /// 注意：借条无快照，曲线为纯资产快照口径。
  Stream<List<NetValuePoint>> watchNetHistory() {
    final query =
        _db.select(_db.assetSnapshots).join([
          innerJoin(
            _db.assets,
            _db.assets.id.equalsExp(_db.assetSnapshots.assetId),
          ),
        ])
          ..orderBy([
            OrderingTerm.asc(_db.assetSnapshots.day),
            OrderingTerm.asc(_db.assetSnapshots.createdAt),
            OrderingTerm.asc(_db.assetSnapshots.id),
          ]);
    return query.watch().map((rows) {
      final todayKey = _dayKey(DateTime.now());
      // day -> (assetId -> 当天最后一条市值)，后写覆盖即"当天最后一条"
      final byDay = <String, Map<int, int>>{};
      final kinds = <int, AssetKind>{};
      for (final row in rows) {
        final snap = row.readTable(_db.assetSnapshots);
        final asset = row.readTable(_db.assets);
        kinds[snap.assetId] = asset.kind;
        byDay.putIfAbsent(snap.day, () => {})[snap.assetId] = snap.valueCents;
      }
      return [
        for (final entry in byDay.entries)
          if (entry.key != todayKey)
            (
              entry.key,
              entry.value.entries.fold<int>(0, (sum, e) {
                final signed =
                    kinds[e.key] == AssetKind.liability ? -e.value : e.value;
                return sum + signed;
              }),
            ),
      ];
    });
  }

  /// 新增资产：落初始快照，让净值曲线从创建当天就有该项资产
  Future<void> insertAsset({
    required String name,
    required AssetKind kind,
    required String category,
    required int valueCents,
    String? note,
    bool includeInNet = true,
    int? creditLimitCents,
    int? billDay,
    int? repayDay,
  }) async {
    return _db.transaction(() async {
      // 取同类型里 sortOrder 最大的记录：必须 limit(1) 收窄到一行，
      // getSingleOrNull 只容忍 0/1 行，同类型已有两条以上时多行会炸
      final maxOrder = await (_db.select(_db.assets)
            ..where((a) => a.kind.equals(kind.index))
            ..orderBy([(a) => OrderingTerm.desc(a.sortOrder)])
            ..limit(1))
          .getSingleOrNull();
      final id = await _db
          .into(_db.assets)
          .insert(
            AssetsCompanion.insert(
              name: name,
              kind: kind,
              category: category,
              valueCents: valueCents,
              note: Value(note),
              includeInNet: Value(includeInNet),
              creditLimitCents: Value(creditLimitCents),
              billDay: Value(billDay),
              repayDay: Value(repayDay),
              sortOrder: Value((maxOrder?.sortOrder ?? -1) + 1),
            ),
          );
      await _insertSnapshot(id, valueCents);
    });
  }

  /// 更新资产信息（名称/分类/备注/开关/信用卡字段），不动市值与快照
  Future<void> updateInfo(
    Asset asset, {
    required String name,
    required String category,
    String? note,
    bool? includeInNet,
    int? creditLimitCents,
    int? billDay,
    int? repayDay,
  }) {
    return (_db.update(_db.assets)..where((a) => a.id.equals(asset.id))).write(
      AssetsCompanion(
        name: Value(name),
        category: Value(category),
        note: Value(note),
        includeInNet: Value(includeInNet ?? asset.includeInNet),
        creditLimitCents: Value(creditLimitCents),
        billDay: Value(billDay),
        repayDay: Value(repayDay),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 更新市值：同步落快照（净值曲线/涨跌基准的数据来源）
  ///
  /// 资产账户余额不可为负：手动改值改出负数同样拒绝（UI 已拦 <0，
  /// 这里是仓储层的不变量兜底）
  Future<void> updateValue(Asset asset, int valueCents) async {
    if (asset.kind == AssetKind.asset && valueCents < 0) {
      throw InsufficientBalanceException(asset.name);
    }
    await _db.transaction(() async {
      await (_db.update(_db.assets)..where((a) => a.id.equals(asset.id))).write(
        AssetsCompanion(
          valueCents: Value(valueCents),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _insertSnapshot(asset.id, valueCents);
    });
  }

  /// 归档 / 取消归档；归档后不参与净值统计，历史快照保留
  Future<void> setArchived(Asset asset, {required bool archived}) {
    return (_db.update(_db.assets)..where((a) => a.id.equals(asset.id))).write(
      AssetsCompanion(
        archived: Value(archived),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 落一条市值快照（今天）
  Future<void> _insertSnapshot(int assetId, int valueCents) {
    return _db
        .into(_db.assetSnapshots)
        .insert(
          AssetSnapshotsCompanion.insert(
            assetId: assetId,
            day: _dayKey(DateTime.now()),
            valueCents: valueCents,
          ),
        );
  }

  // ---------- 记账联动账户（余额直改模型） ----------

  /// 对单账户应用一笔资金流影响，并落余额快照（净值曲线保持连续）。
  ///
  /// · [isOutflow] = true（钱离开账户的"支付"语义）：
  ///   资产余额减少；信用卡（负债）欠款增加
  /// · [isOutflow] = false（钱进入账户的"收款"语义）：
  ///   资产余额增加；信用卡（负债）欠款减少，减穿 0 为负表示溢缴款
  ///
  /// 必须在调用方事务内执行；账户已删除/不存在时静默跳过。
  /// 归档账户同样生效（归档只是不进净值统计，余额照常流转）
  ///
  /// [enforceBalance] = true 时校验余额不足：资产账户扣减穿 0 抛
  /// [InsufficientBalanceException]（撤销旧影响的回滚路径传 false，
  /// 保证删除账单等纠正操作不受阻；信用卡欠款减穿 0 是溢缴款，允许）
  Future<void> applyAccountDelta(
    int assetId, {
    required bool isOutflow,
    required int amountCents,
    bool enforceBalance = false,
  }) async {
    final account = await (_db.select(_db.assets)
          ..where((a) => a.id.equals(assetId)))
        .getSingleOrNull();
    if (account == null) return;
    final delta = account.kind == AssetKind.asset
        ? (isOutflow ? -amountCents : amountCents)
        : (isOutflow ? amountCents : -amountCents);
    final newValue = account.valueCents + delta;
    if (enforceBalance &&
        account.kind == AssetKind.asset &&
        delta < 0 &&
        newValue < 0) {
      throw InsufficientBalanceException(account.name);
    }
    await (_db.update(_db.assets)..where((a) => a.id.equals(assetId))).write(
      AssetsCompanion(
        valueCents: Value(newValue),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _insertSnapshot(assetId, newValue);
  }

  /// 撤销一笔账单对账户余额的影响（删除账单/修改前回滚用）
  Future<void> _revertBill(Bill bill) => _applyBill(bill, revert: true);

  /// 应用/撤销一笔账单的余额影响
  ///
  /// · 支出：付款账户支付语义（资产减/信用卡欠款增）
  /// · 收入：收款账户收款语义（资产加/信用卡欠款减）
  /// · 转账：转出账户支付语义 + 转入账户收款语义
  ///
  /// 应用新影响（revert = false）时校验余额不足；撤销旧影响不校验
  Future<void> _applyBill(Bill bill, {required bool revert}) async {
    final enforce = !revert;
    switch (bill.type) {
      case BillType.expense:
        if (bill.assetId != null) {
          await applyAccountDelta(
            bill.assetId!,
            isOutflow: !revert,
            amountCents: bill.amountCents,
            enforceBalance: enforce,
          );
        }
      case BillType.income:
        if (bill.assetId != null) {
          await applyAccountDelta(
            bill.assetId!,
            isOutflow: revert,
            amountCents: bill.amountCents,
            enforceBalance: enforce,
          );
        }
      case BillType.transfer:
        if (bill.assetId != null) {
          await applyAccountDelta(
            bill.assetId!,
            isOutflow: !revert,
            amountCents: bill.amountCents,
            enforceBalance: enforce,
          );
        }
        if (bill.toAssetId != null) {
          await applyAccountDelta(
            bill.toAssetId!,
            isOutflow: revert,
            amountCents: bill.amountCents,
            enforceBalance: enforce,
          );
        }
    }
  }

  /// 账单变更联动余额（必须在调用方事务内执行）
  ///
  /// · 仅 [newBill] 非空 = 新增，应用影响
  /// · 仅 [oldBill] 非空 = 删除，撤销影响
  /// · 两者都非空 = 修改，先撤销旧影响再应用新影响
  ///   （换账户 = 旧账户加回、新账户扣减，自然正确）
  Future<void> applyBillEffect({Bill? oldBill, Bill? newBill}) async {
    if (oldBill != null) await _revertBill(oldBill);
    if (newBill != null) await _applyBill(newBill, revert: false);
  }

  /// 日期转 `yyyy-MM-dd`（与快照 day 列口径一致）
  static String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
}
