import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database_provider.dart';
import '../local/dao/sync_queue_dao.dart';
import '../local/dao/sync_metadata_dao.dart';
import '../local/database.dart';

/// 同步队列服务
///
/// 管理本地 → Supabase 的异步数据推送。
/// 写入操作先落本地 DB 并立即返回 UI，后台异步推送至 Supabase。
final syncQueueServiceProvider = Provider<SyncQueueService>((ref) {
  return SyncQueueService(
    dao: ref.watch(syncQueueDaoProvider),
    db: ref.watch(appDatabaseProvider),
  );
});

class SyncQueueService {
  final SyncQueueDao dao;
  final AppDatabase db;

  SyncQueueService({required this.dao, required this.db});

  /// 加入同步队列
  Future<void> enqueue({
    required String operationType,
    required String tableName,
    required String recordId,
    required String payload,
  }) async {
    await dao.enqueue(
      SyncQueueCompanion(
        operationType: Value(operationType),
        tblName: Value(tableName),
        recordId: Value(recordId),
        payload: Value(payload),
      ),
    );
  }

  /// 处理队列 — 推送至 Supabase
  ///
  /// 调用时机：记账后立即触发 + 应用启动时批量处理
  Future<void> processQueue() async {
    final items = await dao.getPendingItems();
    debugPrint('🟡 [同步链路-节点4] processQueue 被调用，待处理队列长度: ${items.length}');

    if (items.isEmpty) return;

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    // 未登录时不清空队列，等待下次登录后重试
    if (userId == null) {
      debugPrint('🔴 [同步链路-节点4] 跳过同步：userId 为 null（用户未登录）');
      return;
    }

    debugPrint('🟡 [同步链路-节点4] 当前登录 userId: $userId');

    for (final item in items) {
      try {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;
        debugPrint('🟡 [同步链路-节点4] 处理队列项: tbl=${item.tblName}, '
            'op=${item.operationType}, recordId=${item.recordId}, '
            'retryCount=${item.retryCount}');

        switch (item.tblName) {
          case 'records':
            await _pushRecord(supabase, userId, item.operationType, payload);
            break;
          case 'accounts':
            await _pushAccount(supabase, userId, item.operationType, payload);
            break;
          case 'categories':
            await _pushCategory(supabase, userId, item.operationType, payload);
            break;
          case 'budgets':
            await _pushBudget(supabase, userId, item.operationType, payload);
            break;
        }

        // 推送成功 → 标记记录为已同步并移出队列
        await _markRecordSynced(item.tblName, item.recordId);
        await dao.dequeue(item.id);
        debugPrint('🟢 [同步链路-节点4] 推送成功: ${item.tblName}.${item.recordId}');
      } catch (e) {
        debugPrint('🔴 [同步链路-节点4] 推送失败: ${item.tblName}.${item.recordId}, '
            '错误: $e, 重试次数: ${item.retryCount}');
        if (item.retryCount < 5) {
          await dao.incrementRetry(item.id);
        } else {
          // 超过最大重试次数，标记冲突并移出队列
          debugPrint('🔴 [同步链路-节点4] 超过最大重试次数，标记为冲突: ${item.recordId}');
          await _markRecordConflict(item.tblName, item.recordId);
          await dao.dequeue(item.id);
        }
      }
    }
  }

  /// 推送流水记录到 Supabase（UPSERT 模式）
  ///
  /// 统一使用 upsert (onConflict: 'id')，insert/update/delete 均走同一条路径。
  /// 软删除通过 payload 中的 deleted 字段控制。
  /// 推送后同步更新关联账户的余额。
  Future<void> _pushRecord(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final data = {
      'id': payload['id'],
      'user_id': userId,
      'account_id': payload['account_id'],
      'to_account_id': payload['to_account_id'],
      'amount': payload['amount'],
      'type': payload['type'],
      'category_id': payload['category_id'],
      'note': payload['note'],
      'occurred_at': payload['occurred_at'],
      'source': payload['source'] ?? 'manual',
      'sync_status': 'synced',
      'deleted': payload['deleted'] ?? false,
      'updated_at': payload['updated_at'] ?? now,
    };

    debugPrint('🟡 [同步链路-节点4] Supabase upsert records, '
        '请求体: ${jsonEncode(data)}');

    try {
      await supabase.from('records').upsert(data, onConflict: 'id');

      // ═══ 同步更新 Supabase 账户余额 ═══
      await _syncAccountBalance(supabase, userId, payload);

      debugPrint('🟢 [同步链路-节点4] Supabase upsert 成功: records ${payload['id']}');
    } catch (e) {
      debugPrint('🔴 [同步链路-节点4] Supabase upsert 失败: $e');
      rethrow;
    }
  }

