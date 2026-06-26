import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/sync_queue_table.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase> with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  /// 获取所有待处理项（按创建时间排序）
  Future<List<SyncQueueData>> getPendingItems({int limit = 100}) {
    return (select(db.syncQueue)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// 插入同步队列项
  Future<void> enqueue(SyncQueueCompanion item) {
    return into(db.syncQueue).insert(item);
  }

  /// 增加重试次数（使用原始 SQL 执行 retry_count + 1，避免读写竞态）
  Future<void> incrementRetry(int id) {
    return customStatement(
      'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
      [Variable.withInt(id)],
    );
  }

  /// 删除已完成的队列项
  Future<void> dequeue(int id) {
    return (delete(db.syncQueue)..where((t) => t.id.equals(id))).go();
  }
}
