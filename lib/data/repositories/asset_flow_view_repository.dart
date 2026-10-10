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
/// 账单/借条/分类/图片等多张表的流。
class FlowView {
  const FlowView({
    this.asset,
    required this.entries,
    required this.categories,
    required this.relatedAssets,
    required this.billIdsWithImages,
    required this.debtIdsWithPhotos,
  });

  /// 账户流水页的账户本体（含已归档——归档账户也要能看流水）；
  /// 首页明细无单一账户概念，恒为 null
  final Asset? asset;

  /// 账单 + 借条合并后的流水条目（已按业务日期倒序）
  final List<FlowEntry> entries;

  /// 分类字典：id → 分类（账单行名称/图标按 id 查）
  final Map<int, Category> categories;

  /// 关联账户字典：id → 账户（含已归档，金额下方小字按 id 查名）
  final Map<int, Asset> relatedAssets;

  /// 带图片的账单 id 集合（相机角标）
  final Set<int> billIdsWithImages;

  /// 带照片的借条 id 集合（相机角标）
  final Set<int> debtIdsWithPhotos;
}

/// 流水视图仓储：把多张表的流组装成一个 [FlowView]
///
/// 只做"读组装"，不承担任何写逻辑——账户余额仍走 AssetRepository、
/// 借条增删改仍走 DebtNoteRepository，职责互不重叠。
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
  /// 关联借条 + 分类/账户字典 + 两类图片标记
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
    return combineLatest([
      assetData,
      bills,
      _debts.watchOfAsset(assetId),
      _cats.watchAllCategories().map(_categoryMap),
      // 图片标记依赖账单集合：账单一变就换订新的 id 流
      bills.switchMapLatest(
        (list) => _billImages.watchBillIdsWithImages(
          list.map((b) => b.id).toList(),
        ),
      ),
      // 借条照片标记是全表流，UI 按 id 自行过滤
      _debts.watchNoteIdsWithPhotos(),
    ]).map(
      (v) {
        final assetInfo = v[0] as ({Asset? self, Map<int, Asset> map});
        return FlowView(
          asset: assetInfo.self,
          relatedAssets: assetInfo.map,
          entries: buildFlowEntries(
            v[1] as List<Bill>,
            v[2] as List<DebtNote>,
          ),
          categories: v[3] as Map<int, Category>,
          billIdsWithImages: v[4] as Set<int>,
          debtIdsWithPhotos: v[5] as Set<int>,
        );
      },
    );
  }

  /// 首页明细视图：按 [period] 范围聚合账单，借条按借款日期落入
  /// 同一范围；日分组与小计由 UI 基于 entries 计算
  Stream<FlowView> watchHomeFlow(HomePeriod period, DateTime month) {
    final bills = switch (period) {
      HomePeriod.month => _bills.watchBillsInMonth(month),
      HomePeriod.year => _bills.watchBillsInYear(month.year),
      HomePeriod.all => _bills.watchAllBills(),
    };
    return combineLatest([
      bills,
      _debts.watchAll().map(
            (list) =>
                list.where((d) => _debtInRange(d, period, month)).toList(),
          ),
      _cats.watchAllCategories().map(_categoryMap),
      _assets.watchAll().map(_assetMap),
      bills.switchMapLatest(
        (list) => _billImages.watchBillIdsWithImages(
          list.map((b) => b.id).toList(),
        ),
      ),
      _debts.watchNoteIdsWithPhotos(),
    ]).map(
      (v) => FlowView(
        entries: buildFlowEntries(
          v[0] as List<Bill>,
          v[1] as List<DebtNote>,
        ),
        categories: v[2] as Map<int, Category>,
        relatedAssets: v[3] as Map<int, Asset>,
        billIdsWithImages: v[4] as Set<int>,
        debtIdsWithPhotos: v[5] as Set<int>,
      ),
    );
  }

  /// 分类列表转 id 字典
  Map<int, Category> _categoryMap(List<Category> list) =>
      {for (final c in list) c.id: c};

  /// 账户列表转 id 字典
  Map<int, Asset> _assetMap(List<Asset> list) =>
      {for (final a in list) a.id: a};

  /// 借条是否落在首页当前查看范围内（按借款日期判断）
  bool _debtInRange(DebtNote debt, HomePeriod period, DateTime month) =>
      switch (period) {
        HomePeriod.month =>
          debt.borrowedAt.year == month.year &&
              debt.borrowedAt.month == month.month,
        HomePeriod.year => debt.borrowedAt.year == month.year,
        HomePeriod.all => true,
      };
}
