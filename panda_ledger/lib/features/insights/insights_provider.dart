import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/time_dimension.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/account_repository.dart';

/// 订阅指定时间范围内涉及的所有月份的流水变更
void _watchRelevantMonths(Ref ref, DateTime start, DateTime end) {
  // 遍历 start 到 end 之间的所有不重复月份
  final months = <({int year, int month})>{};
  var d = DateTime(start.year, start.month, 1);
  final last = DateTime(end.year, end.month, 1);
  while (!d.isAfter(last)) {
    months.add((year: d.year, month: d.month));
    d = DateTime(d.year, d.month + 1, 1);
  }
  for (final m in months) {
    ref.watch(monthlyRecordsStreamProvider((year: m.year, month: m.month)));
  }
}

/// 分析页时间参数
class InsightsParams {
  final TimeDimension dimension;
  final DateTime start; // 当前周期开始（含）
  final DateTime end; // 当前周期结束（不含）
  final int? year; // 保留，用于月维度便捷构造
  final int? month; // 保留，用于月维度便捷构造

  const InsightsParams({
    required this.dimension,
    required this.start,
    required this.end,
    this.year,
    this.month,
  });

  /// 月维度（向后兼容）
  factory InsightsParams.monthly(int year, int month) => InsightsParams(
        dimension: TimeDimension.month,
        start: DateTime(year, month, 1),
        end: DateTime(year, month + 1, 1),
        year: year,
        month: month,
      );

  /// 日维度
  factory InsightsParams.daily(DateTime date) => InsightsParams(
        dimension: TimeDimension.day,
        start: DateTime(date.year, date.month, date.day),
        end: DateTime(date.year, date.month, date.day + 1),
      );

  /// 周维度（周一起始）
  factory InsightsParams.weekly(DateTime anyDayInWeek) {
    final monday = _mondayOf(anyDayInWeek);
    return InsightsParams(
      dimension: TimeDimension.week,
      start: monday,
      end: monday.add(const Duration(days: 7)),
    );
  }

  /// 年维度
  factory InsightsParams.yearly(int year) => InsightsParams(
        dimension: TimeDimension.year,
        start: DateTime(year, 1, 1),
        end: DateTime(year + 1, 1, 1),
      );

