import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/accounts_table.dart';

part 'account_dao.g.dart';

@DriftAccessor(tables: [Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  /// 获取所有未归档账户（按排序字段排列，排除已删除）
  Future<List<Account>> getActiveAccounts() {
    return (select(db.accounts)
          ..where((t) => t.isArchived.equals(false) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取全部账户（含已归档，排除已删除）
  Future<List<Account>> getAllAccounts() {
    return (select(db.accounts)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 按类型获取账户
  Future<List<Account>> getAccountsByType(String type) {
    return (select(db.accounts)
          ..where((t) => t.type.equals(type) & t.isArchived.equals(false) & t.deleted.equals(false)))
        .get();
  }

  /// 获取计入总资产的账户
  Future<List<Account>> getNetWorthAccounts() {
    return (select(db.accounts)
          ..where((t) => t.includeInNet.equals(true) & t.isArchived.equals(false) & t.deleted.equals(false)))
        .get();
  }

  /// 获取单个账户
  Future<Account?> getById(String id) {
    return (select(db.accounts)..where((t) => t.id.equals(id) & t.deleted.equals(false))).getSingleOrNull();
  }

  /// 插入账户
  Future<void> insertAccount(Insertable<Account> account) {
    return into(db.accounts).insert(account);
  }

  /// 更新账户余额（同时更新 updatedAt 和 syncStatus，防止 LWW 用旧云端覆盖新本地）
  Future<void> updateBalance(String id, double newBalance) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        balance: Value(newBalance),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 更新账户
  Future<bool> updateAccount(String id, AccountsCompanion data) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(data).then((v) => v > 0);
  }

  /// 归档账户
  Future<void> archiveAccount(String id) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        isArchived: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 取消归档账户
  Future<void> unarchiveAccount(String id) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        isArchived: const Value(false),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 软删除账户
  Future<void> softDeleteAccount(String id) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 监听所有活跃账户（用于 Riverpod watch）
  Selectable<Account> watchActiveAccounts() {
    return (select(db.accounts)
      ..where((t) => t.isArchived.equals(false) & t.deleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]));
  }

  /// 监听所有账户（含已归档，用于 Riverpod watch）
  Selectable<Account> watchAllAccounts() {
    return (select(db.accounts)
      ..where((t) => t.deleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]));
  }
}
