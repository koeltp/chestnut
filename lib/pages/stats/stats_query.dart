import '../../models/enums.dart';

/// 统计页视图身份：页面形态与过滤口径由此推导
/// （取代旧的 categoryId + directOnly 布尔标记组合，一个字段一个含义）
enum StatsViewType {
  /// 全部视图：分段器 + 分类占比环图 + 排行 + 明细
  all,

  /// 分类视图：某分类的账单（一级含其全部子分类，二级为自身）
  category,

  /// 未细分视图：一级分类下直挂（未指定二级）的账单
  uncategorized,
}

/// 可空字段哨兵：区分 copyWith"不修改"与"置为 null"
const Object _unset = _Unset();

class _Unset {
  const _Unset();
}

/// 统计查询参数（不可变快照）：统计页唯一状态源。
///
/// [_history] 里存的就是本对象的快照，← 还原 = 换回旧快照重新搜索。
/// 视图身份 [view] 与筛选条件（filterCategoryIds/keyword/tagIds）分离：
/// 前者由跳转/完整组搜索产生并决定页面形态，后者是普通筛选条件
class StatsQuery {
  const StatsQuery({
    this.period = HomePeriod.month,
    this._month,
    this.custom,
    this.type = BillType.expense,
    this.view = StatsViewType.all,
    this.categoryId,
    this.filterCategoryIds = const {},
    this.keyword = '',
    this.tagIds = const {},
  });

  /// 月/年锚点（period 为 month/year 时生效）；创建时默认当前月
  final DateTime? _month;
  DateTime get month => _month ?? DateTime.now();

  /// 查看范围（按月/按年/全部），与首页口径一致
  final HomePeriod period;

  /// 自定义起止日期（开始含当天、截止排他），两端可只选其一（开放端
  /// 不限制）；非空时优先于 [period] 生效
  final ({DateTime? start, DateTime? end})? custom;

  /// 全部视图的收支类型（分类/未细分视图由分类自身类型决定）
  final BillType type;

  /// 视图身份（决定页面形态与过滤口径）
  final StatsViewType view;

  /// 分类/未细分视图的视图分类 id；其余视图为 null
  final int? categoryId;

  /// 面板多选分类过滤条件（仅全部视图生效）；其余视图恒为空。
  /// 命中口径与聚合一致：命中一级即包含其全部子分类账单，勾选二级
  /// 按精确 id 命中
  final Set<int> filterCategoryIds;

  /// 已应用的搜索关键词（空 = 未筛选）：过滤备注/定位完整信息/分类名
  final String keyword;

  /// 已选标签 id 集合（空 = 不按标签筛选）；多个标签取并集
  final Set<int> tagIds;

  /// 当前范围的 [start, end) 查询边界。
  /// 口径：开始日与截止日均**含当天**——自定义区间的截止端在内部
  /// +1 天转为排他边界（选 10/31 = 查到 10/31 当天）；
  /// 全部模式与开放端为 null（不限制）
  (DateTime?, DateTime?) get range {
    final c = custom;
    if (c != null) {
      final s = c.start;
      final e = c.end;
      return (
        s == null ? null : DateTime(s.year, s.month, s.day),
        e == null ? null : DateTime(e.year, e.month, e.day + 1),
      );
    }
    return switch (period) {
      HomePeriod.month => (
        DateTime(month.year, month.month),
        DateTime(month.year, month.month + 1),
      ),
      HomePeriod.year => (DateTime(month.year), DateTime(month.year + 1)),
      HomePeriod.all => (null, null),
    };
  }

  /// 当前范围的用户语义区间（起止均含当天）：筛选面板据此回显。
  /// period 模式也表达成具体日期，面板内即可统一编辑
  ({DateTime? start, DateTime? end}) get userRange {
    final c = custom;
    if (c != null) return c;
    return switch (period) {
      HomePeriod.month => (
        start: DateTime(month.year, month.month, 1),
        end: DateTime(
          month.year,
          month.month,
          DateTime(month.year, month.month + 1, 0).day,
        ),
      ),
      HomePeriod.year => (
        start: DateTime(month.year, 1, 1),
        end: DateTime(month.year, 12, 31),
      ),
      HomePeriod.all => (start: null, end: null),
    };
  }

  /// 复制并修改部分字段；可空字段（custom/categoryId）默认不修改，
  /// 传 [_unset] 以外的值即修改（含显式置 null）
  // ignore: library_private_types_in_public_api
  StatsQuery copyWith({
    HomePeriod? period,
    DateTime? month,
    Object? custom = _unset,
    BillType? type,
    StatsViewType? view,
    Object? categoryId = _unset,
    Set<int>? filterCategoryIds,
    String? keyword,
    Set<int>? tagIds,
  }) {
    return StatsQuery(
      period: period ?? this.period,
      month: month ?? _month,
      custom: custom == _unset
          ? this.custom
          : custom as ({DateTime? start, DateTime? end})?,
      type: type ?? this.type,
      view: view ?? this.view,
      categoryId: categoryId == _unset ? this.categoryId : categoryId as int?,
      filterCategoryIds: filterCategoryIds ?? this.filterCategoryIds,
      keyword: keyword ?? this.keyword,
      tagIds: tagIds ?? this.tagIds,
    );
  }
}
