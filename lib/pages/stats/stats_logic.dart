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

/// 按一级分类聚合（全部视图环图/排行共用）：金额降序；
/// 二级分类的账单上浮归并到所属一级（火车→交通），总览只保持
/// 一级粒度，二级明细留给钻取后的分类视图"子分类构成"环图；
/// 分类已删除（连一级也不存在）的账单归为"未知分类"（category
/// 为 null，不可钻取）
List<CategoryEntry> aggregateByCategory(
  List<Bill> bills,
  Map<int, Category> categories,
) {
  final sums = <int, int>{};
  var unknown = 0;
  for (final b in bills) {
    final c = categories[b.categoryId];
    // 二级上浮一级：parentId 指向的一级理论上必存在（外键约束），
    // 查不到按"未知分类"兜底
    final root = (c != null && c.parentId != null)
        ? categories[c.parentId]
        : c;
    if (root == null) {
      unknown += b.amountCents;
      continue;
    }
    sums[root.id] = (sums[root.id] ?? 0) + b.amountCents;
  }
  final entries = [
    for (final e in sums.entries)
      (
        category: categories[e.key],
        name: categories[e.key]?.name ?? '未知分类',
        cents: e.value,
      ),
  ];
  if (unknown > 0) {
    entries.add((category: null, name: '未知分类', cents: unknown));
  }
  entries.sort((a, b) => b.cents.compareTo(a.cents));
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
    final cid = b.categoryId;
    // categoryId 为空（转账不进分类视图）归入"未细分"兜底
    if (c != null && cid != null && c.parentId == parent.id) {
      subSums[cid] = (subSums[cid] ?? 0) + b.amountCents;
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
