import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/account_repository.dart';

/// 资产时间维度参数
class AssetsTimeParams {
  final TimeDimension dimension;
  final DateTime? customStart;
  final DateTime? customEnd;

  const AssetsTimeParams({
    this.dimension = TimeDimension.month,
    this.customStart,
    this.customEnd,
  });

  @override
  bool operator ==(Object other) =>
      other is AssetsTimeParams &&
      other.dimension == dimension &&
      other.customStart == customStart &&
      other.customEnd == customEnd;

  @override
  int get hashCode => Object.hash(dimension, customStart, customEnd);
}

/// 资产页数据 Provider — 监听账户变化，自动刷新
final assetsDataProvider =
    FutureProvider.family<AssetsData, AssetsTimeParams>((ref, params) async {
  final accountRepo = ref.watch(accountRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);

  final accounts = await accountRepo.getAllAccounts();
  final active = accounts.where((a) => !a.isArchived).toList();

  double totalAssets = 0;
  double totalLiabilities = 0;

  for (final a in active) {
    if (a.includeInNet) {
      if (a.isLiability) {
        totalLiabilities += a.balance;
      } else {
        totalAssets += a.balance;
      }
    }
  }

  final netWorth = totalAssets - totalLiabilities;

  // 按类型分组
  final Map<String, List<Account>> groups = {};
  for (final a in active) {
    groups.putIfAbsent(a.type, () => []).add(a);
  }

  // ── 计算净资产趋势 ──
  final snapshots = await _computeSnapshots(db, netWorth, params);

  return AssetsData(
    totalAssets: totalAssets,
    totalLiabilities: totalLiabilities,
    netWorth: netWorth,
    accountGroups: groups,
    accounts: active,
    snapshots: snapshots,
  );
});

/// 快照数据点
class SnapshotPoint {
  final DateTime date;
  final double netWorth;
  final String label; // X轴标签

  const SnapshotPoint({
    required this.date,
    required this.netWorth,
    required this.label,
  });
}

/// 根据时间维度计算净资产快照
Future<List<SnapshotPoint>> _computeSnapshots(
  AppDatabase db,
  double currentNetWorth,
  AssetsTimeParams params,
) async {
  switch (params.dimension) {
    case TimeDimension.day:
      return _computeDailySnapshots(db, currentNetWorth, 30);
    case TimeDimension.week:
      return _computeWeeklySnapshots(db, currentNetWorth, 12);
    case TimeDimension.month:
      return _computeMonthlySnapshots(db, currentNetWorth, 12);
    case TimeDimension.year:
      return _computeYearlySnapshots(db, currentNetWorth);
    case TimeDimension.custom:
      if (params.customStart != null && params.customEnd != null) {
        return _computeCustomSnapshots(
            db, currentNetWorth, params.customStart!, params.customEnd!);
      }
      return _computeMonthlySnapshots(db, currentNetWorth, 12);
  }
}

/// 日维度：最近 N 天
Future<List<SnapshotPoint>> _computeDailySnapshots(
  AppDatabase db,
  double currentNetWorth,
  int days,
) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day - days + 1);

  final query = db.customSelect(
    '''SELECT
         DATE(r.occurred_at) as dt,
         COALESCE(SUM(CASE WHEN r.type = 'income' THEN r.amount ELSE 0 END), 0) -
         COALESCE(SUM(CASE WHEN r.type = 'expense' THEN r.amount ELSE 0 END), 0) as net
       FROM records r
       WHERE r.occurred_at >= ?
       GROUP BY dt
       ORDER BY dt DESC''',
    variables: [Variable.withString(start.toIso8601String())],
    readsFrom: {db.records},
  );

  final rows = await query.get();
  final Map<String, double> dailyNet = {};
  for (final row in rows) {
    dailyNet[row.read<String>('dt')] = row.read<double>('net');
  }

  // 生成日期列表
  final dates = <DateTime>[];
  for (int i = 0; i < days; i++) {
    dates.add(DateTime(now.year, now.month, now.day - i));
  }
  dates.sort(); // 从早到晚

  // 回溯计算
  double running = currentNetWorth;
  for (final d in dates) {
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    running -= dailyNet[key] ?? 0;
  }

  final result = <SnapshotPoint>[];
  for (final d in dates) {
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    running += dailyNet[key] ?? 0;
    result.add(SnapshotPoint(
      date: d,
      netWorth: running,
      label: '${d.month}/${d.day}',
    ));
  }
  return result;
}

