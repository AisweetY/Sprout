import 'package:drift/drift.dart';

/// 账户表
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get name => text()();
  TextColumn get type => text().customConstraint(
    "NOT NULL CHECK (type IN ('cash', 'bank', 'credit', 'loan', 'invest', 'other'))",
  )();
  RealColumn get balance => real()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  BoolColumn get isLiability => boolean().named('is_liability').withDefault(const Constant(false))();
  BoolColumn get includeInNet => boolean().named('include_in_net').withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().named('is_archived').withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().named('sync_status').withDefault(const Constant('synced'))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
