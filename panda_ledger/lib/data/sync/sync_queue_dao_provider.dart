import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database_provider.dart';
import '../local/dao/sync_queue_dao.dart';
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

  /// 推送流水记录到 Supabase
  Future<void> _pushRecord(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
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
    };

    debugPrint('🟡 [同步链路-节点4] Supabase 请求: ${operation.toUpperCase()} records, '
        '请求体: ${jsonEncode(data)}');

    try {
      if (operation == 'insert') {
        await supabase.from('records').insert(data);
      } else if (operation == 'update') {
        await supabase.from('records').update(data).eq('id', payload['id']);
      }
      debugPrint('🟢 [同步链路-节点4] Supabase 响应成功: $operation records ${payload['id']}');
    } catch (e) {
      debugPrint('🔴 [同步链路-节点4] Supabase 响应失败: $e');
      rethrow;
    }
  }

  /// 推送账户到 Supabase
  Future<void> _pushAccount(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
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
    };

    if (operation == 'insert') {
      await supabase.from('accounts').insert(data);
    } else if (operation == 'update') {
      await supabase
          .from('accounts')
          .update(data)
          .eq('id', payload['id']);
    }
  }

  /// 推送分类到 Supabase
  Future<void> _pushCategory(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final data = {
      'id': payload['id'],
      'user_id': userId,
      'name': payload['name'],
      'parent_id': payload['parent_id'],
      'icon': payload['icon'],
      'kind': payload['kind'],
      'is_archived': payload['is_archived'] ?? false,
    };

    if (operation == 'insert') {
      await supabase.from('categories').insert(data);
    } else if (operation == 'update') {
      await supabase
          .from('categories')
          .update(data)
          .eq('id', payload['id']);
    }
  }

  /// 推送预算到 Supabase
  Future<void> _pushBudget(
    SupabaseClient supabase,
    String userId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final data = {
      'id': payload['id'],
      'user_id': userId,
      'month': payload['month'],
      'type': payload['type'],
      'category_id': payload['category_id'],
      'target_amount': payload['target_amount'],
    };

    if (operation == 'insert') {
      await supabase.from('budgets').insert(data);
    } else if (operation == 'update') {
      await supabase
          .from('budgets')
          .update(data)
          .eq('id', payload['id']);
    }
  }

  /// 标记本地记录为已同步
  Future<void> _markRecordSynced(String tableName, String recordId) async {
    switch (tableName) {
      case 'records':
        await (db.update(db.records)
              ..where((t) => t.id.equals(recordId)))
            .write(RecordsCompanion(syncStatus: const Value('synced')));
        break;
      // 其他表目前没有 sync_status 字段，仅 records 需要更新
    }
  }

  /// 标记本地记录为冲突
  Future<void> _markRecordConflict(String tableName, String recordId) async {
    switch (tableName) {
      case 'records':
        await (db.update(db.records)
              ..where((t) => t.id.equals(recordId)))
            .write(RecordsCompanion(syncStatus: const Value('conflict')));
        break;
    }
  }

  /// 从 Supabase 增量拉取（应用启动时调用）
  Future<void> pullFromSupabase() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // 拉取记录
      final remoteRecords = await supabase
          .from('records')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(500);

      for (final r in remoteRecords) {
        final exists =
            await (db.select(db.records)..where((t) => t.id.equals(r['id'])))
                .getSingleOrNull();
        if (exists == null) {
          await db.into(db.records).insert(
                RecordsCompanion(
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
                ),
              );
        }
      }

      // 拉取账户
      final remoteAccounts = await supabase
          .from('accounts')
          .select()
          .eq('user_id', userId);
      for (final a in remoteAccounts) {
        final exists = await (db.select(db.accounts)
              ..where((t) => t.id.equals(a['id'])))
            .getSingleOrNull();
        if (exists == null) {
          await db.into(db.accounts).insert(
                AccountsCompanion(
                  id: Value(a['id']),
                  userId: Value(a['user_id']),
                  name: Value(a['name']),
                  type: Value(a['type']),
                  balance: Value((a['balance'] as num).toDouble()),
                  currency: Value(a['currency'] ?? 'CNY'),
                  isLiability: Value(a['is_liability'] ?? false),
                  includeInNet: Value(a['include_in_net'] ?? true),
                  isArchived: Value(a['is_archived'] ?? false),
                  sortOrder: Value(a['sort_order'] ?? 0),
                  createdAt: Value(DateTime.parse(a['created_at'])),
                ),
              );
        }
      }

      // 拉取分类
      final remoteCategories = await supabase
          .from('categories')
          .select()
          .eq('user_id', userId);
      for (final c in remoteCategories) {
        final exists = await (db.select(db.categories)
              ..where((t) => t.id.equals(c['id'])))
            .getSingleOrNull();
        if (exists == null) {
          await db.into(db.categories).insert(
                CategoriesCompanion(
                  id: Value(c['id']),
                  userId: Value(c['user_id']),
                  name: Value(c['name']),
                  parentId: Value.absentIfNull(c['parent_id']),
                  icon: Value.absentIfNull(c['icon']),
                  kind: Value(c['kind']),
                  sortOrder: Value(c['sort_order'] ?? 0),
                  isArchived: Value(c['is_archived'] ?? false),
                ),
              );
        }
      }
    } catch (e) {
      // 拉取失败不阻塞本地使用
    }
  }
}
