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
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// 按账户获取流水
  Future<List<Record>> getRecordsByAccount(String accountId, {int limit = 50}) {
    return (select(db.records)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit))
        .get();
  }

  /// 获取指定日期范围的收支汇总
  Future<Map<String, double>> getSummary(DateTime start, DateTime end) {
    final query = db.customSelect(
      'SELECT type, COALESCE(SUM(amount), 0) as total '
      'FROM records '
      "WHERE occurred_at >= ? AND occurred_at < ? AND type IN ('expense', 'income') "
      'GROUP BY type',
      variables: [
        Variable.withString(start.toIso8601String()),
        Variable.withString(end.toIso8601String()),
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
          ..where((t) => t.occurredAt.isBetweenValues(start, end))
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
      'SELECT COALESCE(SUM(amount), 0) as total FROM records WHERE category_id = ? AND type = ? AND occurred_at >= ? AND occurred_at < ?',
      variables: [
        Variable.withString(categoryId),
        Variable.withString('expense'),
        Variable.withString(start.toIso8601String()),
        Variable.withString(end.toIso8601String()),
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
      ..where((t) => t.occurredAt.isBetweenValues(start, end))
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]));
  }
}
