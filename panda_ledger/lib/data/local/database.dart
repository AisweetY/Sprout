import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/accounts_table.dart';
import 'tables/records_table.dart';
import 'tables/categories_table.dart';
import 'tables/budgets_table.dart';
import 'tables/sync_queue_table.dart';
import 'tables/sync_metadata_table.dart';
import 'tables/conflict_log_table.dart';

import 'dao/account_dao.dart';
import 'dao/record_dao.dart';
import 'dao/category_dao.dart';
import 'dao/budget_dao.dart';
import 'dao/sync_queue_dao.dart';
import 'dao/sync_metadata_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Records,
    Categories,
    Budgets,
    SyncQueue,
    SyncMetadata,
    ConflictLog,
  ],
  daos: [
    AccountDao,
    RecordDao,
    CategoryDao,
    BudgetDao,
    SyncQueueDao,
    SyncMetadataDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用构造函数：接受外部传入的 [executor]（如内存数据库）
  AppDatabase.test(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // ⚠️ SQLite ALTER TABLE 不支持非恒定默认值（如 currentDateAndTime）。
            // DateTimeColumn 必须用原始 SQL + 常量默认值（0）添加，
            // BoolColumn / TextColumn 的常量默认值可直接用 m.addColumn。

            // ── accounts: +updated_at(INT, 0), +sync_status(TEXT, 'synced'), +deleted(INT, 0) ──
            await customStatement(
                'ALTER TABLE accounts ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
            // 已有行的 updated_at 回填为 created_at（二者均为 INTEGER Unix 毫秒）
            await customStatement(
                'UPDATE accounts SET updated_at = created_at');
            await m.addColumn(accounts, accounts.syncStatus); // TEXT literal OK
            await m.addColumn(accounts, accounts.deleted);     // BOOL literal OK

            // ── categories: +updated_at(INT, 0), +sync_status, +deleted ──
            await customStatement(
                'ALTER TABLE categories ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
            await m.addColumn(categories, categories.syncStatus);
            await m.addColumn(categories, categories.deleted);

            // ── records: +deleted ──
            await m.addColumn(records, records.deleted);       // BOOL literal OK

            // ── budgets: +updated_at(INT, 0), +sync_status, +deleted ──
            await customStatement(
                'ALTER TABLE budgets ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
            await m.addColumn(budgets, budgets.syncStatus);
            await m.addColumn(budgets, budgets.deleted);

            // ── 新建表 ──
            await m.createTable(syncMetadata);
            await m.createTable(conflictLog);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'panda_ledger');
  }
}
