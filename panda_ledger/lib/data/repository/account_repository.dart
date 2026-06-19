import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/id_generator.dart';
import '../local/app_database_provider.dart';
import '../local/dao/account_dao.dart';
import '../local/dao/record_dao.dart';
import '../local/database.dart';
import '../sync/sync_queue_dao_provider.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    dao: ref.watch(accountDaoProvider),
    recordDao: ref.watch(recordDaoProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
  );
});

class AccountRepository {
  final AccountDao dao;
  final RecordDao recordDao;
  final SyncQueueService syncQueue;

  AccountRepository({
    required this.dao,
    required this.recordDao,
    required this.syncQueue,
  });

  /// 获取活跃账户列表
  Future<List<Account>> getActiveAccounts() => dao.getActiveAccounts();

  /// 获取所有账户
  Future<List<Account>> getAllAccounts() => dao.getAllAccounts();

  /// 创建账户（本地优先 + 同步队列）
  Future<Account> createAccount({
    required String userId,
    required String name,
    required String type,
    double balance = 0,
    bool isLiability = false,
  }) async {
    final now = DateTime.now();
    final id = IdGenerator.generate();
    final account = AccountsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      type: Value(type),
      balance: Value(balance),
      isLiability: Value(isLiability),
      includeInNet: const Value(true),
      sortOrder: const Value(0),
      createdAt: Value(now),
    );
    await dao.insertAccount(account);

    // ═══ 同步到 Supabase ═══
    try {
      await syncQueue.enqueue(
        operationType: 'insert',
        tableName: 'accounts',
        recordId: id,
        payload: jsonEncode({
          'id': id,
          'name': name,
          'type': type,
          'balance': balance,
          'currency': 'CNY',
          'is_liability': isLiability,
          'include_in_net': true,
          'is_archived': false,
        }),
      );
      debugPrint('🟢 [账户同步] 已入队: $name (id=$id)');

      // 异步触发同步
      syncQueue.processQueue().catchError((e) {
        debugPrint('🔴 [账户同步] processQueue 异常: $e');
      });
    } catch (e) {
      // 入队失败不影响本地已持久化的数据
      debugPrint('🔴 [账户同步] 入队失败: $e');
    }

    return (await dao.getById(id))!;
  }

  /// 校正账户余额 — 直接修改余额并自动生成一条余额调整流水
  ///
  /// 生成一条 type='adjustment' 的流水记录用于审计追踪。
  Future<void> correctBalance(String accountId, double newBalance) async {
    final account = await dao.getById(accountId);
    if (account == null) return;

    final oldBalance = account.balance;
    final diff = newBalance - oldBalance;
    final now = DateTime.now();

    // 1. 更新账户余额
    await dao.updateBalance(accountId, newBalance);

    // 2. 生成一条余额调整流水（amount 存 newBalance，用绝对值保证 CHECK 约束）
    final adjustmentId = IdGenerator.generate();
    final adjustmentAmount = diff.abs();
    // 调整金额为 0 时跳过（余额未变化）
    if (adjustmentAmount == 0) return;

    await recordDao.insertRecord(
      RecordsCompanion(
        id: Value(adjustmentId),
        userId: Value(account.userId),
        accountId: Value(accountId),
        amount: Value(adjustmentAmount),
        type: const Value('adjustment'),
        note: Value('余额校正：¥${oldBalance.toStringAsFixed(2)} → ¥${newBalance.toStringAsFixed(2)}'),
        occurredAt: Value(now),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
        source: const Value('manual'),
      ),
    );
  }

  /// 归档账户
  Future<void> archive(String accountId) async {
    await dao.archiveAccount(accountId);
  }

  /// 取消归档账户
  Future<void> unarchive(String accountId) async {
    await dao.unarchiveAccount(accountId);
  }

  /// 计算净资产
  Future<double> getNetWorth() async {
    final accounts = await dao.getNetWorthAccounts();
    double netWorth = 0;
    for (final a in accounts) {
      if (a.isLiability) {
        netWorth -= a.balance;
      } else {
        netWorth += a.balance;
      }
    }
    return netWorth;
  }
}
