import 'package:drift/drift.dart';

/// 预算 / 储蓄目标表
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get month => text()();
  TextColumn get type => text().customConstraint(
    "NOT NULL CHECK (type IN ('saving_goal', 'category_budget'))",
  )();
  TextColumn get categoryId => text().named('category_id').nullable()();
  RealColumn get targetAmount => real().named('target_amount')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().named('sync_status').withDefault(const Constant('synced'))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