/// 周维度：最近 N 周（按日查询后在内存中按周分组）
Future<List<SnapshotPoint>> _computeWeeklySnapshots(
  AppDatabase db,
  double currentNetWorth,
  int weeks,
) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day - weeks * 7 + 1);

  // 按日查询
  final query = db.customSelect(
    '''SELECT
         DATE(r.occurred_at) as dt,
         COALESCE(SUM(CASE WHEN r.type = 'income' THEN r.amount ELSE 0 END), 0) -
         COALESCE(SUM(CASE WHEN r.type = 'expense' THEN r.amount ELSE 0 END), 0) as net
       FROM records r
       WHERE r.occurred_at >= ?
       GROUP BY dt
       ORDER BY dt DESC''',
    variables: [Variable.withString(start.toIso8601String())],
    readsFrom: {db.records},
  );

  final rows = await query.get();
  final Map<String, double> dailyNet = {};
  for (final row in rows) {
    dailyNet[row.read<String>('dt')] = row.read<double>('net');
  }

  // 生成日期列表
  final days = <DateTime>[];
  for (int i = 0; i < weeks * 7; i++) {
    days.add(DateTime(now.year, now.month, now.day - i));
  }
  days.sort();

  // 回溯计算每日净资产
  double running = currentNetWorth;
  for (final d in days) {
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    running -= dailyNet[key] ?? 0;
  }

  // 收集每周一的净资产
  final result = <SnapshotPoint>[];
  for (final d in days) {
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    running += dailyNet[key] ?? 0;
    if (d.weekday == DateTime.monday) {
      result.add(SnapshotPoint(
        date: d,
        netWorth: running,
        label: '${d.month}/${d.day}',
      ));
    }
  }
  return result;
}

/// 月维度：最近 N 个月
Future<List<SnapshotPoint>> _computeMonthlySnapshots(
  AppDatabase db,
  double currentNetWorth,
  int months,
) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - months + 1, 1);

  final query = db.customSelect(
    '''SELECT
         CAST(strftime('%Y', r.occurred_at) AS INTEGER) as yr,
         CAST(strftime('%m', r.occurred_at) AS INTEGER) as mo,
         COALESCE(SUM(CASE WHEN r.type = 'income' THEN r.amount ELSE 0 END), 0) -
         COALESCE(SUM(CASE WHEN r.type = 'expense' THEN r.amount ELSE 0 END), 0) as net
       FROM records r
       WHERE r.occurred_at >= ?
       GROUP BY yr, mo
       ORDER BY yr DESC, mo DESC''',
    variables: [Variable.withString(start.toIso8601String())],
    readsFrom: {db.records},
  );

  final rows = await query.get();
  final Map<String, double> monthlyNet = {};
  for (final row in rows) {
    final yr = row.read<int?>('yr');
    final mo = row.read<int?>('mo');
    if (yr == null || mo == null) continue; // 防御性跳过 null 值
    monthlyNet['$yr-${mo.toString().padLeft(2, '0')}'] = row.read<double>('net');
  }

  // 生成月份列表
  final monthList = <({int year, int month})>[];
  for (int i = months - 1; i >= 0; i--) {
    final d = DateTime(now.year, now.month - i, 1);
    monthList.add((year: d.year, month: d.month));
  }

  double running = currentNetWorth;
  for (final m in monthList) {
    final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    running -= monthlyNet[key] ?? 0;
  }

  final result = <SnapshotPoint>[];
  for (final m in monthList) {
    final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    running += monthlyNet[key] ?? 0;
    result.add(SnapshotPoint(
      date: DateTime(m.year, m.month, 1),
      netWorth: running,
      label: '${m.month}月',
    ));
  }
  return result;
}

/// 年维度：所有年份
Future<List<SnapshotPoint>> _computeYearlySnapshots(
  AppDatabase db,
  double currentNetWorth,
) async {
  final query = db.customSelect(
    '''SELECT
         CAST(strftime('%Y', r.occurred_at) AS INTEGER) as yr,
         COALESCE(SUM(CASE WHEN r.type = 'income' THEN r.amount ELSE 0 END), 0) -
         COALESCE(SUM(CASE WHEN r.type = 'expense' THEN r.amount ELSE 0 END), 0) as net
       FROM records r
       WHERE r.occurred_at IS NOT NULL
       GROUP BY yr
       ORDER BY yr DESC''',
    readsFrom: {db.records},
  );

  final rows = await query.get();
  if (rows.isEmpty) return [];

  final Map<int, double> yearlyNet = {};
  for (final row in rows) {
    final yr = row.read<int?>('yr');
    if (yr == null) continue; // 防御性跳过 null 年份
    yearlyNet[yr] = row.read<double>('net');
  }

  final years = yearlyNet.keys.toList()..sort();
  double running = currentNetWorth;
  for (final yr in years) {
    running -= yearlyNet[yr] ?? 0;
  }

  final result = <SnapshotPoint>[];
  for (final yr in years) {
    running += yearlyNet[yr] ?? 0;
    result.add(SnapshotPoint(
      date: DateTime(yr, 1, 1),
      netWorth: running,
      label: '$yr',
    ));
  }
  return result;
}