  /// 自定义范围
  factory InsightsParams.custom(DateTime start, DateTime end) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day + 1);
    return InsightsParams(
      dimension: TimeDimension.custom,
      start: normalizedStart,
      end: normalizedEnd,
    );
  }

  /// 获取上一周期的参数（用于环比）
  InsightsParams get previousPeriod {
    final duration = end.difference(start);
    switch (dimension) {
      case TimeDimension.day:
        return InsightsParams.daily(start.subtract(const Duration(days: 1)));
      case TimeDimension.week:
        return InsightsParams.weekly(start.subtract(const Duration(days: 7)));
      case TimeDimension.month:
        final prevMonth = start.month == 1 ? 12 : start.month - 1;
        final prevYear = start.month == 1 ? start.year - 1 : start.year;
        return InsightsParams.monthly(prevYear, prevMonth);
      case TimeDimension.year:
        return InsightsParams.yearly(start.year - 1);
      case TimeDimension.custom:
        final prevEnd = start;
        final prevStart = prevEnd.subtract(duration);
        return InsightsParams.custom(prevStart, prevEnd);
    }
  }

  /// 时间段标签（用于 UI 显示）
  String get periodLabel {
    switch (dimension) {
      case TimeDimension.day:
        return '${start.month}月${start.day}日';
      case TimeDimension.week:
        final endDay = end.subtract(const Duration(days: 1));
        return '${start.month}/${start.day} - ${endDay.month}/${endDay.day}';
      case TimeDimension.month:
        return '${start.year}年${start.month}月';
      case TimeDimension.year:
        return '${start.year}年';
      case TimeDimension.custom:
        final endDay = end.subtract(const Duration(days: 1));
        return '${start.month}/${start.day} - ${endDay.month}/${endDay.day}';
    }
  }

  /// 比较期简洁标签（用于结论中 "比XX" 句式）
  String get comparisonLabel {
    switch (dimension) {
      case TimeDimension.day:
        return '昨天';
      case TimeDimension.week:
        return '上周';
      case TimeDimension.month:
        return '上月';
      case TimeDimension.year:
        return '去年';
      case TimeDimension.custom:
        return '上期';
    }
  }

  /// 比较期完整标题（用于环比区域标题）
  String get comparisonTitle {
    switch (dimension) {
      case TimeDimension.day:
        return '对比昨天';
      case TimeDimension.week:
        return '环比上周';
      case TimeDimension.month:
        return '环比上月';
      case TimeDimension.year:
        return '环比去年';
      case TimeDimension.custom:
        return '对比上期';
    }
  }

  /// 小结标题（用于结论卡片）
  String get summaryTitle {
    switch (dimension) {
      case TimeDimension.day:
        return '本日小结';
      case TimeDimension.week:
        return '本周小结';
      case TimeDimension.month:
        return '本月小结';
      case TimeDimension.year:
        return '本年小结';
      case TimeDimension.custom:
        return '时段小结';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is InsightsParams &&
      other.dimension == dimension &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(dimension, start, end);

  static DateTime _mondayOf(DateTime date) {
    final weekday = date.weekday; // 1=Monday, 7=Sunday
    return DateTime(date.year, date.month, date.day - (weekday - 1));
  }
}

/// 分析页数据
class InsightsData {
  final double income;
  final double expense;
  final double netSaving;
  final double prevIncome;
  final double prevExpense;
  final double savingsRate;
  final List<RankingItem> rankings;
  final String conclusion;
  final InsightsParams params;

  const InsightsData({
    required this.income,
    required this.expense,
    required this.netSaving,
    required this.prevIncome,
    required this.prevExpense,
    required this.savingsRate,
    required this.rankings,
    required this.conclusion,
    required this.params,
  });
}

class RankingItem {
  final String name;
  final double amount;

  const RankingItem({required this.name, required this.amount});
}

/// AI 小结的聚合输入（所有数据由 App 端预计算，不传原始流水给 AI）
class AiSummaryInput {
  final String dimensionName;
  final String periodLabel;
  final String currentDate;
  final double income;
  final double expense;
  final double netSaving;
  final double savingsRate;
  final double prevIncome;
  final double prevExpense;
  final List<TopCategoryDetail> topCategories;
  final List<LargeExpenseItem> largeExpenses;
  final String? highFrequencyCategory;
  final AssetRatioData? assets;
  final double? historicalAvgExpense;
  final String? budgetStatus;

  /// 建议锚点：App 端精确计算的数字，AI 写 advice 只能用这些
  final AdviceHints adviceHints;

  const AiSummaryInput({
    required this.dimensionName,
    required this.periodLabel,
    required this.currentDate,
    required this.income,
    required this.expense,
    required this.netSaving,
    required this.savingsRate,
    required this.prevIncome,
    required this.prevExpense,
    required this.topCategories,
    required this.largeExpenses,
    this.highFrequencyCategory,
    this.assets,
    this.historicalAvgExpense,
    this.budgetStatus,
    required this.adviceHints,
  });

  Map<String, dynamic> toJson() => {
        'dimension_name': dimensionName,
        'period_label': periodLabel,
        'current_date': currentDate,
        'income': income,
        'expense': expense,
        'net_saving': netSaving,
        'savings_rate': savingsRate,
        'prev_income': prevIncome,
        'prev_expense': prevExpense,
        'top_categories': topCategories.map((c) => c.toJson()).toList(),
        'large_expenses': largeExpenses.map((e) => e.toJson()).toList(),
        'high_frequency_category': highFrequencyCategory,
        'assets': assets?.toJson(),
        'historical_avg_expense': historicalAvgExpense,
        'budget_status': budgetStatus,
        'advice_hints': adviceHints.toJson(),
      };
}

class TopCategoryDetail {
  final String name;
  final double amount;
  final double ratio;
  final double prevAmount;
  const TopCategoryDetail({
    required this.name,
    required this.amount,
    required this.ratio,
    required this.prevAmount,
  });
  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'ratio': ratio,
        'prev_amount': prevAmount,
      };
}

