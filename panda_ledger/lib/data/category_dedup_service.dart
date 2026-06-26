import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local/app_database_provider.dart';
import 'local/database.dart';
import 'sync/sync_queue_dao_provider.dart';

final categoryDedupServiceProvider = Provider<CategoryDedupService>((ref) {
  return CategoryDedupService(
    db: ref.read(appDatabaseProvider),
    syncQueue: ref.read(syncQueueServiceProvider),
  );
});

/// 一级分类去重服务
///
/// 历史数据中可能存在同 kind 下同名的一级分类（各自挂有流水和子分类），
/// 导致统计页出现重复条目。
///
/// 本服务在每次应用启动时调用 [deduplicateOnce] 做一次检测：
/// - 无重复分类：一条 SQL 即返回，性能开销可忽略
/// - 有重复分类：保留 [updated_at] 最早的一个，将其余的子分类和流水
///   全部迁移过来后软删除，并推入同步队列上云
class CategoryDedupService {
  final AppDatabase db;
  final SyncQueueService syncQueue;

  CategoryDedupService({required this.db, required this.syncQueue});

  /// 检测并合并重复一级分类，返回处理掉的多余分类数量（0 = 无重复）
  Future<int> deduplicateOnce() async {
    final groups = await _findDuplicateParentGroups();
    if (groups.isEmpty) return 0;

    debugPrint('🟡 [分类去重] 发现 ${groups.length} 组重复，开始处理…');
    var removedCount = 0;

    for (final g in groups) {
      // 同 kind+name 的一级分类，按 updated_at ASC 排序：最早的保留
      final duplicates = await (db.select(db.categories)
            ..where((t) =>
                t.name.equals(g.name) &
                t.kind.equals(g.kind) &
                t.parentId.isNull() &
                t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
          .get();

      if (duplicates.length < 2) continue;

      final keepCat = duplicates.first;
      for (final removeCat in duplicates.sublist(1)) {
        await _mergeInto(from: removeCat, into: keepCat);
        removedCount++;
      }
    }

    debugPrint('✅ [分类去重] 完成，共处理 $removedCount 个多余分类');
    return removedCount;
  }

  // ───────────────────────────────────────────────────────────────
  // 公开操作方法（供归档流程使用）
  // ───────────────────────────────────────────────────────────────

  /// 将 [from] 的流水迁移到 [into] 并软删除 [from]（不处理子分类）
  ///
  /// 供归档/清理时手动触发的迁移，子分类由调用方单独决策。
  Future<void> mergeRecords({
    required Category from,
    required Category into,
  }) async {
    final now = DateTime.now();

    // 迁移流水 category_id
    final records = await (db.select(db.records)
          ..where((t) => t.categoryId.equals(from.id) & t.deleted.equals(false)))
        .get();

    for (final record in records) {
      await (db.update(db.records)..where((t) => t.id.equals(record.id)))
          .write(RecordsCompanion(
            categoryId: Value(into.id),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ));
      syncQueue.enqueue(
        operationType: 'update',
        tableName: 'records',
        recordId: record.id,
        payload: jsonEncode({
          'id': record.id,
          'account_id': record.accountId,
          'to_account_id': record.toAccountId,
          'amount': record.amount,
          'type': record.type,
          'category_id': into.id,
          'note': record.note,
          'occurred_at': record.occurredAt.toIso8601String(),
          'source': record.source,
          'deleted': false,
          'updated_at': now.toUtc().toIso8601String(),
        }),
      );
    }

    // 软删除 from
    await softDeleteCategory(from);
    debugPrint('✅ [分类迁移] ${from.id} → ${into.id}，${records.length} 条流水已迁移');
  }

  /// 软删除分类并入同步队列
  Future<void> softDeleteCategory(Category category) async {
    final now = DateTime.now();
    await (db.update(db.categories)..where((t) => t.id.equals(category.id)))
        .write(CategoriesCompanion(
          deleted: const Value(true),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ));
    syncQueue.enqueue(
      operationType: 'update',
      tableName: 'categories',
      recordId: category.id,
      payload: jsonEncode({
        'id': category.id,
        'name': category.name,
        'parent_id': category.parentId,
        'icon': category.icon,
        'kind': category.kind,
        'is_archived': category.isArchived,
        'deleted': true,
      }),
    );
  }

  // ───────────────────────────────────────────────────────────────
  // 私有实现
  // ───────────────────────────────────────────────────────────────

  /// 将 [from] 的子分类与流水全部迁移到 [into]，然后软删除 [from]
  /// 供 deduplicateOnce 自动合并时使用（会同时处理子分类）
  Future<void> _mergeInto({
    required Category from,
    required Category into,
  }) async {
    final now = DateTime.now();
    debugPrint('🟡 [分类去重] 合并「${from.name}」: ${from.id} → ${into.id}');

    // ── 1. 迁移子分类 parent_id ──
    final children = await (db.select(db.categories)
          ..where((t) => t.parentId.equals(from.id) & t.deleted.equals(false)))
        .get();

    for (final child in children) {
      await (db.update(db.categories)..where((t) => t.id.equals(child.id)))
          .write(CategoriesCompanion(
            parentId: Value(into.id),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ));
      syncQueue.enqueue(
        operationType: 'update',
        tableName: 'categories',
        recordId: child.id,
        payload: jsonEncode({
          'id': child.id,
          'name': child.name,
          'parent_id': into.id,
          'icon': child.icon,
          'kind': child.kind,
          'is_archived': child.isArchived,
          'deleted': false,
        }),
      );
    }

    // ── 2. 迁移流水 + 软删除 from（复用公开方法）──
    await mergeRecords(from: from, into: into);
    debugPrint('✅ [分类去重] ${from.id} 已合并：${children.length} 个子分类');
  }

  /// 用 SQL 找出同 kind+name 下存在多个一级分类的 (name, kind) 组合
  Future<List<({String name, String kind})>> _findDuplicateParentGroups() async {
    final rows = await db.customSelect(
      '''SELECT name, kind FROM categories
         WHERE parent_id IS NULL AND deleted = 0
         GROUP BY name, kind
         HAVING COUNT(*) > 1''',
      readsFrom: {db.categories},
    ).get();
    return rows
        .map((r) => (name: r.read<String>('name'), kind: r.read<String>('kind')))
        .toList();
  }
}
