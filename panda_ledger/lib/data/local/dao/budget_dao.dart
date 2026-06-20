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
  ///
  /// 使用 LIMIT 1 + get() 替代 getSingleOrNull()，避免多行数据时抛出
  /// "Bad state: Too many elements" 错误（可能由同步竞态或重复创建导致）。
  Future<Budget?> getMonthlySavingGoal(String month) async {
    final rows = await (select(db.budgets)
          ..where((t) => t.month.equals(month) & t.type.equals('saving_goal') & t.deleted.equals(false))
          ..limit(1))
        .get();
    return rows.isNotEmpty ? rows.first : null;
  }

  /// 获取某分类的月度预算
  ///
  /// 使用 LIMIT 1 + get() 替代 getSingleOrNull()，原因同上。
  Future<Budget?> getCategoryBudget(String month, String categoryId) async {
    final rows = await (select(db.budgets)
          ..where((t) =>
              t.month.equals(month) &
              t.type.equals('category_budget') &
              t.categoryId.equals(categoryId) &
              t.deleted.equals(false))
          ..limit(1))
        .get();
    return rows.isNotEmpty ? rows.first : null;
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
