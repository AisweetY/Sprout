import 'package:drift/drift.dart';

/// 冲突日志表（仅本地 Drift，用于审计追踪）
///
/// 当 LWW 冲突解决导致云端覆盖本地时，记录被覆盖的原始数据。
/// 仅用于问题追踪，不影响同步逻辑。
class ConflictLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get tblName => text().named('tbl_name')();              // 避免与 Table.tableName 冲突
  TextColumn get localUpdatedAt => text().named('local_updated_at')();     // ISO 8601
  TextColumn get remoteUpdatedAt => text().named('remote_updated_at')();   // ISO 8601
  TextColumn get resolution => text()();   // 'remote_wins'
  DateTimeColumn get resolvedAt => dateTime().named('resolved_at').withDefault(currentDateAndTime)();
}
