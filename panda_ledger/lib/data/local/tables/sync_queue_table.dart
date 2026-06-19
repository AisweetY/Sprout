import 'package:drift/drift.dart';

/// 同步队列表（仅本地 Drift）
///
/// 注意：列名不能与 Table 基类的 tableName 属性冲突，
/// 故使用 tblName 代替。
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get operationType => text()(); // → operation_type
  TextColumn get tblName => text()(); // → tbl_name（避免与 Table.tableName 冲突）
  TextColumn get recordId => text()(); // → record_id
  TextColumn get payload => text()(); // JSON
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)(); // → created_at
  IntColumn get retryCount => integer().withDefault(const Constant(0))(); // → retry_count
}
