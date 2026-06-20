import 'package:drift/drift.dart';

/// 流水主表
class Records extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get accountId => text().named('account_id')();
  TextColumn get toAccountId => text().named('to_account_id').nullable()();
  RealColumn get amount => real().customConstraint('NOT NULL CHECK (amount > 0)')();
  TextColumn get type => text().customConstraint(
    "NOT NULL CHECK (type IN ('expense', 'income', 'transfer', 'adjustment'))",
  )();
  TextColumn get categoryId => text().named('category_id').nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime().named('occurred_at').withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().named('sync_status').withDefault(const Constant('pending'))();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
