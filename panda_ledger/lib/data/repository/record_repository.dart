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

final recordRepositoryProvider = Provider<RecordRepository>((ref) {
  return RecordRepository(
    dao: ref.watch(recordDaoProvider),
    accountDao: ref.watch(accountDaoProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
  );
});

class RecordRepository {
  final RecordDao dao;
  final AccountDao accountDao;
  final SyncQueueService syncQueue;

  RecordRepository({
    required this.dao,
    required this.accountDao,
    required this.syncQueue,
  });

  /// 创建记账流水（本地优先）
  ///
  /// 包含碰撞重试：极低概率下 ID 冲突时，自动重新生成 ID 并重试（最多 3 次）。
  /// 自动更新关联账户余额：
  ///   - expense: 账户扣款
  ///   - income:  账户加款
  ///   - transfer: 转出账户扣款 + 转入账户加款
  ///   - adjustment: 直接设置账户余额为 amount
  Future<String> createRecord({
    required String userId,
    required String accountId,
    required double amount,
    required String type,
    String? toAccountId,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
    String source = 'manual',
  }) async {
    final now = DateTime.now();
    const maxRetries = 3;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      final id = IdGenerator.generate();
      try {
        // ═══ 节点 1：打印 insert 完整参数 ═══
        debugPrint('🔵 [同步链路-节点1] insert 参数: id=$id, userId=$userId, '
            'accountId=$accountId, amount=$amount, type=$type, '
            'categoryId=$categoryId, note=$note, '
            'occurredAt=${(occurredAt ?? now).toIso8601String()}, source=$source');

        await dao.insertRecord(
          RecordsCompanion(
            id: Value(id),
            userId: Value(userId),
            accountId: Value(accountId),
            toAccountId: Value.absentIfNull(toAccountId),
            amount: Value(amount),
            type: Value(type),
            categoryId: Value.absentIfNull(categoryId),
            note: Value.absentIfNull(note),
            occurredAt: Value(occurredAt ?? now),
            createdAt: Value(now),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
            source: Value(source),
          ),
        );

        // ═══ 更新账户余额 ═══
        await _updateAccountBalance(
          accountId: accountId,
          amount: amount,
          type: type,
          toAccountId: toAccountId,
        );

        // ═══ 节点 2：insert 后立即用同 ID 回查本地数据库 ═══
        final inserted = await (dao.db.select(dao.db.records)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (inserted != null) {
          debugPrint('🟢 [同步链路-节点2] 本地回查成功: id=${inserted.id}, '
              'amount=${inserted.amount}, type=${inserted.type}, '
              'syncStatus=${inserted.syncStatus}, '
              'occurredAt=${inserted.occurredAt}');
        } else {
          debugPrint('🔴 [同步链路-节点2] 本地回查失败！id=$id 在数据库中不存在！');
        }

        await syncQueue.enqueue(
          operationType: 'insert',
          tableName: 'records',
          recordId: id,
          payload: jsonEncode({
            'id': id,
            'account_id': accountId,
            'to_account_id': toAccountId,
            'amount': amount,
            'type': type,
            'category_id': categoryId,
            'note': note,
            'occurred_at': (occurredAt ?? now).toIso8601String(),
            'source': source,
          }),
        );

        // ═══ 节点 3：确认同步函数被触发 ═══
        debugPrint('🟡 [同步链路-节点3] 开始触发同步队列 processQueue()...');

        // 异步触发同步（不阻塞返回），但捕获异常避免未处理错误
        syncQueue.processQueue().catchError((e) {
          debugPrint('🔴 [同步链路-节点3] 同步队列处理异常: $e');
        });

        return id;
      } catch (e) {
        debugPrint('🔴 [同步链路-节点1/2] insert 异常: $e');
        // 仅在 UNIQUE 约束冲突时重试；其他异常直接抛出
        if (e.toString().contains('UNIQUE constraint failed') &&
            attempt < maxRetries - 1) {
          continue;
        }
        rethrow;
      }
    }

    // 理论不可达（retry 耗尽后上面已 rethrow）
    throw Exception('createRecord: 重试耗尽但仍无法插入记录');
  }

  /// 根据记账类型更新账户余额
  Future<void> _updateAccountBalance({
    required String accountId,
    required double amount,
    required String type,
    String? toAccountId,
  }) async {
    switch (type) {
      case 'expense':
        // 支出：扣除账户余额
        final account = await accountDao.getById(accountId);
        if (account != null) {
          await accountDao.updateBalance(accountId, account.balance - amount);
        }
        break;

      case 'income':
        // 收入：增加账户余额
        final account = await accountDao.getById(accountId);
        if (account != null) {
          await accountDao.updateBalance(accountId, account.balance + amount);
        }
        break;

      case 'transfer':
        // 转账：转出账户扣款 + 转入账户加款
        if (toAccountId != null) {
          final fromAccount = await accountDao.getById(accountId);
          if (fromAccount != null) {
            await accountDao.updateBalance(accountId, fromAccount.balance - amount);
          }
          final toAccount = await accountDao.getById(toAccountId);
          if (toAccount != null) {
            await accountDao.updateBalance(toAccountId, toAccount.balance + amount);
          }
        }
        break;

      case 'adjustment':
        // 余额调整：直接设置为指定余额
        await accountDao.updateBalance(accountId, amount);
        break;
    }
  }

  /// 获取指定日期范围的收支汇总
  Future<Map<String, double>> getSummary(DateTime start, DateTime end) {
    return dao.getSummary(start, end);
  }

  /// 获取指定日期范围的流水列表
  Future<List<Record>> getRecordsInRange(DateTime start, DateTime end) {
    return dao.getRecordsInRange(start, end);
  }

  /// 获取月度流水
  Future<List<Record>> getMonthlyRecords(int year, int month) {
    return dao.getMonthlyRecords(year, month);
  }

  /// 获取月度收支汇总
  Future<Map<String, double>> getMonthlySummary(int year, int month) {
    return dao.getMonthlySummary(year, month);
  }

  /// 获取最近流水
  Future<List<Record>> getRecentRecords({int limit = 50}) {
    return dao.getRecords(limit: limit);
  }

  /// 按 ID 获取单条记录
  Future<Record?> getById(String id) => dao.getById(id);

  /// 搜索/筛选流水（分页）
  Future<({List<Record> records, bool hasMore})> searchRecords({
    DateTime? start,
    DateTime? end,
    String? categoryId,
    String? accountId,
    String? keyword,
    int limit = 30,
    int offset = 0,
  }) {
    return dao.searchRecords(
      start: start,
      end: end,
      categoryId: categoryId,
      accountId: accountId,
      keyword: keyword,
      limit: limit,
      offset: offset,
    );
  }

  /// 更新记录并修正关联账户余额
  ///
  /// [oldAccountId] / [oldToAccountId] 是编辑前记录的原始账户 ID，
  /// 用于正确撤销旧记账对余额的影响。若不传则默认与当前账户相同
  /// （适用于未变更账户的编辑场景）。
  Future<void> updateRecord({
    required String recordId,
    required String accountId,
    required double amount,
    required String type,
    String? toAccountId,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
    double? oldAmount,
    String? oldType,
    String? oldAccountId,
    String? oldToAccountId,
  }) async {
    // 1. 先撤销旧记账对余额的影响
    if (oldAmount != null && oldType != null) {
      await _reverseAccountBalance(
        accountId: oldAccountId ?? accountId,
        amount: oldAmount,
        type: oldType,
        toAccountId: oldToAccountId ?? toAccountId,
      );
    }

    // 2. 更新记录本身
    await dao.updateRecord(
      recordId,
      RecordsCompanion(
        categoryId: Value.absentIfNull(categoryId),
        amount: Value(amount),
        type: Value(type),
        note: Value.absentIfNull(note),
        occurredAt: Value.absentIfNull(occurredAt),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );

    // 3. 应用新记账对余额的影响
    await _updateAccountBalance(
      accountId: accountId,
      amount: amount,
      type: type,
      toAccountId: toAccountId,
    );

    // 4. 入同步队列
    try {
      await syncQueue.enqueue(
        operationType: 'update',
        tableName: 'records',
        recordId: recordId,
        payload: jsonEncode({
          'id': recordId,
          'account_id': accountId,
          'to_account_id': toAccountId,
          'amount': amount,
          'type': type,
          'category_id': categoryId,
          'note': note,
          'occurred_at': (occurredAt ?? DateTime.now()).toIso8601String(),
        }),
      );
      syncQueue.processQueue().catchError((_) {});
    } catch (_) {}
  }

  /// 删除记录并修正关联账户余额（软删除）
  Future<void> deleteRecord(Record record) async {
    // 1. 撤销记账对余额的影响
    await _reverseAccountBalance(
      accountId: record.accountId,
      amount: record.amount,
      type: record.type,
      toAccountId: record.toAccountId,
    );

    // 2. 软删除本地记录
    await dao.softDeleteRecord(record.id);

    // 3. 入同步队列（upsert 模式，带 deleted=true + account_id 用于余额同步）
    try {
      final now = DateTime.now().toUtc();
      await syncQueue.enqueue(
        operationType: 'update',
        tableName: 'records',
        recordId: record.id,
        payload: jsonEncode({
          'id': record.id,
          'account_id': record.accountId,
          'to_account_id': record.toAccountId,
          'amount': record.amount,
          'type': record.type,
          'category_id': record.categoryId,
          'note': record.note,
          'occurred_at': record.occurredAt.toIso8601String(),
          'source': record.source,
          'deleted': true,
          'updated_at': now.toIso8601String(),
        }),
      );
      syncQueue.processQueue().catchError((_) {});
    } catch (_) {}
  }

  /// 撤销某个记账操作对账户余额的影响（与 _updateAccountBalance 相反）
  Future<void> _reverseAccountBalance({
    required String accountId,
    required double amount,
    required String type,
    String? toAccountId,
  }) async {
    switch (type) {
      case 'expense':
        final account = await accountDao.getById(accountId);
        if (account != null) {
          await accountDao.updateBalance(accountId, account.balance + amount);
        }
        break;
      case 'income':
        final account = await accountDao.getById(accountId);
        if (account != null) {
          await accountDao.updateBalance(accountId, account.balance - amount);
        }
        break;
      case 'transfer':
        if (toAccountId != null) {
          final fromAccount = await accountDao.getById(accountId);
          if (fromAccount != null) {
            await accountDao.updateBalance(accountId, fromAccount.balance + amount);
          }
          final toAccount = await accountDao.getById(toAccountId);
          if (toAccount != null) {
            await accountDao.updateBalance(toAccountId, toAccount.balance - amount);
          }
        }
        break;
    }
  }
}
