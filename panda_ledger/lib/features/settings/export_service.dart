import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/account_repository.dart';

/// 数据导出服务 — CSV / JSON 导出 + 系统分享
class ExportService {
  final AppDatabase db;
  final AccountRepository accountRepo;

  ExportService({required this.db, required this.accountRepo});

  // ═════════════════════════════════════════════════════════════════════════
  // CSV 导出
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> exportCsv() async {
    final records = await db.recordDao.getRecords(limit: 99999, offset: 0);
    final accounts = await accountRepo.getAllAccounts();
    final categories =
        await (db.select(db.categories)..where((t) => t.isArchived.equals(false)))
            .get();

    // 构建分类名称映射
    final categoryNames = <String, String>{};
    for (final c in categories) {
      categoryNames[c.id] = c.name;
    }

    // 构建账户名称映射
    final accountNames = <String, String>{};
    for (final a in accounts) {
      accountNames[a.id] = a.name;
    }

    final rows = <List<String>>[];

    // ── 流水记录 ──
    rows.add(['--- 流水记录 ---']);
    rows.add(['日期', '类型', '金额', '分类', '账户', '备注', '来源']);
    for (final r in records) {
      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(r.occurredAt);
      final typeLabel = _typeLabel(r.type);
      final categoryName = categoryNames[r.categoryId] ?? '';
      final accountName = accountNames[r.accountId] ?? '';
      rows.add([
        dateStr,
        typeLabel,
        r.amount.toStringAsFixed(2),
        categoryName,
        accountName,
        r.note ?? '',
        r.source,
      ]);
    }

    rows.add([]);
    rows.add(['--- 账户 ---']);
    rows.add(['名称', '类型', '余额', '是否负债', '归档']);
    for (final a in accounts) {
      rows.add([
        a.name,
        a.type,
        a.balance.toStringAsFixed(2),
        a.isLiability ? '是' : '否',
        a.isArchived ? '是' : '否',
      ]);
    }

    rows.add([]);
    rows.add(['--- 分类 ---']);
    rows.add(['名称', '类型', '父分类ID', '图标', '归档']);
    for (final c in categories) {
      rows.add([
        c.name,
        c.kind == 'expense' ? '支出' : '收入',
        c.parentId ?? '',
        c.icon ?? '',
        c.isArchived ? '是' : '否',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    await _shareFile(csv, 'csv');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // JSON 导出
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> exportJson() async {
    final records = await db.recordDao.getRecords(limit: 99999, offset: 0);
    final accounts = await accountRepo.getAllAccounts();
    final categories =
        await (db.select(db.categories)..where((t) => t.isArchived.equals(false)))
            .get();

    final json = {
      'exportTime': DateTime.now().toIso8601String(),
      'appVersion': '1.0.0',
      'records': records
          .map((r) => {
                'id': r.id,
                'type': r.type,
                'amount': r.amount,
                'categoryId': r.categoryId,
                'accountId': r.accountId,
                'toAccountId': r.toAccountId,
                'note': r.note,
                'occurredAt': r.occurredAt.toIso8601String(),
                'source': r.source,
                'syncStatus': r.syncStatus,
              })
          .toList(),
      'accounts': accounts
          .map((a) => {
                'id': a.id,
                'name': a.name,
                'type': a.type,
                'balance': a.balance,
                'currency': a.currency,
                'isLiability': a.isLiability,
                'includeInNet': a.includeInNet,
                'isArchived': a.isArchived,
              })
          .toList(),
      'categories': categories
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'kind': c.kind,
                'parentId': c.parentId,
                'icon': c.icon,
                'sortOrder': c.sortOrder,
                'isArchived': c.isArchived,
              })
          .toList(),
    };

    final encoded = const JsonEncoder.withIndent('  ').convert(json);
    await _shareFile(encoded, 'json');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 文件分享
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _shareFile(String content, String ext) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filename = 'panda_ledger_export_$timestamp.$ext';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '熊猫记账数据导出',
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'expense':
        return '支出';
      case 'income':
        return '收入';
      case 'transfer':
        return '转账';
      case 'adjustment':
        return '调整';
      default:
        return type;
    }
  }
}

/// ExportService Provider
final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(
    db: ref.watch(appDatabaseProvider),
    accountRepo: ref.watch(accountRepositoryProvider),
  );
});
