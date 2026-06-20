import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/sync_metadata_table.dart';

part 'sync_metadata_dao.g.dart';

/// 同步元数据 DAO
///
/// 管理增量同步的游标信息（key-value 模式）。
@DriftAccessor(tables: [SyncMetadata])
class SyncMetadataDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetadataDaoMixin {
  SyncMetadataDao(super.db);

  /// 读取元数据值
  Future<String?> get(String key) async {
    final row = await (select(db.syncMetadata)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// 写入元数据（INSERT OR REPLACE）
  Future<void> set(String key, String value) async {
    await into(db.syncMetadata).insert(
      SyncMetadataCompanion(key: Value(key), value: Value(value)),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// 获取上次拉取时间
  Future<DateTime?> getLastPullAt() async {
    final val = await get('last_pull_at');
    if (val == null) return null;
    return DateTime.tryParse(val);
  }

  /// 设置上次拉取时间
  Future<void> setLastPullAt(DateTime time) async {
    await set('last_pull_at', time.toUtc().toIso8601String());
  }

  /// 是否完成过初始全量同步
  Future<bool> hasDoneInitialSync() async {
    final val = await get('initial_sync_done');
    return val == 'true';
  }

  /// 标记初始同步完成
  Future<void> markInitialSyncDone() async {
    await set('initial_sync_done', 'true');
  }
}
