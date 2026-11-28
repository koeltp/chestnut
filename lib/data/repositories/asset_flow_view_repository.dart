import '../../models/enums.dart';
import '../../utils/stream_utils.dart';
import '../database.dart';
import '../flow_entry.dart';
import 'asset_repository.dart';
import 'bill_image_repository.dart';
import 'bill_repository.dart';
import 'category_repository.dart';
import 'debt_note_repository.dart';

/// 流水视图模型：首页明细与账户流水页的统一数据载体
///
/// UI 只订阅一层流即可拿到渲染所需的全部数据，不再自行串联
/// 账单/借条/还款/分类/图片等多张表的流。
class FlowView {
  const FlowView({
    this.asset,
    required this.entries,
    required this.categories,
    required this.relatedAssets,
    required this.billIdsWithImages,
    required this.debtIdsWithPhotos,
    required this.debtNotes,
  });

  /// 账户流水页的账户本体（含已归档——归档账户也要能看流水）；
  /// 首页明细无单一账户概念，恒为 null
  final Asset? asset;

  /// 账单 + 借条 + 还款分笔合并后的流水条目（已按业务日期倒序）
  final List<FlowEntry> entries;

  /// 分类字典：id → 分类（账单行名称/图标按 id 查）
  final Map<int, Category> categories;

  /// 关联账户字典：id → 账户（含已归档，金额下方小字按 id 查名）
  final Map<int, Asset> relatedAssets;

  /// 带图片的账单 id 集合（相机角标）
  final Set<int> billIdsWithImages;

  /// 带照片的借条 id 集合（相机角标）
  final Set<int> debtIdsWithPhotos;

  /// 借条字典：id → 借条（还款行的对方名/详情弹窗按 noteId 查）。
  /// 全量口径（借条量级小）——还款记录的借条可能不在当前查询范围内
  final Map<int, DebtNote> debtNotes;
}

/// 流水视图仓储：把多张表的流组装成一个 [FlowView]
///
/// 只做"读组装"，不承担任何写逻辑——账户余额仍走 AssetRepository、
/// 借条增删改与还款分笔仍走 DebtNoteRepository，职责互不重叠。
class AssetFlowViewRepository {
  AssetFlowViewRepository(this._db);

  final AppDatabase _db;

  // 各仓储无状态（仅持 _db），就地构造零成本
  late final AssetRepository _assets = AssetRepository(_db);
  late final BillRepository _bills = BillRepository(_db);
  late final DebtNoteRepository _debts = DebtNoteRepository(_db);
  late final CategoryRepository _cats = CategoryRepository(_db);
  late final BillImageRepository _billImages = BillImageRepository(_db);

  /// 账户流水视图：账户本体 + 关联账单（转出/转入双向匹配）+
  /// 关联借条与还款 + 分类/账户字典 + 两类图片标记
  Stream<FlowView> watchAssetFlow(int assetId) {
    final bills = _bills.watchBillsOfAsset(assetId);
    // 一条流同时产出账户本体与全量账户字典：watchAll 含已归档，
    // 修掉归档账户进流水页标题/概览消失的问题
    final assetData = _assets.watchAll().map(
      (list) => (
        self: list.where((a) => a.id == assetId).firstOrNull,
        map: {for (final a in list) a.id: a},
      ),
    );
    final debts = _debts.watchOfAsset(assetId);
    return combineLatest([
      assetData,
      bills,
      debts,
      // 关联借条的还款分笔（join 借条按关联账户过滤）
      _debts.watchRepaymentsOfAsset(assetId),
      _cats.watchAllCategories().map(_categoryMap),
      // 图片标记依赖账单集合：账单一变就换订新的 id 流
      bills.switchMapLatest(
        (list) =>
            _billImages.watchBillIdsWithImages(list.map((b) => b.id).toList()),
      ),
      // 借条照片标记是全表流，UI 按 id 自行过滤
      _debts.watchNoteIdsWithPhotos(),
      // 借条字典：全量口径（与首页明细一致）——换卡还款的借条
      // relatedAssetId ≠ 当前账户，过滤后的流查不到会显示
      // "已删除的借条"兜底文案
      _debts.watchAll().map(_debtMap),
    ]).map((v) {
      final assetInfo = v[0] as ({Asset? self, Map<int, Asset> map});
      return FlowView(
        asset: assetInfo.self,
        relatedAssets: assetInfo.map,
        entries: buildFlowEntries(
          v[1] as List<Bill>,
          v[2] as List<DebtNote>,
          repayments: v[3] as List<DebtNoteRepayment>,
        ),
        categories: v[4] as Map<int, Category>,
        billIdsWithImages: v[5] as Set<int>,
        debtIdsWithPhotos: v[6] as Set<int>,
        debtNotes: v[7] as Map<int, DebtNote>,
      );
    });
  }