class LargeExpenseItem {
  final String description;
  final double amount;
  final String category;
  const LargeExpenseItem({
    required this.description,
    required this.amount,
    required this.category,
  });
  Map<String, dynamic> toJson() => {
        'description': description,
        'amount': amount,
        'category': category,
      };
}

class AssetRatioData {
  final double cashRatio;
  final double investRatio;
  const AssetRatioData({required this.cashRatio, required this.investRatio});
  Map<String, dynamic> toJson() => {
        'cash_ratio': cashRatio,
        'invest_ratio': investRatio,
      };
}

/// 建议锚点 — App 端精确计算，AI 只能用这些数字写 advice，不得编造
class AdviceHints {
  /// 目标达成情况描述（Flutter 端算好，AI 直接引用）
  ///
  /// 样例：
  /// - "已超额完成，存了 ¥2,300"
  /// - "当前完成 72%，按节奏预计最终完成约 85%，本月难达标"
  /// - "当前完成 72%，按节奏能达标"
  /// - "周期已结束，完成 68%，差 ¥640"
  /// - null → 无储蓄目标
  final String? goalStatus;

  /// 本期环比增幅最大的支出分类名（两期都有数据才算）
  final String? topGainCategory;

  /// 该分类比上期多花了多少（绝对值）
  final double? topGainAmount;

  /// 当前周期剩余天数（0 = 周期已结束，建议面向下期）
  final int daysRemainingInPeriod;

  const AdviceHints({
    this.goalStatus,
    this.topGainCategory,
    this.topGainAmount,
    required this.daysRemainingInPeriod,
  });

  Map<String, dynamic> toJson() => {
        'goal_status': goalStatus,
        'top_gain_category': topGainCategory,
        'top_gain_amount': topGainAmount,
        'days_remaining': daysRemainingInPeriod,
      };
}

/// 分析页数据 Provider — 响应式自动更新
///
/// 依赖 categoriesStreamProvider / monthlyRecordsStreamProvider，
/// 当分类或流水变更时自动重算。
final insightsDataProvider =
    FutureProvider.family<InsightsData, InsightsParams>((ref, params) async {
  try {
    final db = ref.watch(appDatabaseProvider);
    final recordDao = ref.watch(recordDaoProvider);

    // ═══ 订阅底层数据流 → 数据变更时自动失效重算 ═══
    ref.watch(categoriesStreamProvider);
    // 订阅当前周期和上一周期涉及月份的流水
    _watchRelevantMonths(ref, params.start, params.end);
    final prevParams = params.previousPeriod;
    _watchRelevantMonths(ref, prevParams.start, prevParams.end);

    // 当期汇总（默认值 .0 保证非 null）
    final summary = await recordDao.getSummary(params.start, params.end);
    final income = summary['income'] ?? 0.0;
    final expense = summary['expense'] ?? 0.0;

    // 上期汇总（用于环比，prevParams 已在上面声明）
    final prevSummary = await recordDao.getSummary(prevParams.start, prevParams.end);
    final prevIncome = prevSummary['income'] ?? 0.0;
    final prevExpense = prevSummary['expense'] ?? 0.0;

    // 分类排行
    final rankings = await _getCategoryRankings(db, params.start, params.end);

    // 生成文字结论
    final conclusion = _generateConclusion(
      expense, income, prevExpense, prevIncome, rankings, params,
    );

    // 净结余
    final netSaving = income - expense;

    // 储蓄率（安全计算，避免除零）
    final savingsRate = income > 0 ? ((income - expense) / income * 100) : 0.0;

    return InsightsData(
      income: income,
      expense: expense,
      netSaving: netSaving,
      prevIncome: prevIncome,
      prevExpense: prevExpense,
      savingsRate: savingsRate,
      rankings: rankings,
      conclusion: conclusion,
      params: params,
    );
  } catch (e, stack) {
    // 打印详细错误信息以便调试
    debugPrint('❌ 分析页数据加载失败: $e\n$stack');
    rethrow;
  }
});

