import 'package:drift/drift.dart';

import '../database.dart';
import '../../theme/app_colors.dart';

/// 标签仓储：标签的增删改查与账单-标签关联管理
///
/// 标签是跨分类的"场景/项目"维度，一笔账单可挂多个标签。
/// 颜色在新建时自动按色板循环分配，用户可在管理页修改。
class TagRepository {
  TagRepository(this._db);

  final AppDatabase _db;

  /// 监听全部标签（按 sortOrder 升序）
  Stream<List<Tag>> watchTags() {
    return (_db.select(_db.tags)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  /// 获取全部标签（按 sortOrder 升序）
  Future<List<Tag>> getTags() {
    return (_db.select(_db.tags)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 按 id 查单个标签
  Future<Tag?> getTagById(int id) {
    return (_db.select(_db.tags)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 获取某笔账单的全部标签（按 sortOrder 排序）
  Future<List<Tag>> getTagsByBillId(int billId) async {
    final tagIds = await (_db.select(_db.billTags)
          ..where((bt) => bt.billId.equals(billId)))
        .map((bt) => bt.tagId)
        .get();
    if (tagIds.isEmpty) return [];
    return (_db.select(_db.tags)
          ..where((t) => t.id.isIn(tagIds))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 批量获取多笔账单的标签（列表渲染用，返回 billId → 标签列表映射）
  Future<Map<int, List<Tag>>> getTagsByBillIds(List<int> billIds) async {
    if (billIds.isEmpty) return {};
    final rows = await (_db.select(_db.billTags)
          ..where((bt) => bt.billId.isIn(billIds)))
        .get();
    final tagIds = rows.map((r) => r.tagId).toSet().toList();
    if (tagIds.isEmpty) return {};
    final tags = await (_db.select(_db.tags)
          ..where((t) => t.id.isIn(tagIds)))
        .get();
    final tagMap = {for (final t in tags) t.id: t};
    final result = <int, List<Tag>>{};
    for (final r in rows) {
      final tag = tagMap[r.tagId];
      if (tag != null) {
        result.putIfAbsent(r.billId, () => []).add(tag);
      }
    }
    // 每个账单内按 sortOrder 排序
    for (final list in result.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return result;
  }

  /// 新建标签（名称幂等：同名返回已有 id）
  ///
  /// [color] 非空时使用指定颜色（标签管理页创建，用户自选）；
  /// 为空时自动按色板循环分配（钱迹导入等程序化场景）。
  Future<int> addTag(String name, {int? color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('标签名不能为空');
    }
    // 查重：名称完全匹配（首尾空格已 trim）
    final existing = await (_db.select(_db.tags)
          ..where((t) => t.name.equals(trimmed)))
        .getSingleOrNull();
    if (existing != null) return existing.id;

    // 自动分配颜色：按现有标签总数对色板取模，保证颜色均匀分布
    final count = await _db.tags.count().getSingle();
    final palette = AppColors.tagPalette;
    final finalColor = color ?? palette[count % palette.length];

    // sortOrder 追加到末尾
    final maxOrder = await (_db.selectOnly(_db.tags)
          ..addColumns([_db.tags.sortOrder.max()]))
        .map((r) => r.read(_db.tags.sortOrder.max()) ?? -1)
        .getSingle();

    return _db.into(_db.tags).insert(
          TagsCompanion.insert(
            name: trimmed,
            color: finalColor,
            sortOrder: Value(maxOrder + 1),
          ),
        );
  }

  /// 更新标签名与颜色
  Future<int> updateTag(int id, String name, int color) {
    return (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
          TagsCompanion(
            name: Value(name.trim()),
            color: Value(color),
          ),
        );
  }

  /// 统计引用该标签的账单数量（删除前确认弹窗提示用）
  Future<int> countBillsByTagId(int tagId) async {
    final rows = await (_db.select(_db.billTags)
          ..where((bt) => bt.tagId.equals(tagId)))
        .get();
    return rows.length;
  }

  /// 删除标签（级联删除 bill_tags 关联，不影响账单本身）
  ///
  /// 返回受影响的关联行数（供 UI 提示"有 N 笔账单使用此标签"）。
  Future<int> deleteTag(int id) {
    return _db.transaction(() async {
      final affected =
          await (_db.delete(_db.billTags)..where((bt) => bt.tagId.equals(id)))
              .go();
      await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
      return affected;
    });
  }

  /// 设置某笔账单的标签（全量替换：先删旧关联再插新，事务内保证原子性）
  Future<void> setBillTags(int billId, List<int> tagIds) {
    return _db.transaction(() async {
      await (_db.delete(_db.billTags)
            ..where((bt) => bt.billId.equals(billId)))
          .go();
      if (tagIds.isEmpty) return;
      // 去重 + 按 id 排序，保证插入顺序稳定
      final unique = tagIds.toSet().toList()..sort();
      await _db.batch((b) {
        b.insertAll(
          _db.billTags,
          [
            for (final tagId in unique)
              BillTagsCompanion.insert(billId: billId, tagId: tagId),
          ],
        );
      });
    });
  }

  /// 单笔账单的标签数量（记一笔页 #(N) 显示用，编辑回显时查询）
  Future<int> countTagsByBillId(int billId) async {
    final rows = await (_db.select(_db.billTags)
          ..where((bt) => bt.billId.equals(billId)))
        .get();
    return rows.length;
  }
}
