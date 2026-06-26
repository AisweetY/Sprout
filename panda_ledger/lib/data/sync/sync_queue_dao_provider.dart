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

  /// 并发保护：防止启动/恢复/定时器/写入同时处理同一批队列项
  bool _isProcessing = false;
  bool _needsReprocess = false;

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
  /// 调用时机：记账后立即触发 + 应用启动时批量处理。
  /// 内置并发保护：若已有处理在进行中，标记需要重新处理而非并发执行。
  Future<void> processQueue() async {
    // ═══ 并发保护：若已在处理，标记需要重处理 ═══
    if (_isProcessing) {
      _needsReprocess = true;
      debugPrint('🟡 [同步链路-节点4] processQueue 已在处理中，标记延迟重处理');
      return;
    }

    _isProcessing = true;
    _needsReprocess = false;

    try {
      await _processQueueInternal();
    } finally {
      _isProcessing = false;
      // ═══ 处理期间有新入队请求 → 再跑一次 ═══
      if (_needsReprocess) {
        _needsReprocess = false;
        debugPrint('🟡 [同步链路-节点4] 执行延迟重处理');
        // 不递归调用，调度到下一微任务避免栈溢出
        Future.microtask(() => processQueue());
      }
    }
  }

  /// processQueue 的内部实现，由 processQueue() 加锁后调用
  Future<void> _processQueueInternal() async {
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

        // ═══ 网络不可达：保留队列项，不消耗重试配额 ═══
        if (_isNetworkUnreachable(e)) {
          debugPrint('🟡 [同步链路-节点4] 网络不可达，保留剩余 ${items.length - items.indexOf(item)} 个队列项等待网络恢复');
          return; // 跳出 for 循环，所有未处理项留在队列里
        }

        // ═══ 服务端/数据错误：正常重试计数 ═══
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
      debugPrint('🔴 [同步链路-余额] 更新 Supabase 账户余额失败: $e');
      // 余额同步失败不应阻止记录出队：记录本身已成功写入 Supabase，
      // 账户余额可通过下次 pull 或其他同步周期自行修复。不 rethrow。
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

  /// 判断异常是否为网络不可达（断网/DNS 失败/超时/连接被拒）
  ///
  /// 这类错误重试无意义，应保留队列项等待网络恢复；
  /// 与服务端错误（4xx/5xx）区分，后者才消耗重试次数。
  bool _isNetworkUnreachable(Object e) {
    final msg = e.toString().toLowerCase();
    const unreachablePatterns = [
      'socketexception',
      'timeoutexception',
      'handshakeexception',
      'clientsocketexception',
      'connection refused',
      'connection reset',
      'network is unreachable',
      'no route to host',
      'host lookup failed',
      'failed host lookup',
      'connection timed out',
      'connection closed',
      'connection failed',
      'network error',
      'internet connection',
      'websocketexception',
    ];
    return unreachablePatterns.any((p) => msg.contains(p));
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
      if (lastPullAt != null) {
        // 增量拉取：仅拉取 updated_at >= lastPullAt 的变更
        final remoteRecords = await supabase
            .from('records')
            .select()
            .eq('user_id', userId)
            .gte('updated_at', lastPullAt.toIso8601String())
            .order('updated_at', ascending: false);
        for (final r in remoteRecords) {
          await _upsertRecordFromRemote(r);
        }
      } else {
        // 首次全量拉取：分页遍历，避免 limit(500) 截断旧数据。
        // 使用 range offset 而非 updated_at > cursor，防止同时间戳漏数据。
        int offset = 0;
        bool hasMore = true;
        while (hasMore) {
          final page = await supabase
              .from('records')
              .select()
              .eq('user_id', userId)
              .order('updated_at', ascending: true)
              .order('id')
              .range(offset, offset + 499); // 500 条/页
          for (final r in page) {
            await _upsertRecordFromRemote(r);
          }
          if ((page as List).length < 500) {
            hasMore = false;
          } else {
            offset += 500;
          }
        }
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

  /// 启动时一致性对账：将 sync_status != 'synced' 的记录重新入队
  ///
  /// 覆盖场景：
  ///   - processQueue 中途被 App 强杀 — 部分记录推送成功但本地未标记 synced
  ///   - 记录因 5xx 被标记 conflict 出队，但 Supabase 后来恢复了
  ///   - 网络恢复后之前"掉队"的记录自动找回
  ///
  /// 不做云端查询：upsert 是幂等的，直接入队让 processQueue 处理即可。
  /// 通常在 pullFromSupabase + processQueue 完成后调用。
  Future<void> reconcileOnStartup() async {
    debugPrint('🟡 [对账] 开始启动一致性对账...');

    final tables = ['records', 'accounts', 'categories', 'budgets'];
    int totalReenqueued = 0;

    for (final tableName in tables) {
      final count = await _reconcileTable(tableName);
      totalReenqueued += count;
    }

    if (totalReenqueued > 0) {
      debugPrint('🟢 [对账] 一致性对账完成，重新入队 $totalReenqueued 条记录');
    } else {
      debugPrint('🟢 [对账] 一致性对账完成，无需修复');
    }
  }

  /// 对单张表：找到 sync_status != 'synced' 的记录，重新入队
  Future<int> _reconcileTable(String tableName) async {
    final localIds = await _getUnsyncedIds(tableName);
    if (localIds.isEmpty) return 0;

    debugPrint('🟡 [对账] $tableName: 发现 ${localIds.length} 条未同步记录，重新入队...');

    int reenqueuedCount = 0;
    for (final id in localIds) {
      final enqueued = await _reenqueueMissing(tableName, id);
      if (enqueued) reenqueuedCount++;
    }

    if (reenqueuedCount > 0) {
      debugPrint('🟢 [对账] $tableName: 重新入队 $reenqueuedCount 条');
    }
    return reenqueuedCount;
  }

  /// 获取表中 sync_status != 'synced' 的记录 ID 列表
  Future<List<String>> _getUnsyncedIds(String tableName) async {
    switch (tableName) {
      case 'records':
        // records 不过滤 deleted：软删除也是需要同步到云端的变更
        final rows = await (db.select(db.records)
              ..where((t) => t.syncStatus.equals('pending') | t.syncStatus.equals('conflict')))
            .get();
        return rows.map((r) => r.id).toList();
      case 'accounts':
        final rows = await (db.select(db.accounts)
              ..where((t) => t.syncStatus.equals('pending') | t.syncStatus.equals('conflict')))
            .get();
        return rows.map((r) => r.id).toList();
      case 'categories':
        final rows = await (db.select(db.categories)
              ..where((t) => t.syncStatus.equals('pending') | t.syncStatus.equals('conflict')))
            .get();
        return rows.map((r) => r.id).toList();
      case 'budgets':
        final rows = await (db.select(db.budgets)
              ..where((t) => t.syncStatus.equals('pending') | t.syncStatus.equals('conflict')))
            .get();
        return rows.map((r) => r.id).toList();
      default:
        return [];
    }
  }

  /// 将缺失的云端记录重新入队，返回 true 表示实际入队了
  Future<bool> _reenqueueMissing(String tableName, String recordId) async {
    // 避免重复入队：检查是否已在队列中
    final existing = await (db.select(db.syncQueue)
          ..where((t) => t.recordId.equals(recordId) & t.tblName.equals(tableName)))
        .getSingleOrNull();
    if (existing != null) return false;

    // 从本地读取当前数据，构建 payload
    final payload = await _buildPayloadFromLocal(tableName, recordId);
    if (payload == null) return false;

    await dao.enqueue(
      SyncQueueCompanion(
        operationType: const Value('upsert'),
        tblName: Value(tableName),
        recordId: Value(recordId),
        payload: Value(payload),
      ),
    );
    return true;
  }

  /// 从本地 DB 读取记录数据并构建同步 payload
  Future<String?> _buildPayloadFromLocal(String tableName, String recordId) async {
    switch (tableName) {
      case 'records':
        final row = await (db.select(db.records)..where((t) => t.id.equals(recordId))).getSingleOrNull();
        if (row == null) return null;
        return jsonEncode({
          'id': row.id,
          'account_id': row.accountId,
          'to_account_id': row.toAccountId,
          'amount': row.amount,
          'type': row.type,
          'category_id': row.categoryId,
          'note': row.note,
          // ⚑ toUtc()：对账重推时同样需要 UTC，否则 timestamptz 偏移 +8h
          'occurred_at': row.occurredAt.toUtc().toIso8601String(),
          'source': row.source,
          'deleted': row.deleted,
          'updated_at': row.updatedAt.toUtc().toIso8601String(),
        });
      case 'accounts':
        final row = await (db.select(db.accounts)..where((t) => t.id.equals(recordId))).getSingleOrNull();
        if (row == null) return null;
        return jsonEncode({
          'id': row.id,
          'name': row.name,
          'type': row.type,
          'balance': row.balance,
          'currency': 'CNY',
          'is_liability': row.isLiability,
          'include_in_net': row.includeInNet,
          'is_archived': row.isArchived,
          'deleted': row.deleted,
          'updated_at': row.updatedAt.toIso8601String(),
        });
      case 'categories':
        final row = await (db.select(db.categories)..where((t) => t.id.equals(recordId))).getSingleOrNull();
        if (row == null) return null;
        return jsonEncode({
          'id': row.id,
          'name': row.name,
          'parent_id': row.parentId,
          'icon': row.icon,
          'kind': row.kind,
          'is_archived': row.isArchived,
          'deleted': row.deleted,
          'updated_at': row.updatedAt.toIso8601String(),
        });
      case 'budgets':
        final row = await (db.select(db.budgets)..where((t) => t.id.equals(recordId))).getSingleOrNull();
        if (row == null) return null;
        return jsonEncode({
          'id': row.id,
          'month': row.month,
          'type': row.type,
          'category_id': row.categoryId,
          'target_amount': row.targetAmount,
          'deleted': row.deleted,
          'updated_at': row.updatedAt.toIso8601String(),
        });
      default:
        return null;
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

  /// 登出时清空队列
  ///
  /// 本地模式期间写入的记录 userId='local'，登录后推送会被 RLS 拒绝。
  /// 登出时彻底清队，避免污染下一个账户的同步流程。
  Future<void> clearQueue() async {
    await db.delete(db.syncQueue).go();
  }
}