  /// 同步关联账户的最新余额到 Supabase
  ///
  /// 从本地 DB 读取已更新的账户余额，推送至 Supabase accounts 表。
  Future<void> _syncAccountBalance(
    SupabaseClient supabase,
    String userId,
    Map<String, dynamic> payload,
  ) async {
    final accountId = payload['account_id'] as String?;
    if (accountId == null) return;

    try {
      final localAccount = await (db.select(db.accounts)
            ..where((t) => t.id.equals(accountId)))
          .getSingleOrNull();
      if (localAccount != null) {
        await supabase
            .from('accounts')
            .update({'balance': localAccount.balance})
            .eq('id', accountId);
        debugPrint('🟢 [同步链路-余额] 已更新 Supabase 账户余额: '
            '$accountId → ${localAccount.balance}');
      }

      // 转账场景：同步转入账户余额
      final toAccountId = payload['to_account_id'] as String?;
      if (toAccountId != null && toAccountId.isNotEmpty) {
        final toAccount = await (db.select(db.accounts)
              ..where((t) => t.id.equals(toAccountId)))
            .getSingleOrNull();
        if (toAccount != null) {
          await supabase
              .from('accounts')
              .update({'balance': toAccount.balance})
              .eq('id', toAccountId);
          debugPrint('🟢 [同步链路-余额] 已更新 Supabase 转入账户余额: '
              '$toAccountId → ${toAccount.balance}');
        }
      }
    } catch (e) {
      // 余额同步失败不阻塞流水已推送的事实，仅记录日志
      debugPrint('🔴 [同步链路-余额] 更新 Supabase 账户余额失败: $e');
    }
  }

  /// 推送账户到 Supabase（UPSERT 模式）
  Future<void> _pushAccount(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final data = {
      'id': payload['id'],
      'user_id': userId,
      'name': payload['name'],
      'type': payload['type'],
      'balance': payload['balance'],
      'currency': payload['currency'] ?? 'CNY',
      'is_liability': payload['is_liability'] ?? false,
      'include_in_net': payload['include_in_net'] ?? true,
      'is_archived': payload['is_archived'] ?? false,
      'deleted': payload['deleted'] ?? false,
      'updated_at': payload['updated_at'] ?? now,
    };

    await supabase.from('accounts').upsert(data, onConflict: 'id');
  }

  /// 推送分类到 Supabase（UPSERT 模式）
  Future<void> _pushCategory(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final data = {
      'id': payload['id'],
      'user_id': userId,
      'name': payload['name'],
      'parent_id': payload['parent_id'],
      'icon': payload['icon'],
      'kind': payload['kind'],
      'is_archived': payload['is_archived'] ?? false,
      'deleted': payload['deleted'] ?? false,
      'updated_at': payload['updated_at'] ?? now,
    };

    await supabase.from('categories').upsert(data, onConflict: 'id');
  }

  /// 推送预算到 Supabase（UPSERT 模式）
  Future<void> _pushBudget(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final data = {
      'id': payload['id'],
      'user_id': userId,
      'month': payload['month'],
      'type': payload['type'],
      'category_id': payload['category_id'],
      'target_amount': payload['target_amount'],
      'deleted': payload['deleted'] ?? false,
      'updated_at': payload['updated_at'] ?? now,
    };

    await supabase.from('budgets').upsert(data, onConflict: 'id');
  }

  /// 标记本地记录为已同步（所有表）
  Future<void> _markRecordSynced(String tableName, String recordId) async {
    switch (tableName) {
      case 'records':
        await (db.update(db.records)
              ..where((t) => t.id.equals(recordId)))
            .write(RecordsCompanion(syncStatus: const Value('synced')));
        break;
      case 'accounts':
        await (db.update(db.accounts)
              ..where((t) => t.id.equals(recordId)))
            .write(AccountsCompanion(syncStatus: const Value('synced')));
        break;
      case 'categories':
        await (db.update(db.categories)
              ..where((t) => t.id.equals(recordId)))
            .write(CategoriesCompanion(syncStatus: const Value('synced')));
        break;
      case 'budgets':
        await (db.update(db.budgets)
              ..where((t) => t.id.equals(recordId)))
            .write(BudgetsCompanion(syncStatus: const Value('synced')));
        break;
    }
  }

