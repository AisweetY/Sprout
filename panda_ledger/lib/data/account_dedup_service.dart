import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local/app_database_provider.dart';
import 'local/database.dart';
import 'sync/sync_queue_dao_provider.dart';

final accountDedupServiceProvider = Provider<AccountDedupService>((ref) {
  return AccountDedupService(
    db: ref.read(appDatabaseProvider),
    syncQueue: ref.read(syncQueueServiceProvider),
  );
});

/// 账户去重服务
///
/// 解决「本地模式使用后首次登录」场景下的重复账户问题：
///
/// 复现路径：
///   1. 全新安装 → 进入本地模式 → seed 创建「现金」账户（UUID-A，userId='local'）
///   2. 用户登录 → pullFromSupabase() 拉取云端已有「现金」账户（UUID-X）
///   3. pull 按 id 去重，UUID-A ≠ UUID-X → 两条账户共存 → 用户看到两个「现金」
///
/// 处理策略：
///   - 按 (name, type) 发现同名账户组
///   - 保留 updated_at 最早的（通常是云端已有数据），软删除其余
///   - 将引用被删除账户的流水（account_id / to_account_id）迁移到保留账户
///   - 所有变更入同步队列上云
class AccountDedupService {
  final AppDatabase db;
  final SyncQueueService syncQueue;

  AccountDedupService({required this.db, required this.syncQueue});

  /// 检测并合并重复账户，返回处理掉的多余账户数量（0 = 无重复）
  ///
  /// 幂等：无重复时仅一条 SQL 查询，可在每次启动 / 恢复时安全调用。
  Future<int> deduplicateOnce() async {
    final groups = await _findDuplicateGroups();
    if (groups.isEmpty) return 0;

    debugPrint('🟡 [账户去重] 发现 ${groups.length} 组重复账户，开始处理…');
    var removedCount = 0;

    for (final g in groups) {
      // 同 name+type 的活跃账户，按 updated_at ASC 排序：最早的保留
      // 云端既有数据的 updated_at 通常早于本地 seed（seed 在 pull 之后才运行）
      final accounts = await (db.select(db.accounts)
            ..where((t) =>
                t.name.equals(g.name) &
                t.type.equals(g.type) &
                t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
          .get();

      if (accounts.length < 2) continue;

      final keeper = accounts.first;
      for (final loser in accounts.sublist(1)) {
        await _mergeInto(from: loser, into: keeper);
        removedCount++;
      }
    }

    debugPrint('✅ [账户去重] 完成，共处理 $removedCount 个多余账户');
    return removedCount;
  }

  /// 将 [from] 账户的所有流水迁移到 [into]，然后软删除 [from]
  Future<void> _mergeInto({required Account from, required Account into}) async {
    final now = DateTime.now().toUtc();
    debugPrint('🟡 [账户去重] 合并「${from.name}」: ${from.id} → ${into.id}');

    // ── 1. 迁移借方流水（account_id = from.id） ──
    final asSource = await (db.select(db.records)
          ..where((t) => t.accountId.equals(from.id) & t.deleted.equals(false)))
        .get();

    for (final r in asSource) {
      await (db.update(db.records)..where((t) => t.id.equals(r.id)))
          .write(RecordsCompanion(
            accountId: Value(into.id),
            syncStatus: const Value('pending'),
            updatedAt: Value(now),
          ));
      await syncQueue.enqueue(
        operationType: 'upsert',
        tableName: 'records',
        recordId: r.id,
        payload: jsonEncode({
          'id': r.id,
          'account_id': into.id,
          'to_account_id': r.toAccountId,
          'amount': r.amount,
          'type': r.type,
          'category_id': r.categoryId,
          'note': r.note,
          'occurred_at': r.occurredAt.toUtc().toIso8601String(),
          'source': r.source,
          'deleted': r.deleted,
          'updated_at': now.toIso8601String(),
        }),
      );
    }

    // ── 2. 迁移转账目标流水（to_account_id = from.id） ──
    final asTarget = await (db.select(db.records)
          ..where((t) => t.toAccountId.equals(from.id) & t.deleted.equals(false)))
        .get();

    for (final r in asTarget) {
      // 若该记录 account_id 也指向 from（步骤1已更新 DB，但 r 是快照），
      // payload 中需同样使用 into.id
      final newAccountId = r.accountId == from.id ? into.id : r.accountId;
      await (db.update(db.records)..where((t) => t.id.equals(r.id)))
          .write(RecordsCompanion(
            toAccountId: Value(into.id),
            syncStatus: const Value('pending'),
            updatedAt: Value(now),
          ));
      await syncQueue.enqueue(
        operationType: 'upsert',
        tableName: 'records',
        recordId: r.id,
        payload: jsonEncode({
          'id': r.id,
          'account_id': newAccountId,
          'to_account_id': into.id,
          'amount': r.amount,
          'type': r.type,
          'category_id': r.categoryId,
          'note': r.note,
          'occurred_at': r.occurredAt.toUtc().toIso8601String(),
          'source': r.source,
          'deleted': r.deleted,
          'updated_at': now.toIso8601String(),
        }),
      );
    }

    // ── 3. 软删除 from 账户并入同步队列 ──
    await (db.update(db.accounts)..where((t) => t.id.equals(from.id)))
        .write(AccountsCompanion(
          deleted: const Value(true),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ));
    await syncQueue.enqueue(
      operationType: 'upsert',
      tableName: 'accounts',
      recordId: from.id,
      payload: jsonEncode({
        'id': from.id,
        'name': from.name,
        'type': from.type,
        'balance': from.balance,
        'currency': from.currency,
        'is_liability': from.isLiability,
        'include_in_net': from.includeInNet,
        'is_archived': from.isArchived,
        'deleted': true,
        'updated_at': now.toIso8601String(),
      }),
    );

    debugPrint('✅ [账户去重] ${from.id} 已合并：'
        '${asSource.length} 条借方 + ${asTarget.length} 条转账目标流水已迁移');
  }

  /// 用 SQL 找出同 name+type 下存在多个活跃账户的分组
  Future<List<({String name, String type})>> _findDuplicateGroups() async {
    final rows = await db.customSelect(
      '''SELECT name, type FROM accounts
         WHERE deleted = 0
         GROUP BY name, type
         HAVING COUNT(*) > 1''',
      readsFrom: {db.accounts},
    ).get();
    return rows
        .map((r) => (name: r.read<String>('name'), type: r.read<String>('type')))
        .toList();
  }
}
