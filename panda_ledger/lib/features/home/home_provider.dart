import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/account_repository.dart';

/// 首页数据 Provider
final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final recordDao = ref.watch(recordDaoProvider);
  final budgetDao = ref.watch(budgetDaoProvider);
  final accountRepo = ref.watch(accountRepositoryProvider);

  final now = DateTime.now();
  final year = now.year;
  final month = now.month;
  final monthStr = '$year-${month.toString().padLeft(2, '0')}';

  // 并行获取
  final results = await Future.wait([
    recordDao.getMonthlySummary(year, month),
    budgetDao.getMonthlySavingGoal(monthStr),
    accountRepo.getNetWorth(),
    _getTopSpending(db, year, month),
  ]);

  final summary = results[0] as Map<String, double>;
  final savingGoal = results[1];
  final netWorth = results[2] as double;
  final topSpending = results[3] as List<CategorySpending>;

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
  final projectedSaving = daysPassed > 0 ? (netSaving / daysPassed) * daysInMonth : 0.0;

  return HomeData(
    netSaving: netSaving,
    income: income,
    expense: expense,
    netWorth: netWorth,
    savingGoalAmount: goalAmount,
    savingGoalProgress: goalProgress,
    projectedSaving: projectedSaving,
    topSpending: topSpending,
    month: month,
    year: year,
  );
});

Future<List<CategorySpending>> _getTopSpending(AppDatabase db, int year, int month) async {
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 1);

  // 按一级分类汇总：二级分类的金额通过 COALESCE 汇总到其父级
  final query = db.customSelect(
    '''SELECT COALESCE(parent.name, c.name) as name,
              COALESCE(SUM(r.amount), 0) as total
       FROM records r
       LEFT JOIN categories c ON r.category_id = c.id
       LEFT JOIN categories parent ON c.parent_id = parent.id
       WHERE r.occurred_at >= ? AND r.occurred_at < ?
         AND r.type = 'expense'
         AND r.category_id IS NOT NULL
       GROUP BY COALESCE(parent.id, c.id), COALESCE(parent.name, c.name)
       ORDER BY total DESC
       LIMIT 5''',
    variables: [
      Variable.withString(start.toIso8601String()),
      Variable.withString(end.toIso8601String()),
    ],
    readsFrom: {db.records, db.categories},
  );

  final rows = await query.get();
  return rows.map((row) => CategorySpending(
    name: row.read<String>('name'),
    amount: row.read<double>('total'),
  )).toList();
}

class HomeData {
  final double netSaving;
  final double income;
  final double expense;
  final double netWorth;
  final double savingGoalAmount;
  final double savingGoalProgress;
  final double projectedSaving;
  final List<CategorySpending> topSpending;
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
    required this.topSpending,
    required this.month,
    required this.year,
  });
}

class CategorySpending {
  final String name;
  final double amount;

  const CategorySpending({required this.name, required this.amount});
}
