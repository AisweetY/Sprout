import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/accessibility_utils.dart';
import '../../core/widgets/error_state_widget.dart';
import '../../core/widgets/shimmer_loading.dart';
import 'ai_summary_provider.dart';
import 'insights_provider.dart';

/// 分析页 — 核心问题：「钱具体是怎么花的、为什么」
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  TimeDimension _dimension = TimeDimension.month;
  DateTime _referenceDate = DateTime.now();
  DateTime? _customStart;
  DateTime? _customEnd;

  InsightsParams _buildParams() {
    switch (_dimension) {
      case TimeDimension.day:
        return InsightsParams.daily(_referenceDate);
      case TimeDimension.week:
        return InsightsParams.weekly(_referenceDate);
      case TimeDimension.month:
        return InsightsParams.monthly(_referenceDate.year, _referenceDate.month);
      case TimeDimension.year:
        return InsightsParams.yearly(_referenceDate.year);
      case TimeDimension.custom:
        if (_customStart != null && _customEnd != null) {
          return InsightsParams.custom(_customStart!, _customEnd!);
        }
        // 未选择范围时默认显示本月
        return InsightsParams.monthly(
          DateTime.now().year,
          DateTime.now().month,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = _buildParams();
    final asyncData = ref.watch(insightsDataProvider(params));

    return Scaffold(
      appBar: AppBar(title: const Text('分析')),
      body: Column(
        children: [
          // ── 时间维度选择器 ──
          _DimensionSelector(
            selected: _dimension,
            onChanged: (d) => setState(() {
              _dimension = d;
              if (d != TimeDimension.custom) {
                _customStart = null;
                _customEnd = null;
              }
            }),
          ),

          // ── 维度导航栏 ──
          _DimensionNavBar(
            dimension: _dimension,
            referenceDate: _referenceDate,
            customStart: _customStart,
            customEnd: _customEnd,
            onDateChanged: (date) => setState(() => _referenceDate = date),
            onCustomRangeChanged: (start, end) => setState(() {
              _customStart = start;
              _customEnd = end;
            }),
          ),

          // ── 内容区 ──
          Expanded(
            child: asyncData.when(
              loading: () => PageSkeletons.insights(),
              error: (e, _) => ErrorStateWidget(
                message: ErrorStateWidget.friendlyMessage(e),
                onRetry: () => ref.invalidate(insightsDataProvider(_buildParams())),
              ),
              data: (data) => _buildContent(context, data, theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, InsightsData data, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ── 自动文字结论（视觉权重最高，置顶）──
        _ConclusionCard(data: data, theme: theme),
        const SizedBox(height: 16),

        // ── 周期概览 ──
        _PeriodOverview(data: data, theme: theme),
        const SizedBox(height: 24),

        // ── 分类排行柱状图 ──
        Text('分类排行', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _CategoryBarChart(rankings: data.rankings, theme: theme),
        const SizedBox(height: 24),

        // ── 环比变化 ──
        if (data.prevExpense > 0 || data.prevIncome > 0) ...[
          Text(data.params.comparisonTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _PeriodComparison(data: data, theme: theme),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 时间维度选择器
// ═══════════════════════════════════════════════════════════════

class _DimensionSelector extends StatelessWidget {
  final TimeDimension selected;
  final ValueChanged<TimeDimension> onChanged;

  const _DimensionSelector({required this.selected, required this.onChanged});

  static const _items = [
    (TimeDimension.day, '日'),
    (TimeDimension.week, '周'),
    (TimeDimension.month, '月'),
    (TimeDimension.year, '年'),
    (TimeDimension.custom, '自定义'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: _items.map((item) {
          final isSelected = selected == item.$1;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: item.$1 == TimeDimension.day ? 0 : 4),
              child: SizedBox(
                height: 36,
                child: Material(
                  color: isSelected
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onChanged(item.$1),
                    child: Center(
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 维度导航栏
// ═══════════════════════════════════════════════════════════════

class _DimensionNavBar extends StatelessWidget {
  final TimeDimension dimension;
  final DateTime referenceDate;
  final DateTime? customStart;
  final DateTime? customEnd;
  final ValueChanged<DateTime> onDateChanged;
  final void Function(DateTime start, DateTime end) onCustomRangeChanged;

  const _DimensionNavBar({
    required this.dimension,
    required this.referenceDate,
    required this.customStart,
    required this.customEnd,
    required this.onDateChanged,
    required this.onCustomRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (dimension) {
      case TimeDimension.day:
        return _DayNav(
          date: referenceDate,
          onDateChanged: onDateChanged,
          theme: theme,
        );
      case TimeDimension.week:
        return _WeekNav(
          date: referenceDate,
          onDateChanged: onDateChanged,
          theme: theme,
        );
      case TimeDimension.month:
        return _MonthNav(
          date: referenceDate,
          onDateChanged: onDateChanged,
          theme: theme,
        );
      case TimeDimension.year:
        return _YearNav(
          date: referenceDate,
          onDateChanged: onDateChanged,
          theme: theme,
        );
      case TimeDimension.custom:
        return _CustomNav(
          start: customStart,
          end: customEnd,
          onRangeChanged: onCustomRangeChanged,
          theme: theme,
        );
    }
  }
}

/// 日导航：< 2026/06/20 >
class _DayNav extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final ThemeData theme;

  const _DayNav({
    required this.date,
    required this.onDateChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '前一天',
            onPressed: () => onDateChanged(date.subtract(const Duration(days: 1))),
          ),
          InkWell(
            onTap: () => _pickDate(context, date, onDateChanged),
            child: Text(
              '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '后一天',
            onPressed: () => onDateChanged(date.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }
}

/// 周导航：< 6/16 - 6/22 >
class _WeekNav extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final ThemeData theme;

  const _WeekNav({
    required this.date,
    required this.onDateChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final monday = InsightsParams.weekly(date).start;
    final sunday = monday.add(const Duration(days: 6));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一周',
            onPressed: () => onDateChanged(date.subtract(const Duration(days: 7))),
          ),
          InkWell(
            onTap: () => _pickDate(context, date, onDateChanged),
            child: Text(
              '${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一周',
            onPressed: () => onDateChanged(date.add(const Duration(days: 7))),
          ),
        ],
      ),
    );
  }
}

/// 月导航：< 2026年6月 >
class _MonthNav extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final ThemeData theme;

  const _MonthNav({
    required this.date,
    required this.onDateChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上个月',
            onPressed: () {
              if (date.month == 1) {
                onDateChanged(DateTime(date.year - 1, 12, 1));
              } else {
                onDateChanged(DateTime(date.year, date.month - 1, 1));
              }
            },
          ),
          Text(
            '${date.year}年${date.month}月',
            style: theme.textTheme.titleMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下个月',
            onPressed: () {
              if (date.month == 12) {
                onDateChanged(DateTime(date.year + 1, 1, 1));
              } else {
                onDateChanged(DateTime(date.year, date.month + 1, 1));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 年导航：< 2026年 >
class _YearNav extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final ThemeData theme;

  const _YearNav({
    required this.date,
    required this.onDateChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一年',
            onPressed: () => onDateChanged(DateTime(date.year - 1, 1, 1)),
          ),
          Text('${date.year}年', style: theme.textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一年',
            onPressed: () => onDateChanged(DateTime(date.year + 1, 1, 1)),
          ),
        ],
      ),
    );
  }
}

/// 自定义范围导航：开始日期 → 结束日期
class _CustomNav extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime start, DateTime end) onRangeChanged;
  final ThemeData theme;

  const _CustomNav({
    required this.start,
    required this.end,
    required this.onRangeChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: start ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onRangeChanged(picked, end ?? picked.add(const Duration(days: 7)));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                start != null
                    ? '${start!.year}/${start!.month.toString().padLeft(2, '0')}/${start!.day.toString().padLeft(2, '0')}'
                    : '开始日期',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('→', style: theme.textTheme.titleMedium),
          ),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: end ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onRangeChanged(start ?? picked.subtract(const Duration(days: 7)), picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                end != null
                    ? '${end!.year}/${end!.month.toString().padLeft(2, '0')}/${end!.day.toString().padLeft(2, '0')}'
                    : '结束日期',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹出日期选择器
Future<void> _pickDate(
  BuildContext context,
  DateTime initial,
  ValueChanged<DateTime> onChanged,
) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (picked != null) {
    onChanged(picked);
  }
}

// ═══════════════════════════════════════════════════════════════
// 内容卡片组件
// ═══════════════════════════════════════════════════════════════

/// AI 财务小结卡片（替代原模板结论）
///
/// 4 种状态：
/// - idle: 显示占位文案 + [✨ 生成小结] 按钮
/// - loading: 加载动画 + 提示文字（页面不阻塞）
/// - done: 展示小结正文 + [🔄 重新生成] 按钮
/// - error: 错误信息 + [🔄 重试] 按钮
class _ConclusionCard extends ConsumerWidget {
  final InsightsData data;
  final ThemeData theme;
  const _ConclusionCard({required this.data, required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiState = ref.watch(aiSummaryProvider);
    final notifier = ref.read(aiSummaryProvider.notifier);

    // 确保已为当前参数准备状态（幂等，切换维度时自动查缓存或回 idle）
    notifier.ensurePrepared(data.params);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 标题行 ──
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(data.params.summaryTitle, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // ── 内容区（按状态分支）──
            switch (aiState.status) {
              AiSummaryStatus.idle => _buildIdle(context, ref, data),
              AiSummaryStatus.loading => _buildLoading(context),
              AiSummaryStatus.done => _buildDone(context, ref, data, aiState.text!),
              AiSummaryStatus.error => _buildError(context, ref, data, aiState.errorMsg ?? '未知错误'),
            },
          ],
        ),
      ),
    );
  }

  /// 无小结状态
  Widget _buildIdle(BuildContext context, WidgetRef ref, InsightsData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI 分析你的收支数据，生成本周期的财务小结，洞察消费趋势和财务健康度。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('生成小结'),
            onPressed: () => _onGenerate(ref, data),
          ),
        ),
      ],
    );
  }

  /// 生成中状态
  Widget _buildLoading(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'AI 正在分析你的财务数据…',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '生成中可继续浏览页面，完成后自动展示',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  /// 已生成状态
  Widget _buildDone(
    BuildContext context,
    WidgetRef ref,
    InsightsData data,
    String summary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary, style: theme.textTheme.bodyLarge?.copyWith(height: 1.7)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重新生成'),
            onPressed: () => _onRegenerate(ref, data),
          ),
        ),
      ],
    );
  }

  /// 失败状态
  Widget _buildError(
    BuildContext context,
    WidgetRef ref,
    InsightsData data,
    String errorMsg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                errorMsg,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
            onPressed: () => _onGenerate(ref, data),
          ),
        ),
      ],
    );
  }

  /// 点击「生成小结」→ 准备数据 → 调 Edge Function
  void _onGenerate(WidgetRef ref, InsightsData data) {
    _triggerGenerate(ref, data, force: false);
  }

  /// 点击「重新生成」→ 忽略缓存强制调用
  void _onRegenerate(WidgetRef ref, InsightsData data) {
    _triggerGenerate(ref, data, force: true);
  }

  void _triggerGenerate(WidgetRef ref, InsightsData data, {required bool force}) {
    final notifier = ref.read(aiSummaryProvider.notifier);
    final inputFuture = prepareAiSummaryInput(ref, data.params, data);

    inputFuture.then((input) {
      if (force) {
        notifier.regenerateSummary(params: data.params, input: input);
      } else {
        notifier.generateSummary(params: data.params, input: input);
      }
    }).catchError((e) {
      debugPrint('⚠️ 准备 AI 小结数据失败: $e');
    });
  }
}

/// 周期概览（收入/支出/储蓄率）
class _PeriodOverview extends StatelessWidget {
  final InsightsData data;
  final ThemeData theme;
  const _PeriodOverview({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _OverviewItem(
              label: '收入',
              value: '¥ ${data.income.toStringAsFixed(0)}',
              icon: Icons.arrow_downward,
              color: theme.colorScheme.primary,
            ),
            _OverviewItem(
              label: '支出',
              value: '¥ ${data.expense.toStringAsFixed(0)}',
              icon: Icons.arrow_upward,
              color: theme.colorScheme.error,
            ),
            _OverviewItem(
              label: '储蓄率',
              value: '${data.savingsRate.toStringAsFixed(0)}%',
              icon: Icons.savings,
              color: data.savingsRate >= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _OverviewItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 分类排行横向柱状图
class _CategoryBarChart extends StatelessWidget {
  final List<dynamic> rankings;
  final ThemeData theme;
  const _CategoryBarChart({required this.rankings, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (rankings.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text('记账数据将在这里生成图表', style: theme.textTheme.bodySmall),
      );
    }

    final maxAmount = rankings.first.amount;
    final catColors = AppColors.categoryColors;

    return Column(
      children: rankings.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final ratio = maxAmount > 0 ? item.amount / maxAmount : 0.0;
        final color = catColors[idx % catColors.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(item.name,
                    style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio),
                    duration: AccessibilityUtils.motionDuration(
                        context, const Duration(milliseconds: 600)),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 16,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: color.withAlpha(20),
                        color: color,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Text(
                  '¥ ${item.amount.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 周期对比
class _PeriodComparison extends StatelessWidget {
  final InsightsData data;
  final ThemeData theme;
  const _PeriodComparison({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    final expenseDiff = data.expense - data.prevExpense;
    final incomeDiff = data.income - data.prevIncome;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _CompareRow(
              label: '支出',
              current: '¥ ${data.expense.toStringAsFixed(0)}',
              prev: '¥ ${data.prevExpense.toStringAsFixed(0)}',
              diff: expenseDiff,
            ),
            const SizedBox(height: 8),
            _CompareRow(
              label: '收入',
              current: '¥ ${data.income.toStringAsFixed(0)}',
              prev: '¥ ${data.prevIncome.toStringAsFixed(0)}',
              diff: incomeDiff,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String current;
  final String prev;
  final double diff;

  const _CompareRow({
    required this.label,
    required this.current,
    required this.prev,
    required this.diff,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncrease = diff > 0;
    final diffText =
        isIncrease ? '+¥${diff.toStringAsFixed(0)}' : '-¥${(-diff).toStringAsFixed(0)}';

    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: theme.textTheme.bodyMedium)),
        Expanded(
            child: Text(current,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500))),
        Text(prev, style: theme.textTheme.bodySmall),
        const SizedBox(width: 8),
        Text(diffText,
            style: TextStyle(
              fontSize: 13,
              color: isIncrease ? theme.colorScheme.error : theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            )),
      ],
    );
  }
}
