import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ledger/data/category_dedup_service.dart';
import 'package:panda_ledger/data/local/database.dart';
import 'package:panda_ledger/data/local/dao/sync_queue_dao.dart';
import 'package:panda_ledger/data/sync/sync_queue_dao_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 分类去重服务测试
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late CategoryDedupService service;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    final sqDao = SyncQueueDao(db);
    final syncQueue = SyncQueueService(dao: sqDao, db: db);
    service = CategoryDedupService(db: db, syncQueue: syncQueue);
  });

  tearDown(() async => db.close());

  Future<String> _insertCat({
    required String name,
    required String kind,
    String? parentId,
    required String id,
    DateTime? updatedAt,
  }) async {
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: id,
        userId: 'u-1',
        name: name,
        kind: kind,
        parentId: Value.absentIfNull(parentId),
        icon: const Value('help_outline'),
        updatedAt: Value(updatedAt ?? DateTime.now()),
      ),
    );
    return id;
  }

  Future<Category?> _getById(String id) =>
      (db.select(db.categories)..where((t) => t.id.equals(id))).getSingleOrNull();

  group('deduplicateOnce', () {
    test('无重复时返回 0', () async {
      await _insertCat(name: '餐饮', kind: 'expense', id: 'a');
      await _insertCat(name: '工资', kind: 'income', id: 'b');

      expect(await service.deduplicateOnce(), 0);
    });

    test('不同 kind 同名不冲突', () async {
      await _insertCat(name: '其他', kind: 'expense', id: 'a');
      await _insertCat(name: '其他', kind: 'income', id: 'b');

      expect(await service.deduplicateOnce(), 0);
    });

    test('重复分类：保留最早的，软删除多余的', () async {
      await _insertCat(name: '餐饮', kind: 'expense', id: 'old',
        updatedAt: DateTime(2025, 1, 1));
      await _insertCat(name: '餐饮', kind: 'expense', id: 'dup',
        updatedAt: DateTime(2025, 6, 1));

      expect(await service.deduplicateOnce(), 1);

      final old = await _getById('old');
      final dup = await _getById('dup');
      expect(old, isNotNull);
      expect(old!.deleted, isFalse);
      expect(dup!.deleted, isTrue);
    });

    test('重复分类的子分类迁移到保留项', () async {
      await _insertCat(name: '餐饮', kind: 'expense', id: 'old',
        updatedAt: DateTime(2025, 1, 1));
      await _insertCat(name: '外卖', kind: 'expense',
        parentId: 'old', id: 'sub');
      await _insertCat(name: '餐饮', kind: 'expense', id: 'dup',
        updatedAt: DateTime(2025, 6, 1));

      await service.deduplicateOnce();

      final sub = await _getById('sub');
      expect(sub!.deleted, isFalse);
      expect(sub.parentId, 'old'); // 迁移到保留分类下
    });
  });
}
