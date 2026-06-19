import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/accounts_table.dart';
import 'tables/records_table.dart';
import 'tables/categories_table.dart';
import 'tables/budgets_table.dart';
import 'tables/sync_queue_table.dart';

import 'dao/account_dao.dart';
import 'dao/record_dao.dart';
import 'dao/category_dao.dart';
import 'dao/budget_dao.dart';
import 'dao/sync_queue_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Records,
    Categories,
    Budgets,
    SyncQueue,
  ],
  daos: [
    AccountDao,
    RecordDao,
    CategoryDao,
    BudgetDao,
    SyncQueueDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // 添加迁移步骤：
          //   if (from < 2) { await m.addColumn(db.xxx, db.xxx.newColumn); }
          // 使用 m.createAll() 或逐表添加列来升级 schema
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'panda_ledger');
  }
}