  /// 首页明细视图：按 [period] 范围聚合账单，借条与还款也下沉 SQL
  /// 过滤到同一范围；日分组与小计由 UI 基于 entries 计算
  Stream<FlowView> watchHomeFlow(HomePeriod period, DateTime month) {
    final bills = switch (period) {
      HomePeriod.month => _bills.watchBillsInMonth(month),
      HomePeriod.year => _bills.watchBillsInYear(month.year),
      HomePeriod.all => _bills.watchAllBills(),
    };
    // 借条按范围下沉 SQL 过滤：避免全表 watch 后 Dart 层 where
    // 导致范围外借条变动也触发 combineLatest 重发射
    final debts = switch (period) {
      HomePeriod.month => _debts.watchDebtsInMonth(month),
      HomePeriod.year => _debts.watchDebtsInYear(month.year),
      HomePeriod.all => _debts.watchAll(),
    };
    final repayments = switch (period) {
      HomePeriod.month => _debts.watchRepaymentsInMonth(month),
      HomePeriod.year => _debts.watchRepaymentsInYear(month.year),
      HomePeriod.all => _debts.watchRepaymentsAll(),
    };
    return _assembleFlow(bills, debts, repayments);
  }

  /// 首页"全部"模式：最近 [limit] 条账单 + 全部借条与还款，统一混排后
  /// 整体返回。
  ///
  /// "加载更多"= 调大 [limit] 重新订阅，而不是按 offset 翻页：
  /// 借条与还款是全表参与混排的，若按页截断会让同一条记录在每页
  /// 重复出现，且分页边界会和真实时间顺序错位。
  Stream<FlowView> watchHomeFlowPaged({required int limit}) {
    // 借条与还款数量小（个人用户通常几十条），全表 watch 无压力；
    // 与最近 limit 条账单在 Dart 层按日期统一混排
    return _assembleFlow(
      _bills.watchRecentBills(limit),
      _debts.watchAll(),
      _debts.watchRepaymentsAll(),
    );
  }

  /// 共用组装：账单流 + 借条流 + 还款流 → combineLatest 8 个子流 → FlowView
  Stream<FlowView> _assembleFlow(
    Stream<List<Bill>> bills,
    Stream<List<DebtNote>> debts,
    Stream<List<DebtNoteRepayment>> repayments,
  ) {
    return combineLatest([
      bills,
      debts,
      repayments,
      _cats.watchAllCategories().map(_categoryMap),
      _assets.watchAll().map(_assetMap),
      bills.switchMapLatest(
        (list) =>
            _billImages.watchBillIdsWithImages(list.map((b) => b.id).toList()),
      ),
      _debts.watchNoteIdsWithPhotos(),
      // 全量借条字典：还款行的对方名可能落在范围外的借条上
      _debts.watchAll().map(_debtMap),
    ]).map(
      (v) => FlowView(
        entries: buildFlowEntries(
          v[0] as List<Bill>,
          v[1] as List<DebtNote>,
          repayments: v[2] as List<DebtNoteRepayment>,
        ),
        categories: v[3] as Map<int, Category>,
        relatedAssets: v[4] as Map<int, Asset>,
        billIdsWithImages: v[5] as Set<int>,
        debtIdsWithPhotos: v[6] as Set<int>,
        debtNotes: v[7] as Map<int, DebtNote>,
      ),
    );
  }

  /// 分类列表转 id 字典
  Map<int, Category> _categoryMap(List<Category> list) => {
    for (final c in list) c.id: c,
  };

  /// 账户列表转 id 字典
  Map<int, Asset> _assetMap(List<Asset> list) => {
    for (final a in list) a.id: a,
  };

  /// 借条列表转 id 字典
  Map<int, DebtNote> _debtMap(List<DebtNote> list) => {
    for (final n in list) n.id: n,
  };
}
