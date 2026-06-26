import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ledger/data/local/database.dart';
import 'package:panda_ledger/data/local/dao/account_dao.dart';
import 'package:panda_ledger/data/local/dao/record_dao.dart';
import 'package:panda_ledger/data/local/dao/sync_queue_dao.dart';
import 'package:panda_ledger/data/repository/record_repository.dart';
import 'package:panda_ledger/data/sync/sync_queue_dao_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 核心业务逻辑测试：余额更新 / 撤销 / 差额补正。
///
/// 通过 RecordRepository.createRecord / deleteRecord / updateRecord
/// 公有 API 间接验证 _updateAccountBalance 和 _reverseAccountBalance。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late AccountDao accountDao;
  late RecordDao recordDao;
  late RecordRepository repo;

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    accountDao = AccountDao(db);
    recordDao = RecordDao(db);
    final syncQueueDao = SyncQueueDao(db);
    final syncQueue = SyncQueueService(dao: syncQueueDao, db: db);
    repo = RecordRepository(
      dao: recordDao,
      accountDao: accountDao,
      syncQueue: syncQueue,
    );
  });

  tearDown(() async => db.close());

  /// 插入测试账户
  Future<void> seedAccount({
    String id = 'a-001',
    String name = '测试账户',
    double balance = 1000,
    bool isLiability = false,
    String type = 'cash',
    String userId = 'u-1',
  }) async {
    await accountDao.insertAccount(
      AccountsCompanion.insert(
        id: id,
        userId: userId,
        name: name,
        type: type,
        balance: balance,
        isLiability: Value(isLiability),
        isArchived: const Value(false),
        includeInNet: const Value(true),
        deleted: const Value(false),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // createRecord → 余额更新
  // ═══════════════════════════════════════════════════════════════

  group('createRecord 余额更新', () {
    test('资产账户 — 支出：余额减少', () async {
      await seedAccount(balance: 1000);
      await repo.createRecord(
        userId: 'u-1', accountId: 'a-001', amount: 200, type: 'expense',
      );
      final acc = await accountDao.getById('a-001');
      expect(acc!.balance, 800);
    });

    test('资产账户 — 收入：余额增加', () async {
      await seedAccount(balance: 1000);
      await repo.createRecord(
        userId: 'u-1', accountId: 'a-001', amount: 300, type: 'income',
      );
      final acc = await accountDao.getById('a-001');
      expect(acc!.balance, 1300);
    });
  });

  group('createRecord 负债账户方向', () {
    test('负债 — 支出：欠款增加', () async {
      await seedAccount(
        id: 'card', name: '信用卡', balance: 500,
        isLiability: true, type: 'credit',
      );
      await repo.createRecord(
        userId: 'u-1', accountId: 'card', amount: 200, type: 'expense',
      );
      final acc = await accountDao.getById('card');
      expect(acc!.balance, 700); // 500 → 700 欠款加深
    });

    test('负债 — 收入：还债减欠款', () async {
      await seedAccount(
        id: 'card', name: '信用卡', balance: 500,
        isLiability: true, type: 'credit',
      );
      await repo.createRecord(
        userId: 'u-1', accountId: 'card', amount: 200, type: 'income',
      );
      final acc = await accountDao.getById('card');
      expect(acc!.balance, 300); // 500 → 300 欠款减少
    });
  });

  group('createRecord 转账', () {
    test('资产→资产：转出减，转入增', () async {
      await seedAccount(id: 'cash', name: '现金', balance: 1000);
      await seedAccount(id: 'bank', name: '银行', balance: 500);
      await repo.createRecord(
        userId: 'u-1', accountId: 'cash', toAccountId: 'bank',
        amount: 200, type: 'transfer',
      );
      final cash = await accountDao.getById('cash');
      final bank = await accountDao.getById('bank');
      expect(cash!.balance, 800);
      expect(bank!.balance, 700);
    });

    test('资产→负债（还信用卡）：转出减，欠款减', () async {
      await seedAccount(id: 'cash', name: '现金', balance: 1000);
      await seedAccount(
        id: 'card', name: '信用卡', balance: 500,
        isLiability: true, type: 'credit',
      );
      await repo.createRecord(
        userId: 'u-1', accountId: 'cash', toAccountId: 'card',
        amount: 200, type: 'transfer',
      );
      final cash = await accountDao.getById('cash');
      final card = await accountDao.getById('card');
      expect(cash!.balance, 800);  // 转出扣款
      expect(card!.balance, 300);  // 负债减少
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // deleteRecord → 余额撤销
  // ═══════════════════════════════════════════════════════════════

  group('deleteRecord 余额撤销', () {
    test('撤销支出：余额恢复', () async {
      await seedAccount(balance: 1000);
      final id = await repo.createRecord(
        userId: 'u-1', accountId: 'a-001', amount: 200, type: 'expense',
      );
      expect((await accountDao.getById('a-001'))!.balance, 800);

      final record = await recordDao.getById(id);
      await repo.deleteRecord(record!);
      expect((await accountDao.getById('a-001'))!.balance, 1000);
    });

    test('撤销转账：双方余额恢复', () async {
      await seedAccount(id: 'cash', name: '现金', balance: 1000);
      await seedAccount(id: 'bank', name: '银行', balance: 500);
      final id = await repo.createRecord(
        userId: 'u-1', accountId: 'cash', toAccountId: 'bank',
        amount: 200, type: 'transfer',
      );
      final record = await recordDao.getById(id);
      await repo.deleteRecord(record!);
      expect((await accountDao.getById('cash'))!.balance, 1000);
      expect((await accountDao.getById('bank'))!.balance, 500);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // updateRecord → 差额补正
  // ═══════════════════════════════════════════════════════════════

  group('updateRecord 差额补正', () {
    test('修改金额：余额按差额调整', () async {
      await seedAccount(balance: 1000);
      final id = await repo.createRecord(
        userId: 'u-1', accountId: 'a-001', amount: 200, type: 'expense',
      );
      expect((await accountDao.getById('a-001'))!.balance, 800);

      await repo.updateRecord(
        recordId: id,
        accountId: 'a-001',
        amount: 300,
        type: 'expense',
        oldAmount: 200,
        oldType: 'expense',
      );
      // 旧200→新300，差额+100，余额再减100
      expect((await accountDao.getById('a-001'))!.balance, 700);
    });

    test('修改类型：撤销旧类型 + 应用新类型', () async {
      await seedAccount(balance: 1000);
      final id = await repo.createRecord(
        userId: 'u-1', accountId: 'a-001', amount: 200, type: 'expense',
      );
      expect((await accountDao.getById('a-001'))!.balance, 800);

      // 支出→收入：撤销 -200，再 +200 = 1000 + 200 = 1200
      await repo.updateRecord(
        recordId: id,
        accountId: 'a-001',
        amount: 200,
        type: 'income',
        oldAmount: 200,
        oldType: 'expense',
      );
      expect((await accountDao.getById('a-001'))!.balance, 1200);
    });
  });
}