Future<List<RankingItem>> _getCategoryRankings(
  AppDatabase db,
  DateTime start,
  DateTime end,
) async {
  // 按一级分类汇总：二级分类的金额通过 COALESCE 汇总到其父级
  //
  // 修复：
  // 1. 用 INNER JOIN 代替 LEFT JOIN，同时过滤 c.deleted=0，
  //    确保软删除的分类不进入排行（否则删除后重建同名分类会出现重复行）
  // 2. WHERE 增加 r.deleted=0，排除已软删除的流水记录
  // 3. LEFT JOIN parent 仍保留（记录可能直接挂父级分类），
  //    同时过滤 parent.deleted=0 避免已删父级影响分组名
  final query = db.customSelect(
    '''SELECT COALESCE(parent.name, c.name) as name,
              SUM(r.amount) as total
       FROM records r
       JOIN categories c ON r.category_id = c.id AND c.deleted = 0
       LEFT JOIN categories parent ON c.parent_id = parent.id AND parent.deleted = 0
       WHERE r.occurred_at >= ? AND r.occurred_at < ?
         AND r.type = 'expense'
         AND r.deleted = 0
       GROUP BY COALESCE(parent.id, c.id), COALESCE(parent.name, c.name)
       ORDER BY total DESC''',
    variables: [
      Variable.withDateTime(start),
      Variable.withDateTime(end),
    ],
    readsFrom: {db.records, db.categories},
  );

  final rows = await query.get();
  return rows
      .map((row) => RankingItem(
            name: row.read<String>('name'),
            amount: row.read<double>('total'),
          ))
      .toList();
}

String _generateConclusion(
  double expense,
  double income,
  double prevExpense,
  double prevIncome,
  List<RankingItem> rankings,
  InsightsParams params,
) {
  final buf = StringBuffer();
  final diff = expense - prevExpense;
  final saving = income - expense;
  final label = params.periodLabel;

  if (expense == 0 && income == 0) {
    return '$label暂无记账记录，开始记一笔吧！';
  }

  buf.write(label);

  // 支出对比
  final compLabel = params.comparisonLabel;
  if (prevExpense > 0) {
    if (diff > 0) {
      buf.write('总支出 ¥${expense.toStringAsFixed(0)}，比$compLabel多花了 ¥${diff.toStringAsFixed(0)}');
    } else {
      buf.write('总支出 ¥${expense.toStringAsFixed(0)}，比$compLabel少花了 ¥${(-diff).toStringAsFixed(0)}');
    }
  } else {
    buf.write('总支出 ¥${expense.toStringAsFixed(0)}');
  }

  // 储蓄情况
  if (income > 0) {
    final rate = ((saving / income) * 100).toStringAsFixed(0);
    buf.write('，储蓄率 $rate%。');
  } else {
    buf.write('。');
  }

  // 最大支出分类
  if (rankings.isNotEmpty) {
    final top = rankings.first;
    buf.write('最大支出是「${top.name}」（¥${top.amount.toStringAsFixed(0)}）');

    if (rankings.length >= 2) {
      final second = rankings[1];
      buf.write('，其次是「${second.name}」（¥${second.amount.toStringAsFixed(0)}）');
    }
    buf.write('。');
  }

  // 追加建议
  if (saving < 0 && income > 0) {
    buf.write('本期入不敷出，建议关注支出较大的分类。');
  } else if (diff > 0 && prevExpense > 0) {
    buf.write('支出较上期增长，可以检查是否有可优化的消费。');
  }

  return buf.toString();
}

// ═══════════════════════════════════════════════════════════════
// AI 小结数据聚合（懒调用 — 仅在用户点击「生成」时触发）
// ═══════════════════════════════════════════════════════════════

