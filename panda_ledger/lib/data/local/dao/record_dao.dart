import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/records_table.dart';

part 'record_dao.g.dart';

@DriftAccessor(tables: [Records])
class RecordDao extends DatabaseAccessor<AppDatabase> with _$RecordDaoMixin {
  RecordDao(super.db);

  /// 获取最近流水（分页）
  Future<List<Record>> getRecords({int limit = 50, int offset = 0}) {
    return (select(db.records)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// 按账户获取流水
  Future<List<Record>> getRecordsByAccount(String accountId, {int limit = 50}) {
    return (select(db.records)
          ..where((t) => t.accountId.equals(accountId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit))
        .get();
  }

  /// 获取指定日期范围的收支汇总
  Future<Map<String, double>> getSummary(DateTime start, DateTime end) {
    final query = db.customSelect(
      'SELECT type, COALESCE(SUM(amount), 0) as total '
      'FROM records '
      "WHERE occurred_at >= ? AND occurred_at < ? AND type IN ('expense', 'income') AND deleted = 0 "
      'GROUP BY type',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {db.records},
    );
    return query.map((row) {
      return (
        type: row.read<String>('type'),
        total: row.read<double>('total'),
      );
    }).get().then((rows) {
      double expense = 0, income = 0;
      for (final r in rows) {
        if (r.type == 'expense') expense = r.total;
        if (r.type == 'income') income = r.total;
      }
      return {'expense': expense, 'income': income};
    });
  }

  /// 获取指定日期范围的流水列表
  Future<List<Record>> getRecordsInRange(DateTime start, DateTime end) {
    return (select(db.records)
          ..where((t) => t.occurredAt.isBetweenValues(start, end) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .get();
  }

  /// 获取指定月份的流水（委托给 getRecordsInRange）
  Future<List<Record>> getMonthlyRecords(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return getRecordsInRange(start, end);
  }

  /// 获取某月某分类的支出合计
  Future<double> getCategoryMonthlyTotal(String categoryId, int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final query = db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) as total FROM records WHERE category_id = ? AND type = ? AND occurred_at >= ? AND occurred_at < ? AND deleted = 0',
      variables: [
        Variable.withString(categoryId),
        Variable.withString('expense'),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {db.records},
    );
    return query.map((row) => row.read<double>('total')).getSingle();
  }

  /// 获取当月收支汇总（委托给 getSummary）
  Future<Map<String, double>> getMonthlySummary(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return getSummary(start, end);
  }

  /// 插入流水
  Future<void> insertRecord(Insertable<Record> record) {
    return into(db.records).insert(record);
  }

  /// 更新同步状态
  Future<void> updateSyncStatus(String id, String status) {
    return (update(db.records)..where((t) => t.id.equals(id))).write(
      RecordsCompanion(syncStatus: Value(status)),
    );
  }

  /// 获取待同步记录
  Future<List<Record>> getPendingSyncRecords() {
    return (select(db.records)..where((t) => t.syncStatus.equals('pending'))).get();
  }

  /// 监听月度流水（Riverpod watch）
  Selectable<Record> watchMonthlyRecords(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return (select(db.records)
      ..where((t) => t.occurredAt.isBetweenValues(start, end) & t.deleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]));
  }

  /// 按 ID 获取单条记录
  Future<Record?> getById(String id) {
    return (select(db.records)..where((t) => t.id.equals(id) & t.deleted.equals(false))).getSingleOrNull();
  }

  /// 更新记录
  Future<bool> updateRecord(String id, RecordsCompanion data) {
    return (update(db.records)..where((t) => t.id.equals(id)))
        .write(data)
        .then((v) => v > 0);
  }

  /// 删除记录（软删除）
  Future<void> softDeleteRecord(String id) {
    return (update(db.records)..where((t) => t.id.equals(id))).write(
      RecordsCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 按 ID 获取单条记录（含已删除，供同步使用）
  Future<Record?> getByIdAny(String id) {
    return (select(db.records)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 搜索 + 筛选流水（分页）
  ///
  /// 返回 (records, hasMore)
  Future<({List<Record> records, bool hasMore})> searchRecords({
    DateTime? start,
    DateTime? end,
    String? categoryId,
    String? accountId,
    String? keyword,
    int limit = 30,
    int offset = 0,
  }) async {
    // 构建查询：先获取基础结果集，再加条件
    var query = select(db.records)..where((t) => t.deleted.equals(false));

    // 时间范围
    if (start != null && end != null) {
      query = query..where((t) => t.occurredAt.isBetweenValues(start, end));
    } else if (start != null) {
      query = query..where((t) => t.occurredAt.isBiggerOrEqualValue(start));
    } else if (end != null) {
      query = query..where((t) => t.occurredAt.isSmallerThanValue(end));
    }

    // 分类筛选
    if (categoryId != null) {
      query = query..where((t) => t.categoryId.equals(categoryId));
    }

    // 账户筛选
    if (accountId != null) {
      query = query..where((t) => t.accountId.equals(accountId));
    }

    // 备注关键字搜索
    if (keyword != null && keyword.isNotEmpty) {
      query = query..where((t) => t.note.like('%$keyword%'));
    }

    // 排序 + 分页（多取一条判断 hasMore）
    query = query
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
      ..limit(limit + 1, offset: offset);

    final rows = await query.get();
    final hasMore = rows.length > limit;
    if (hasMore) rows.removeLast();

    return (records: rows, hasMore: hasMore);
  }
}
