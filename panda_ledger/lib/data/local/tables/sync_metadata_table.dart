import 'package:drift/drift.dart';

/// 同步元数据表（仅本地 Drift，不对应 Supabase 表）
///
/// 存储增量同步的游标信息（上次拉取时间、是否完成初始同步等）。
/// 使用 key-value 模式，便于未来扩展更多元数据字段。
class SyncMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