  /// 标记本地记录为冲突（所有表）
  Future<void> _markRecordConflict(String tableName, String recordId) async {
    switch (tableName) {
      case 'records':
        await (db.update(db.records)
              ..where((t) => t.id.equals(recordId)))
            .write(RecordsCompanion(syncStatus: const Value('conflict')));
        break;
      case 'accounts':
        await (db.update(db.accounts)
              ..where((t) => t.id.equals(recordId)))
            .write(AccountsCompanion(syncStatus: const Value('conflict')));
        break;
      case 'categories':
        await (db.update(db.categories)
              ..where((t) => t.id.equals(recordId)))
            .write(CategoriesCompanion(syncStatus: const Value('conflict')));
        break;
      case 'budgets':
        await (db.update(db.budgets)
              ..where((t) => t.id.equals(recordId)))
            .write(BudgetsCompanion(syncStatus: const Value('conflict')));
        break;
    }
  }

  /// 从 Supabase 增量拉取（支持 LWW 冲突解决）
  ///
  /// - 首次调用：全量拉取所有数据
  /// - 后续调用：仅拉取 updated_at >= last_pull_at 的变更
  /// - LWW：远端 updated_at >= 本地 → 云端覆盖；本地更新 → 保留本地
  Future<void> pullFromSupabase() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final metadataDao = SyncMetadataDao(db);
    final hasDoneInitialSync = await metadataDao.hasDoneInitialSync();

    DateTime? lastPullAt;
    if (hasDoneInitialSync) {
      lastPullAt = await metadataDao.getLastPullAt();
    }

    final pullStartTime = DateTime.now().toUtc();

    try {
      // ═══ 1. 拉取 accounts ═══
      final remoteAccounts = await _fetchIncremental(
        supabase.from('accounts').select().eq('user_id', userId),
        'updated_at',
        lastPullAt,
      );
      for (final a in remoteAccounts) {
        await _upsertAccountFromRemote(a);
      }

      // ═══ 2. 拉取 categories ═══
      final remoteCategories = await _fetchIncremental(
        supabase.from('categories').select().eq('user_id', userId),
        'updated_at',
        lastPullAt,
      );
      for (final c in remoteCategories) {
        await _upsertCategoryFromRemote(c);
      }

      // ═══ 3. 拉取 records ═══
      var recQuery = supabase
          .from('records')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);
      if (lastPullAt != null) {
        recQuery = _addIncrementalFilter(recQuery, 'updated_at', lastPullAt);
      } else {
        recQuery = recQuery.limit(500);
      }
      final remoteRecords = await recQuery;
      for (final r in remoteRecords) {
        await _upsertRecordFromRemote(r);
      }

      // ═══ 4. 拉取 budgets ═══
      final remoteBudgets = await _fetchIncremental(
        supabase.from('budgets').select().eq('user_id', userId),
        'updated_at',
        lastPullAt,
      );
      for (final b in remoteBudgets) {
        await _upsertBudgetFromRemote(b);
      }

      // ═══ 5. 记录本次拉取时间 ═══
      await metadataDao.setLastPullAt(pullStartTime);
      if (!hasDoneInitialSync) {
        await metadataDao.markInitialSyncDone();
      }