/// 准备 AI 小结所需的聚合数据
///
/// 所有计算在 App 端完成，不传原始流水给 AI。
/// 需传入 [ref] 以访问各 DAO/Repo Provider。
Future<AiSummaryInput> prepareAiSummaryInput(
  WidgetRef ref,
  InsightsParams params,
  InsightsData data,
) async {
  final db = ref.read(appDatabaseProvider);
  final recordDao = ref.read(recordDaoProvider);
  final accountRepo = ref.read(accountRepositoryProvider);
  final budgetDao = ref.read(budgetDaoProvider);
  final categoryDao = ref.read(categoryDaoProvider);

  // ── 1. TOP 3 分类（含上期对比）──
  final prevParams = params.previousPeriod;
  final prevRankings = await _getCategoryRankings(db, prevParams.start, prevParams.end);
  final prevMap = <String, double>{};
  for (final r in prevRankings) {
    prevMap[r.name] = r.amount;
  }

  final topCategories = data.rankings.take(3).map((r) {
    final ratio = data.expense > 0 ? (r.amount / data.expense * 100) : 0.0;
    return TopCategoryDetail(
      name: r.name,
      amount: r.amount,
      ratio: ratio,
      prevAmount: prevMap[r.name] ?? 0.0,
    );
  }).toList();

  // ── 2. 大额消费 ──
  final records = await recordDao.getRecordsInRange(params.start, params.end);
  final largeThreshold = 500.0;
  final largeExpenses = records
      .where((r) => r.type == 'expense' && r.amount >= largeThreshold)
      .map((r) => LargeExpenseItem(
            description: r.note ?? '消费',
            amount: r.amount,
            category: '消费', // 后续可关联 category 名称
          ))
      .toList();

  // ── 3. 高频消费分类 ──
  final expenseRecords = records.where((r) => r.type == 'expense').toList();
  final categoryCount = <String?, int>{};
  for (final r in expenseRecords) {
    categoryCount[r.categoryId] = (categoryCount[r.categoryId] ?? 0) + 1;
  }
  String? highFreqCatId;
  int maxCount = 0;
  for (final entry in categoryCount.entries) {
    if (entry.value > maxCount) {
      maxCount = entry.value;
      highFreqCatId = entry.key;
    }
  }
  // categoryId 是 UUID，AI 无法理解 → 查出人类可读的分类名称
  String? highFreqCatName;
  if (highFreqCatId != null) {
    final cat = await categoryDao.getById(highFreqCatId);
    highFreqCatName = cat?.name;
  }

  // ── 4. 历史月均支出（过去 6 个月）──
  double? historicalAvgExpense;
  final now = DateTime.now();
  final pastMonths = <DateTime>[];
  for (var i = 1; i <= 6; i++) {
    var y = now.year;
    var m = now.month - i;
    if (m <= 0) {
      m += 12;
      y -= 1;
    }
    pastMonths.add(DateTime(y, m, 1));
  }

  double totalHistExpense = 0;
  int histMonthCount = 0;
  for (final month in pastMonths) {
    final endDate = DateTime(month.year, month.month + 1, 1);
    // 跳过当前周期的月份（避免循环引用）
    final summary = await recordDao.getSummary(month, endDate);
    final exp = summary['expense'] ?? 0;
    if (exp > 0) {
      totalHistExpense += exp;
      histMonthCount++;
    }
  }
  if (histMonthCount > 0) {
    historicalAvgExpense = totalHistExpense / histMonthCount;
  }

  // ── 5. 资产占比 ──
  AssetRatioData? assets;
  final accounts = await accountRepo.getActiveAccounts();
  if (accounts.isNotEmpty) {
    double totalBalance = 0;
    double cashBalance = 0;
    double investBalance = 0;
    for (final a in accounts) {
      final absBalance = a.balance.abs();
      totalBalance += absBalance;
      if (a.type == 'cash' || a.type == 'bank' || a.type == 'credit') {
        cashBalance += absBalance;
      } else if (a.type == 'invest') {
        investBalance += absBalance;
      }
    }
    if (totalBalance > 0) {
      assets = AssetRatioData(
        cashRatio: (cashBalance / totalBalance * 100).roundToDouble(),
        investRatio: (investBalance / totalBalance * 100).roundToDouble(),
      );
    }
  }

  // ── 6. 预算状态 ──
  String? budgetStatus;

  final monthStr = '${params.start.year}-${params.start.month.toString().padLeft(2, '0')}';
  final savingGoal = await budgetDao.getMonthlySavingGoal(monthStr);
  if (savingGoal != null && savingGoal.targetAmount > 0) {
    final progress = (data.netSaving / savingGoal.targetAmount * 100).clamp(0.0, 100.0);
    budgetStatus = '月度储蓄目标 ¥${savingGoal.targetAmount.toStringAsFixed(0)}，当前达成 ${progress.toStringAsFixed(0)}%';
  }

  // ── 7. 当前周期剩余天数 ──
  // .inDays 向下截断，周期最后一天（<24h 剩余）会返回 0，导致误判"周期已结束"。
  // 改用 ceiling 除法：只要还有 ≥1 秒剩余，就算 1 天。
  final nowForHints = DateTime.now();
  final daysRemaining = params.end.isAfter(nowForHints)
      ? (params.end.difference(nowForHints).inHours + 23) ~/ 24
      : 0;

  // ── 8. 目标达成情况预估（Flutter 端算好，AI 直接引用，不需要 AI 自己估算）──
  String? goalStatus;
  if (savingGoal != null && savingGoal.targetAmount > 0) {
    final goal = savingGoal.targetAmount;
    final saved = data.netSaving;
    final pct = (saved / goal * 100).clamp(0.0, 100.0);

    if (saved >= goal) {
      // 已超额
      goalStatus = '已超额完成，存了 ¥${saved.toStringAsFixed(0)}（目标 ¥${goal.toStringAsFixed(0)}）';
    } else if (daysRemaining == 0) {
      // 周期已结束，算最终结果
      goalStatus = '周期已结束，完成 ${pct.toStringAsFixed(0)}%，差 ¥${(goal - saved).toStringAsFixed(0)} 未达标';
    } else {
      // 按当前日均净存入预测最终结果
      final totalDays = params.end.difference(params.start).inDays;
      final daysElapsed = (totalDays - daysRemaining).clamp(1, totalDays);
      final dailyNetSaving = saved / daysElapsed;
      final projected = saved + dailyNetSaving * daysRemaining;
      final projectedPct = (projected / goal * 100).clamp(0.0, 100.0);

      if (projected >= goal) {
        goalStatus = '当前完成 ${pct.toStringAsFixed(0)}%，按当前节奏能达标';
      } else {
        goalStatus = '当前完成 ${pct.toStringAsFixed(0)}%，按当前节奏预计完成约 ${projectedPct.toStringAsFixed(0)}%，本月难达标';
      }
    }
  }

  // ── 9. 建议锚点：环比增幅最大的支出分类 ──
  // 只统计上期也有数据的分类（防止新分类被误判为"超支"）
  String? topGainCategory;
  double topGainAmount = 0;
  for (final r in data.rankings) {
    final prevAmount = prevMap[r.name] ?? 0.0;
    if (prevAmount > 0) {
      final gain = r.amount - prevAmount;
      if (gain > topGainAmount) {
        topGainAmount = gain;
        topGainCategory = r.name;
      }
    }
  }

  final adviceHints = AdviceHints(
    goalStatus: goalStatus,
    topGainCategory: topGainCategory,
    topGainAmount: topGainAmount > 0 ? topGainAmount : null,
    daysRemainingInPeriod: daysRemaining,
  );

  return AiSummaryInput(
    dimensionName: params.summaryTitle,
    periodLabel: params.periodLabel,
    currentDate: DateTime.now().toIso8601String().substring(0, 10),
    income: data.income,
    expense: data.expense,
    netSaving: data.netSaving,
    savingsRate: data.savingsRate,
    prevIncome: data.prevIncome,
    prevExpense: data.prevExpense,
    topCategories: topCategories,
    largeExpenses: largeExpenses,
    highFrequencyCategory: highFreqCatName,
    assets: assets,
    historicalAvgExpense: historicalAvgExpense,
    budgetStatus: budgetStatus,
    adviceHints: adviceHints,
  );
}
