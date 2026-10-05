import '../../data/database.dart';

/// 统计页纯逻辑：关键词过滤与分类聚合
///
/// 与 UI 解耦便于单元测试（原为 stats_page 私有方法，拆分时外提），
/// 主页面在 _buildBody 中调用。

/// 环图/排行条目：category 为 null = 分类已删除或未细分（不可钻取）
typedef CategoryEntry = ({Category? category, String name, int cents});

/// 关键词过滤：定位完整信息/备注/分类名任一包含（英文统一转小写
/// 比较，中文不受影响）
List<Bill> applyKeyword(
  List<Bill> bills,
  Map<int, Category> categories,
  String keyword,
) {
  final kw = keyword.trim().toLowerCase();
  if (kw.isEmpty) return bills;
  return bills.where((b) {
    return (b.locationFull ?? '').toLowerCase().contains(kw) ||
        (b.note ?? '').toLowerCase().contains(kw) ||
        (categories[b.categoryId]?.name ?? '').toLowerCase().contains(kw);
  }).toList();
}

/// 按分类聚合（全部视图环图/排行共用）：金额降序；
/// 分类已删除的账单归为"未知分类"（category 为 null，不可钻取）
List<CategoryEntry> aggregateByCategory(
  List<Bill> bills,
  Map<int, Category> categories,
) {
  final sums = <int, int>{};
  for (final b in bills) {
    sums[b.categoryId] = (sums[b.categoryId] ?? 0) + b.amountCents;
  }
  final entries = [
    for (final e in sums.entries)
      (
        category: categories[e.key],
        name: categories[e.key]?.name ?? '未知分类',
        cents: e.value,
      ),
  ]..sort((a, b) => b.cents.compareTo(a.cents));
  return entries;
}

/// 子分类构成数据（分类视图仅一级分类）：按子分类聚合；
/// 直接挂一级或分类已不存在的账单归并为"未细分"（不可钻取）
List<CategoryEntry> pieEntries(
  List<Bill> bills,
  Map<int, Category> categories,
  Category parent,
) {
  final subSums = <int, int>{};
  var direct = 0;
  for (final b in bills) {
    final c = categories[b.categoryId];
    if (c != null && c.parentId == parent.id) {
      subSums[b.categoryId] = (subSums[b.categoryId] ?? 0) + b.amountCents;
    } else {
      direct += b.amountCents;
    }
  }
  final entries = [
    for (final e in subSums.entries)
      (
        category: categories[e.key],
        name: categories[e.key]?.name ?? '未知分类',
        cents: e.value,
      ),
  ];
  if (direct > 0) entries.add((category: null, name: '未细分', cents: direct));
  entries.sort((a, b) => b.cents.compareTo(a.cents));
  return entries;
}
