import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/budgets_table.dart';

part 'budget_dao.g.dart';

@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  /// 获取某月所有预算
  Future<List<Budget>> getMonthlyBudgets(String month) {
    return (select(db.budgets)..where((t) => t.month.equals(month) & t.deleted.equals(false))).get();
  }

  /// 获取某月的储蓄目标
  Future<Budget?> getMonthlySavingGoal(String month) {
    return (select(db.budgets)
          ..where((t) => t.month.equals(month) & t.type.equals('saving_goal') & t.deleted.equals(false)))
        .getSingleOrNull();
  }

  /// 获取某分类的月度预算
  Future<Budget?> getCategoryBudget(String month, String categoryId) {
    return (select(db.budgets)
          ..where((t) =>
              t.month.equals(month) &
              t.type.equals('category_budget') &
              t.categoryId.equals(categoryId) &
              t.deleted.equals(false)))
        .getSingleOrNull();
  }

  /// 插入预算
  Future<void> insertBudget(Insertable<Budget> budget) {
    return into(db.budgets).insert(budget);
  }

  /// 更新预算目标金额
  Future<void> updateBudgetAmount(String id, double newAmount) {
    return (update(db.budgets)..where((t) => t.id.equals(id))).write(
      BudgetsCompanion(targetAmount: Value(newAmount)),
    );
  }

  /// 删除预算（软删除）
  Future<void> softDeleteBudget(String id) {
    return (update(db.budgets)..where((t) => t.id.equals(id))).write(
      BudgetsCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 监听月度预算
  Selectable<Budget> watchMonthlyBudgets(String month) {
    return (select(db.budgets)..where((t) => t.month.equals(month) & t.deleted.equals(false)));
  }
}
