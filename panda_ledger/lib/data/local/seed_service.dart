import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils/id_generator.dart';
import '../sync/sync_queue_dao_provider.dart';
import 'app_database_provider.dart';
import 'database.dart';

/// 种子数据服务
///
/// 首次启动时自动创建预置分类和默认账户，并同步到云端。
final seedServiceProvider = Provider<SeedService>((ref) {
  return SeedService(
    db: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
  );
});

class SeedService {
  final AppDatabase db;
  final SyncQueueService syncQueue;

  SeedService({required this.db, required this.syncQueue});

  /// 检查是否需要初始化种子数据
  ///
  /// 策略：先检查本地分类是否为空。若已完成初始同步但仍无分类
  /// （云端也无数据），则执行种子初始化。这是真正新用户首次使用的情况。
  Future<bool> needsSeeding() async {
    final rows = await db.select(db.categories).get();
    return rows.isEmpty;
  }

  /// 执行种子数据初始化
  Future<void> seed({required String userId}) async {
    // ── 创建默认账户（现金） ──
    final existingAccounts = await db.select(db.accounts).get();
    if (existingAccounts.isEmpty) {
      await _createDefaultAccount(userId);
    }

    // 创建支出分类
    for (final name in DefaultCategories.expenseNames) {
      final icon = DefaultCategories.expenseIcons[name] ?? 'more_horiz';
      await _createCategory(userId, name, 'expense', icon, null);

      // 创建二级分类
      final subs = DefaultCategories.subcategories[name];
      if (subs != null) {
        final parentId = await _getCategoryId(userId, name, 'expense');
        if (parentId != null) {
          for (final subName in subs) {
            await _createCategory(userId, subName, 'expense', icon, parentId);
          }
        }
      }
    }

    // 创建收入分类
    for (final name in DefaultCategories.incomeNames) {
      final icon = DefaultCategories.incomeIcons[name] ?? 'more_horiz';
      await _createCategory(userId, name, 'income', icon, null);
    }

    // 种子数据全部写入后，异步推送到 Supabase
    syncQueue.processQueue().catchError((e) {
      debugPrint('🔴 [种子同步] processQueue 异常: $e');
    });
  }

  /// 创建默认账户「现金」
  Future<void> _createDefaultAccount(String userId) async {
    final id = IdGenerator.generate();
    await db.into(db.accounts).insert(
      AccountsCompanion(
        id: Value(id),
        userId: Value(userId),
        name: const Value('现金'),
        type: const Value('cash'),
        balance: const Value(0),
        currency: const Value('CNY'),
        isLiability: const Value(false),
        includeInNet: const Value(true),
        isArchived: const Value(false),
        sortOrder: const Value(0),
      ),
    );

    // 入同步队列
    try {
      await syncQueue.enqueue(
        operationType: 'insert',
        tableName: 'accounts',
        recordId: id,
        payload: jsonEncode({
          'id': id,
          'name': '现金',
          'type': 'cash',
          'balance': 0,
          'currency': 'CNY',
          'is_liability': false,
          'include_in_net': true,
          'is_archived': false,
        }),
      );
      debugPrint('🟢 [种子同步] 默认账户「现金」已入队: $id');
    } catch (e) {
      debugPrint('🔴 [种子同步] 默认账户入队失败: $e');
    }
  }

  Future<void> _createCategory(
    String userId,
    String name,
    String kind,
    String icon,
    String? parentId,
  ) async {
    final id = IdGenerator.generate();
    await db.into(db.categories).insert(
      CategoriesCompanion(
        id: Value(id),
        userId: Value(userId),
        name: Value(name),
        kind: Value(kind),
        icon: Value(icon),
        parentId: Value.absentIfNull(parentId),
      ),
    );

    // 入同步队列
    try {
      await syncQueue.enqueue(
        operationType: 'insert',
        tableName: 'categories',
        recordId: id,
        payload: jsonEncode({
          'id': id,
          'name': name,
          'parent_id': parentId,
          'icon': icon,
          'kind': kind,
          'is_archived': false,
        }),
      );
    } catch (e) {
      debugPrint('🔴 [种子同步] 分类「$name」入队失败: $e');
    }
  }

  Future<String?> _getCategoryId(String userId, String name, String kind) async {
    final rows = await (db.select(db.categories)
          ..where((t) => t.name.equals(name) & t.kind.equals(kind) & t.parentId.isNull())
          ..limit(1))
        .get();
    return rows.isNotEmpty ? rows.first.id : null;
  }
}