      debugPrint('🟢 [同步链路-Pull] 增量拉取完成');
    } catch (e) {
      debugPrint('🔴 [同步链路-Pull] 拉取失败: $e');
      // 拉取失败不阻塞本地使用
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 增量查询辅助（绕过 PostgrestTransformBuilder 类型限制）
  // ═══════════════════════════════════════════════════════════════

  /// 执行增量拉取查询（带可选 updated_at >= lastPullAt 过滤）
  Future<List<Map<String, dynamic>>> _fetchIncremental(
    dynamic queryBuilder,
    String column,
    DateTime? lastPullAt,
  ) async {
    if (lastPullAt != null) {
      queryBuilder = queryBuilder.gte(column, lastPullAt.toIso8601String());
    }
    return await queryBuilder;
  }

  /// 向已有查询追加增量过滤条件
  dynamic _addIncrementalFilter(
    dynamic queryBuilder,
    String column,
    DateTime lastPullAt,
  ) {
    return queryBuilder.gte(column, lastPullAt.toIso8601String());
  }

  // ═══════════════════════════════════════════════════════════════
  // LWW upsert 辅助方法
  // ═══════════════════════════════════════════════════════════════

  /// LWW: 从远端 account 数据 upsert 到本地
  Future<void> _upsertAccountFromRemote(Map<String, dynamic> a) async {
    final remoteUpdatedAt = DateTime.parse(a['updated_at']);
    final isDeleted = a['deleted'] == true;

    final local = await (db.select(db.accounts)
          ..where((t) => t.id.equals(a['id'])))
        .getSingleOrNull();

    if (local == null) {
      // 本地不存在 → 插入
      await db.into(db.accounts).insert(_accountCompanionFromRemote(a));
      return;
    }

    // 本地存在 → LWW 判断
    if (isDeleted) {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.accounts)..where((t) => t.id.equals(a['id'])))
            .write(AccountsCompanion(
              deleted: const Value(true),
              updatedAt: Value(remoteUpdatedAt),
            ));
        await _logConflict(a['id'], 'accounts', local.updatedAt, remoteUpdatedAt);
      }
    } else {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.accounts)..where((t) => t.id.equals(a['id'])))
            .write(_accountCompanionFromRemote(a));
        if (local.updatedAt.isAfter(remoteUpdatedAt)) {
          await _logConflict(a['id'], 'accounts', local.updatedAt, remoteUpdatedAt);
        }
      }
    }
  }

  /// LWW: 从远端 category 数据 upsert 到本地
  Future<void> _upsertCategoryFromRemote(Map<String, dynamic> c) async {
    final remoteUpdatedAt = DateTime.parse(c['updated_at']);
    final isDeleted = c['deleted'] == true;

    final local = await (db.select(db.categories)
          ..where((t) => t.id.equals(c['id'])))
        .getSingleOrNull();

    if (local == null) {
      await db.into(db.categories).insert(_categoryCompanionFromRemote(c));
      return;
    }

    if (isDeleted) {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.categories)..where((t) => t.id.equals(c['id'])))
            .write(CategoriesCompanion(
              deleted: const Value(true),
              updatedAt: Value(remoteUpdatedAt),
            ));
        await _logConflict(c['id'], 'categories', local.updatedAt, remoteUpdatedAt);
      }
    } else {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.categories)..where((t) => t.id.equals(c['id'])))
            .write(_categoryCompanionFromRemote(c));
        if (local.updatedAt.isAfter(remoteUpdatedAt)) {
          await _logConflict(c['id'], 'categories', local.updatedAt, remoteUpdatedAt);
        }
      }
    }
  }

  /// LWW: 从远端 record 数据 upsert 到本地
  Future<void> _upsertRecordFromRemote(Map<String, dynamic> r) async {
    final remoteUpdatedAt = DateTime.parse(r['updated_at']);
    final isDeleted = r['deleted'] == true;

    final local = await (db.select(db.records)
          ..where((t) => t.id.equals(r['id'])))
        .getSingleOrNull();

    if (local == null) {
      await db.into(db.records).insert(_recordCompanionFromRemote(r));
      return;
    }

    if (isDeleted) {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.records)..where((t) => t.id.equals(r['id'])))
            .write(RecordsCompanion(
              deleted: const Value(true),
              updatedAt: Value(remoteUpdatedAt),
              syncStatus: const Value('synced'),
            ));
        await _logConflict(r['id'], 'records', local.updatedAt, remoteUpdatedAt);
      }
    } else {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.records)..where((t) => t.id.equals(r['id'])))
            .write(_recordCompanionFromRemote(r));
        if (local.updatedAt.isAfter(remoteUpdatedAt)) {
          await _logConflict(r['id'], 'records', local.updatedAt, remoteUpdatedAt);
        }
      }
    }
  }

  /// LWW: 从远端 budget 数据 upsert 到本地
  Future<void> _upsertBudgetFromRemote(Map<String, dynamic> b) async {
    final remoteUpdatedAt = DateTime.parse(b['updated_at']);
    final isDeleted = b['deleted'] == true;

    final local = await (db.select(db.budgets)
          ..where((t) => t.id.equals(b['id'])))
        .getSingleOrNull();

    if (local == null) {
      await db.into(db.budgets).insert(_budgetCompanionFromRemote(b));
      return;
    }

    if (isDeleted) {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.budgets)..where((t) => t.id.equals(b['id'])))
            .write(BudgetsCompanion(
              deleted: const Value(true),
              updatedAt: Value(remoteUpdatedAt),
            ));
        await _logConflict(b['id'], 'budgets', local.updatedAt, remoteUpdatedAt);
      }
    } else {
      if (!remoteUpdatedAt.isBefore(local.updatedAt)) {
        await (db.update(db.budgets)..where((t) => t.id.equals(b['id'])))
            .write(_budgetCompanionFromRemote(b));
        if (local.updatedAt.isAfter(remoteUpdatedAt)) {
          await _logConflict(b['id'], 'budgets', local.updatedAt, remoteUpdatedAt);
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 远端数据 → Drift Companion 映射
  // ═══════════════════════════════════════════════════════════════

  AccountsCompanion _accountCompanionFromRemote(Map<String, dynamic> a) {
    return AccountsCompanion(
      id: Value(a['id']),
      userId: Value(a['user_id']),
      name: Value(a['name']),
      type: Value(a['type']),
      balance: Value((a['balance'] as num).toDouble()),
      currency: Value(a['currency'] ?? 'CNY'),
      isLiability: Value(a['is_liability'] ?? false),
      includeInNet: Value(a['include_in_net'] ?? true),
      isArchived: Value(a['is_archived'] ?? false),
      deleted: Value(a['deleted'] ?? false),
      sortOrder: Value(a['sort_order'] ?? 0),
      createdAt: Value(DateTime.parse(a['created_at'])),
      updatedAt: Value(DateTime.parse(a['updated_at'])),
      syncStatus: const Value('synced'),
    );
  }

  CategoriesCompanion _categoryCompanionFromRemote(Map<String, dynamic> c) {
    return CategoriesCompanion(
      id: Value(c['id']),
      userId: Value(c['user_id']),
      name: Value(c['name']),
      parentId: Value.absentIfNull(c['parent_id']),
      icon: Value.absentIfNull(c['icon']),
      kind: Value(c['kind']),
      sortOrder: Value(c['sort_order'] ?? 0),
      isArchived: Value(c['is_archived'] ?? false),
      deleted: Value(c['deleted'] ?? false),
      updatedAt: Value(DateTime.parse(c['updated_at'])),
      syncStatus: const Value('synced'),
    );
  }

  RecordsCompanion _recordCompanionFromRemote(Map<String, dynamic> r) {
    return RecordsCompanion(
      id: Value(r['id']),
      userId: Value(r['user_id']),
      accountId: Value(r['account_id']),
      toAccountId: Value.absentIfNull(r['to_account_id']),
      amount: Value((r['amount'] as num).toDouble()),
      type: Value(r['type']),
      categoryId: Value.absentIfNull(r['category_id']),
      note: Value.absentIfNull(r['note']),
      occurredAt: Value(DateTime.parse(r['occurred_at'])),
      createdAt: Value(DateTime.parse(r['created_at'])),
      updatedAt: Value(DateTime.parse(r['updated_at'])),
      syncStatus: const Value('synced'),
      source: Value(r['source'] ?? 'manual'),
      deleted: Value(r['deleted'] ?? false),
    );
  }

  BudgetsCompanion _budgetCompanionFromRemote(Map<String, dynamic> b) {
    return BudgetsCompanion(
      id: Value(b['id']),
      userId: Value(b['user_id']),
      month: Value(b['month']),
      type: Value(b['type']),
      categoryId: Value.absentIfNull(b['category_id']),
      targetAmount: Value((b['target_amount'] as num).toDouble()),
      deleted: Value(b['deleted'] ?? false),
      updatedAt: Value(DateTime.parse(b['updated_at'])),
      syncStatus: const Value('synced'),
    );
  }

  /// 记录冲突日志（本地被云端覆盖时）
  Future<void> _logConflict(
    String recordId,
    String tableName,
    DateTime localUpdatedAt,
    DateTime remoteUpdatedAt,
  ) async {
    try {
      await db.into(db.conflictLog).insert(
            ConflictLogCompanion(
              recordId: Value(recordId),
              tblName: Value(tableName),
              localUpdatedAt: Value(localUpdatedAt.toIso8601String()),
              remoteUpdatedAt: Value(remoteUpdatedAt.toIso8601String()),
              resolution: const Value('remote_wins'),
            ),
          );
    } catch (_) {
      // 日志写入失败不阻塞同步
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 定时同步调度
  // ═══════════════════════════════════════════════════════════════

  Timer? _syncTimer;

  /// 启动后台定时同步（前台每 5 分钟）
  void startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      pullFromSupabase().catchError((e) {
        debugPrint('定时同步拉取失败: $e');
      });
      processQueue().catchError((e) {
        debugPrint('定时同步推送失败: $e');
      });
    });
  }

  /// 停止定时同步
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
}
