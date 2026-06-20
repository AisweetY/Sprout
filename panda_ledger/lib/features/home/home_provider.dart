import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/account_repository.dart';

/// 首页数据 Provider — 响应式自动更新
///
/// 依赖 accountsStreamProvider / monthlyRecordsStreamProvider /
/// monthlyBudgetsStreamProvider，当底层数据变更时自动重算。
final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final recordDao = ref.watch(recordDaoProvider);
  final accountRepo = ref.watch(accountRepositoryProvider);

  final now = DateTime.now();
  final year = now.year;
  final month = now.month;
  final monthStr = '$year-${month.toString().padLeft(2, '0')}';

  // ═══ 订阅底层数据流 → 数据变更时自动失效重算 ═══
  ref.watch(accountsStreamProvider);
  ref.watch(monthlyRecordsStreamProvider((year: year, month: month)));
  ref.watch(monthlyBudgetsStreamProvider(monthStr));

  // 并行获取
  final results = await Future.wait([
    recordDao.getMonthlySummary(year, month),
    _getMonthlySavingGoal(db, monthStr),
    accountRepo.getNetWorth(),
    _getDailyRecords(db, year, month),
  ]);

  final summary = results[0] as Map<String, double>;
  final savingGoal = results[1];
  final netWorth = results[2] as double;
  final dailyGroups = results[3] as List<DailyRecordGroup>;

  final income = summary['income'] ?? 0;
  final expense = summary['expense'] ?? 0;
  final netSaving = income - expense;

  double goalAmount = 0;
  if (savingGoal != null) {
    goalAmount = (savingGoal as Budget).targetAmount;
  }
  final goalProgress = goalAmount > 0 ? (netSaving / goalAmount).clamp(0.0, 1.0) : 0.0;

  final daysInMonth = DateTime(year, month + 1, 0).day;
  final daysPassed = now.day;
  final projectedSaving =
      daysPassed > 0 ? (netSaving / daysPassed) * daysInMonth : 0.0;

  return HomeData(
    netSaving: netSaving,
    income: income,
    expense: expense,
    netWorth: netWorth,
    savingGoalAmount: goalAmount,
    savingGoalProgress: goalProgress,
    projectedSaving: projectedSaving,
    dailyGroups: dailyGroups,
    month: month,
    year: year,
  );
});

/// 获取月度储蓄目标（不使用 DAO 的便捷方法，因为需要从 budgets 表查）
Future<Budget?> _getMonthlySavingGoal(AppDatabase db, String month) async {
  return (db.select(db.budgets)
        ..where((t) =>
            t.month.equals(month) &
            t.type.equals('saving_goal') &
            t.deleted.equals(false)))
      .getSingleOrNull();
}

/// 获取当月按天分组的流水（含账户名和分类名）
Future<List<DailyRecordGroup>> _getDailyRecords(
    AppDatabase db, int year, int month) async {
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 1);

  final query = db.customSelect(
    '''SELECT
         r.id, r.type, r.amount, r.note, r.occurred_at,
         r.sync_status,
         COALESCE(sub.name, cat.name, '其他') as category_name,
         COALESCE(sub.icon, cat.icon) as category_icon,
         a.name as account_name,
         a.type as account_type
       FROM records r
       LEFT JOIN categories sub ON r.category_id = sub.id
       LEFT JOIN categories cat ON sub.parent_id = cat.id
       LEFT JOIN accounts a ON r.account_id = a.id
       WHERE r.occurred_at >= ? AND r.occurred_at < ?
       ORDER BY r.occurred_at DESC''',
    variables: [
      Variable.withDateTime(start),
      Variable.withDateTime(end),
    ],
    readsFrom: {db.records, db.categories, db.accounts},
  );

  final rows = await query.get();

  final Map<String, List<RecordItem>> dayMap = {};

  for (final row in rows) {
    final occurredAt = row.read<DateTime>('occurred_at');
    final dateKey =
        '${occurredAt.year}-${occurredAt.month.toString().padLeft(2, '0')}-${occurredAt.day.toString().padLeft(2, '0')}';

    final item = RecordItem(
      id: row.read<String>('id'),
      type: row.read<String>('type'),
      amount: row.read<double>('amount'),
      note: row.read<String?>('note'),
      occurredAt: occurredAt,
      categoryName: row.read<String>('category_name'),
      categoryIcon: row.read<String?>('category_icon'),
      accountName: row.read<String>('account_name'),
      syncStatus: row.read<String>('sync_status'),
    );

    dayMap.putIfAbsent(dateKey, () => []).add(item);
  }

  final groups = <DailyRecordGroup>[];
  final sortedKeys = dayMap.keys.toList()..sort((a, b) => b.compareTo(a));

  for (final key in sortedKeys) {
    final items = dayMap[key]!;
    final date = DateTime.parse(key);
    double dayIncome = 0;
    double dayExpense = 0;
    for (final item in items) {
      if (item.type == 'income') {
        dayIncome += item.amount;
      } else if (item.type == 'expense') {
        dayExpense += item.amount;
      }
    }
    groups.add(DailyRecordGroup(
      date: date,
      dateLabel: '${date.month}月${date.day}日',
      items: items,
      dayIncome: dayIncome,
      dayExpense: dayExpense,
    ));
  }

  return groups;
}

/// 首页聚合数据
class HomeData {
  final double netSaving;
  final double income;
  final double expense;
  final double netWorth;
  final double savingGoalAmount;
  final double savingGoalProgress;
  final double projectedSaving;
  final List<DailyRecordGroup> dailyGroups;
  final int month;
  final int year;

  const HomeData({
    required this.netSaving,
    required this.income,
    required this.expense,
    required this.netWorth,
    required this.savingGoalAmount,
    required this.savingGoalProgress,
    required this.projectedSaving,
    required this.dailyGroups,
    required this.month,
    required this.year,
  });
}

/// 按天分组的流水
class DailyRecordGroup {
  final DateTime date;
  final String dateLabel;
  final List<RecordItem> items;
  final double dayIncome;
  final double dayExpense;

  const DailyRecordGroup({
    required this.date,
    required this.dateLabel,
    required this.items,
    required this.dayIncome,
    required this.dayExpense,
  });
}

/// 单条流水展示数据
class RecordItem {
  final String id;
  final String type;
  final double amount;
  final String? note;
  final DateTime occurredAt;
  final String categoryName;
  final String? categoryIcon;
  final String accountName;
  final String syncStatus;

  const RecordItem({
    required this.id,
    required this.type,
    required this.amount,
    this.note,
    required this.occurredAt,
    required this.categoryName,
    this.categoryIcon,
    required this.accountName,
    this.syncStatus = 'synced',
  });
}
