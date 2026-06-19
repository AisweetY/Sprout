import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';

/// 月份参数 — 用于 FutureProvider.family
class BudgetParams {
  final int year;
  final int month;

  const BudgetParams({required this.year, required this.month});

  @override
  bool operator ==(Object other) =>
      other is BudgetParams && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// 分类预算条目
class CategoryBudgetItem {
  final String categoryId;
  final String categoryName;
  final String? icon;
  final double spent;
  final double? budgetCap;
  final bool isOverBudget;
  final double progress; // spent / budgetCap, [0, 1]

  const CategoryBudgetItem({
    required this.categoryId,
    required this.categoryName,
    this.icon,
    required this.spent,
    this.budgetCap,
    this.isOverBudget = false,
    this.progress = 0,
  });
}

/// 预算页面聚合数据
class CategoryBudgetData {
  final Budget? savingGoal;
  final List<CategoryBudgetItem> categoryItems;
  final double totalExpense;
  final double totalBudget;
  final bool hasAnyBudget;

  const CategoryBudgetData({
    this.savingGoal,
    required this.categoryItems,
    required this.totalExpense,
    required this.totalBudget,
    required this.hasAnyBudget,
  });
}

/// 预算设置页面的数据 Provider
final categoryBudgetDataProvider =
    FutureProvider.family<CategoryBudgetData, BudgetParams>((ref, params) async {
  final db = ref.watch(appDatabaseProvider);
  final budgetDao = ref.watch(budgetDaoProvider);
  final categoryDao = ref.watch(categoryDaoProvider);

  final monthStr =
      '${params.year}-${params.month.toString().padLeft(2, '0')}';

  // 并行获取：储蓄目标 + 支出分类 + 月度预算
  final results = await Future.wait([
    budgetDao.getMonthlySavingGoal(monthStr),
    categoryDao.getCategoriesByKind('expense'),
    budgetDao.getMonthlyBudgets(monthStr),
  ]);

  final savingGoal = results[0] as Budget?;
  final expenseCategories = results[1] as List<Category>;
  final monthBudgets = results[2] as List<Budget>;

  // 过滤活跃分类（非归档）
  final activeCategories =
      expenseCategories.where((c) => !c.isArchived).toList();

  // 构建分类预算映射：categoryId → Budget
  final budgetMap = <String, Budget>{};
  for (final b in monthBudgets) {
    if (b.type == 'category_budget' && b.categoryId != null) {
      budgetMap[b.categoryId!] = b;
    }
  }

  // 为每个分类计算支出和预算
  final items = <CategoryBudgetItem>[];
  double totalExpense = 0;
  double totalBudget = 0;
  bool hasAnyBudget = savingGoal != null || budgetMap.isNotEmpty;

  final start = DateTime(params.year, params.month, 1);
  final end = DateTime(params.year, params.month + 1, 1);

  for (final cat in activeCategories) {
    // 查询该分类当月支出
    final spent = await db.customSelect(
      '''SELECT COALESCE(SUM(r.amount), 0) as total
         FROM records r
         WHERE r.category_id = ?
           AND r.type = 'expense'
           AND r.occurred_at >= ?
           AND r.occurred_at < ?''',
      variables: [
        Variable.withString(cat.id),
        Variable.withString(start.toIso8601String()),
        Variable.withString(end.toIso8601String()),
      ],
      readsFrom: {db.records},
    ).map((row) => row.read<double>('total')).getSingle();

    totalExpense += spent;

    final catBudget = budgetMap[cat.id];
    final budgetCap = catBudget?.targetAmount;

    if (budgetCap != null && budgetCap > 0) {
      totalBudget += budgetCap;
    }

    final isOver = budgetCap != null && spent > budgetCap;
    final progress = budgetCap != null && budgetCap > 0
        ? (spent / budgetCap).clamp(0.0, 1.0)
        : 0.0;

    items.add(CategoryBudgetItem(
      categoryId: cat.id,
      categoryName: cat.name,
      icon: cat.icon,
      spent: spent,
      budgetCap: budgetCap,
      isOverBudget: isOver,
      progress: progress,
    ));
  }

  // 按支出金额降序排列
  items.sort((a, b) => b.spent.compareTo(a.spent));

  return CategoryBudgetData(
    savingGoal: savingGoal,
    categoryItems: items,
    totalExpense: totalExpense,
    totalBudget: totalBudget,
    hasAnyBudget: hasAnyBudget,
  );
});
