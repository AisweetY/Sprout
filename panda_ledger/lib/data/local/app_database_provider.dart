import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'dao/account_dao.dart';
import 'dao/budget_dao.dart';
import 'dao/category_dao.dart';
import 'dao/record_dao.dart';
import 'dao/sync_queue_dao.dart';
import 'dao/sync_metadata_dao.dart';

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

/// SyncMetadataDao Provider
final syncMetadataDaoProvider = Provider<SyncMetadataDao>((ref) {
  return SyncMetadataDao(ref.watch(appDatabaseProvider));
});

// ═══════════════════════════════════════════════════════════════════
// 响应式 StreamProvider — 监听底层数据表变更
// 所有页面通过依赖这些 StreamProvider 实现数据自动更新
// ═══════════════════════════════════════════════════════════════════

/// 活跃账户流（实时响应账户增/删/改/归档）
final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountDaoProvider).watchActiveAccounts().watch();
});

/// 全部账户流（含已归档，实时响应）
final allAccountsStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountDaoProvider).watchAllAccounts().watch();
});

/// 活跃分类流（实时响应分类增/删/改/归档）
final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryDaoProvider).watchActiveCategories().watch();
});

/// 全部分类流（含已归档，实时响应）
final allCategoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryDaoProvider).watchAllCategories().watch();
});

/// 月度流水流 — 给定年月，实时响应流水变更
final monthlyRecordsStreamProvider =
    StreamProvider.family<List<Record>, ({int year, int month})>(
  (ref, params) {
    return ref
        .watch(recordDaoProvider)
        .watchMonthlyRecords(params.year, params.month)
        .watch();
  },
);

/// 月度预算流 — 给定月份字符串，实时响应预算变更
final monthlyBudgetsStreamProvider =
    StreamProvider.family<List<Budget>, String>((ref, month) {
  return ref.watch(budgetDaoProvider).watchMonthlyBudgets(month).watch();
});
