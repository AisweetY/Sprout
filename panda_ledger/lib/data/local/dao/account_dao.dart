import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/accounts_table.dart';

part 'account_dao.g.dart';

@DriftAccessor(tables: [Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  /// 获取所有未归档账户（按排序字段排列）
  Future<List<Account>> getActiveAccounts() {
    return (select(db.accounts)
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取全部账户（含已归档）
  Future<List<Account>> getAllAccounts() {
    return (select(db.accounts)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();
  }

  /// 按类型获取账户
  Future<List<Account>> getAccountsByType(String type) {
    return (select(db.accounts)
          ..where((t) => t.type.equals(type) & t.isArchived.equals(false)))
        .get();
  }

  /// 获取计入总资产的账户
  Future<List<Account>> getNetWorthAccounts() {
    return (select(db.accounts)
          ..where((t) => t.includeInNet.equals(true) & t.isArchived.equals(false)))
        .get();
  }

  /// 获取单个账户
  Future<Account?> getById(String id) {
    return (select(db.accounts)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 插入账户
  Future<void> insertAccount(Insertable<Account> account) {
    return into(db.accounts).insert(account);
  }

  /// 更新账户余额
  Future<void> updateBalance(String id, double newBalance) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(balance: Value(newBalance)),
    );
  }

  /// 更新账户
  Future<bool> updateAccount(String id, AccountsCompanion data) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(data).then((v) => v > 0);
  }

  /// 归档账户
  Future<void> archiveAccount(String id) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(
      const AccountsCompanion(isArchived: Value(true)),
    );
  }

  /// 取消归档账户
  Future<void> unarchiveAccount(String id) {
    return (update(db.accounts)..where((t) => t.id.equals(id))).write(
      const AccountsCompanion(isArchived: Value(false)),
    );
  }

  /// 监听所有活跃账户（用于 Riverpod watch）
  Selectable<Account> watchActiveAccounts() {
    return (select(db.accounts)
      ..where((t) => t.isArchived.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]));
  }
}
