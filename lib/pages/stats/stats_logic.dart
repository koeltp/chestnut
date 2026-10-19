import '../../data/database.dart';
import '../../models/enums.dart';
import 'stats_query.dart';

/// 统计页纯逻辑：主体过滤与分类聚合
///
/// 与 UI 解耦便于单元测试，主页面在 _buildBody 中调用。

/// 环图/排行条目：category 为 null = 分类已删除或未细分
/// （点击行为由宿主决定，如列出这批账单）
typedef CategoryEntry = ({Category? category, String name, int cents});

/// 账单归属的一级分类：二级上浮一级；分类已删除返回 null
/// （配合"删除分类强制迁移"策略，正常数据下不应出现 null）
Category? rootCategoryOf(Bill b, Map<int, Category> categories) {
  final c = categories[b.categoryId];
  if (c == null) return null;
  return c.parentId == null ? c : categories[c.parentId];
}

/// 主体过滤（单遍完成全部条件，取代原来日期/关键词/分类多遍链）：
/// - 转账账单显式排除（转账不挂分类，不参与任何统计口径）
/// - 日期：[start, end)，null = 不限制
/// - 关键词：定位完整信息/备注/分类名任一包含（英文统一转小写
///   比较，中文不受影响）
/// - 分类：按视图身份取口径——
///   · category：视图分类 + 其全部子分类
///   · uncategorized：仅直挂视图分类的账单
///   · all：多选条件命中二级精确命中、命中一级即含全部子分类（与
///     聚合上浮口径一致）
List<Bill> filterBills(
  List<Bill> bills, {
  required Map<int, Category> categories,
  required (DateTime?, DateTime?) range,
  String keyword = '',
  StatsViewType view = StatsViewType.all,
  int? viewCategoryId,
  Set<int> filterCategoryIds = const {},
}) {
  final (start, end) = range;
  final kw = keyword.trim().toLowerCase();
  return bills.where((b) {
    if (b.type == BillType.transfer) return false;
    if (start != null && b.date.isBefore(start)) return false;
    if (end != null && !b.date.isBefore(end)) return false;
    if (kw.isNotEmpty &&
        !(b.locationFull ?? '').toLowerCase().contains(kw) &&
        !(b.note ?? '').toLowerCase().contains(kw) &&
        !(categories[b.categoryId]?.name ?? '').toLowerCase().contains(kw)) {
      return false;
    }
    switch (view) {
      case StatsViewType.category:
        final c = categories[b.categoryId];
        return b.categoryId == viewCategoryId ||
            (c != null && c.parentId == viewCategoryId);
      case StatsViewType.uncategorized:
        return b.categoryId == viewCategoryId;
      case StatsViewType.all:
        if (filterCategoryIds.isEmpty) return true;
        final root = rootCategoryOf(b, categories);
        if (root == null) return false;
        return filterCategoryIds.contains(b.categoryId) ||
            filterCategoryIds.contains(root.id);
    }
  }).toList();
}

/// 按一级分类聚合（全部视图环图/排行共用）：金额降序；
/// 二级分类的账单上浮归并到所属一级（火车→交通），总览只保持
/// 一级粒度，二级明细留给钻取后的分类视图"子分类构成"环图
List<CategoryEntry> aggregateByCategory(
  List<Bill> bills,
  Map<int, Category> categories,
) {
  final sums = <int, int>{};
  for (final b in bills) {
    // 二级上浮一级：parentId 指向的一级理论上必存在（外键约束），
    // 且删除分类已强制迁移，root 为 null 的账单直接跳过兜底
    final root = rootCategoryOf(b, categories);
    if (root == null) continue;
    sums[root.id] = (sums[root.id] ?? 0) + b.amountCents;
  }
  final entries = [
    for (final e in sums.entries)
      (category: categories[e.key], name: categories[e.key]!.name, cents: e.value),
  ];
  entries.sort((a, b) => b.cents.compareTo(a.cents));
  return entries;
}

/// 子分类构成数据（一级分类视图）：按子分类聚合；
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
      (category: categories[e.key], name: categories[e.key]!.name, cents: e.value),
  ];
  if (direct > 0) entries.add((category: null, name: '未细分', cents: direct));
  entries.sort((a, b) => b.cents.compareTo(a.cents));
  return entries;
}