/// 自定义范围
Future<List<SnapshotPoint>> _computeCustomSnapshots(
  AppDatabase db,
  double currentNetWorth,
  DateTime start,
  DateTime end,
) async {
  final duration = end.difference(start).inDays;

  if (duration <= 31) {
    // 短范围：按日聚合
    return _computeDailyRangeSnapshots(db, currentNetWorth, start, end);
  } else if (duration <= 366) {
    // 中等范围：按周聚合
    return _computeWeekRangeSnapshots(db, currentNetWorth, start, end);
  } else {
    // 长范围：按月聚合
    return _computeMonthRangeSnapshots(db, currentNetWorth, start, end);
  }
}

Future<List<SnapshotPoint>> _computeDailyRangeSnapshots(
  AppDatabase db, double currentNetWorth, DateTime start, DateTime end,
) async {
  final query = db.customSelect(
    '''SELECT DATE(r.occurred_at) as dt,
         COALESCE(SUM(CASE WHEN r.type='income' THEN r.amount ELSE 0 END),0) -
         COALESCE(SUM(CASE WHEN r.type='expense' THEN r.amount ELSE 0 END),0) as net
       FROM records r
       WHERE r.occurred_at >= ? AND r.occurred_at < ?
       GROUP BY dt ORDER BY dt ASC''',
    variables: [
      Variable.withString(start.toIso8601String()),
      Variable.withString(end.toIso8601String()),
    ],
    readsFrom: {db.records},
  );

  final rows = await query.get();
  final Map<String, double> netMap = {};
  for (final row in rows) {
    netMap[row.read<String>('dt')] = row.read<double>('net');
  }

  // 从 start 到 end 的所有日期
  final days = <DateTime>[];
  for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
    days.add(d);
  }

  // 直接计算（不回溯，因为自定义范围可能不与当前净资产对齐）
  final result = <SnapshotPoint>[];
  double running = 0; // 累计净收入
  for (final d in days) {
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    running += netMap[key] ?? 0;
    result.add(SnapshotPoint(
      date: d,
      netWorth: running,
      label: '${d.month}/${d.day}',
    ));
  }
  return result;
}

Future<List<SnapshotPoint>> _computeWeekRangeSnapshots(
  AppDatabase db, double currentNetWorth, DateTime start, DateTime end,
) async {
  // 简化为按月聚合
  return _computeMonthRangeSnapshots(db, currentNetWorth, start, end);
}

Future<List<SnapshotPoint>> _computeMonthRangeSnapshots(
  AppDatabase db, double currentNetWorth, DateTime start, DateTime end,
) async {
  final query = db.customSelect(
    '''SELECT CAST(strftime('%Y', r.occurred_at) AS INTEGER) as yr,
         CAST(strftime('%m', r.occurred_at) AS INTEGER) as mo,
         COALESCE(SUM(CASE WHEN r.type='income' THEN r.amount ELSE 0 END),0) -
         COALESCE(SUM(CASE WHEN r.type='expense' THEN r.amount ELSE 0 END),0) as net
       FROM records r
       WHERE r.occurred_at >= ? AND r.occurred_at < ?
       GROUP BY yr, mo ORDER BY yr ASC, mo ASC''',
    variables: [
      Variable.withString(start.toIso8601String()),
      Variable.withString(end.toIso8601String()),
    ],
    readsFrom: {db.records},
  );

  final rows = await query.get();
  final result = <SnapshotPoint>[];
  for (final row in rows) {
    final yr = row.read<int?>('yr');
    final mo = row.read<int?>('mo');
    if (yr == null || mo == null) continue; // 防御性跳过 null 值
    result.add(SnapshotPoint(
      date: DateTime(yr, mo, 1),
      netWorth: row.read<double>('net'),
      label: '$yr/${mo.toString().padLeft(2, '0')}',
    ));
  }
  return result;
}

/// 时间维度枚举（与 insights 保持一致）
enum TimeDimension { day, week, month, year, custom }

class AssetsData {
  final double totalAssets;
  final double totalLiabilities;
  final double netWorth;
  final Map<String, List<Account>> accountGroups;
  final List<Account> accounts;
  final List<SnapshotPoint> snapshots;

  const AssetsData({
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netWorth,
    required this.accountGroups,
    required this.accounts,
    this.snapshots = const [],
  });

  double groupTotal(String type, Map<String, List<Account>> groups) {
    double total = 0;
    for (final a in groups[type] ?? <Account>[]) {
      total += a.balance;
    }
    return total;
  }
}

/// 账户类型显示配置
class AccountTypeConfig {
  static const Map<String, TypeInfo> info = {
    'cash': TypeInfo('现金', Icons.money),
    'bank': TypeInfo('储蓄卡', Icons.account_balance),
    'credit': TypeInfo('信用卡', Icons.credit_card),
    'loan': TypeInfo('贷款', Icons.real_estate_agent),
    'invest': TypeInfo('投资', Icons.trending_up),
    'other': TypeInfo('其他', Icons.more_horiz),
  };

  static String label(String type) => info[type]?.label ?? type;
  static IconData icon(String type) => info[type]?.icon ?? Icons.more_horiz;
}

class TypeInfo {
  final String label;
  final IconData icon;
  const TypeInfo(this.label, this.icon);
}
