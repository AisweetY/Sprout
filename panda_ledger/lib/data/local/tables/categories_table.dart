import 'package:drift/drift.dart';

/// 自定义分类表
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get name => text()();
  TextColumn get parentId => text().named('parent_id').nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get kind => text().customConstraint(
    "NOT NULL CHECK (kind IN ('expense', 'income'))",
  )();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().named('is_archived').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
