import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'dao/account_dao.dart';
import 'dao/budget_dao.dart';
import 'dao/category_dao.dart';
import 'dao/record_dao.dart';
import 'dao/sync_queue_dao.dart';

/// 全局数据库实例 Provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// CategoryDao Provider
final categoryDaoProvider = Provider<CategoryDao>((ref) {
  return CategoryDao(ref.watch(appDatabaseProvider));
});

/// AccountDao Provider
final accountDaoProvider = Provider<AccountDao>((ref) {
  return AccountDao(ref.watch(appDatabaseProvider));
});

/// RecordDao Provider
final recordDaoProvider = Provider<RecordDao>((ref) {
  return RecordDao(ref.watch(appDatabaseProvider));
});

/// BudgetDao Provider
final budgetDaoProvider = Provider<BudgetDao>((ref) {
  return BudgetDao(ref.watch(appDatabaseProvider));
});

/// SyncQueueDao Provider
final syncQueueDaoProvider = Provider<SyncQueueDao>((ref) {
  return SyncQueueDao(ref.watch(appDatabaseProvider));
});
