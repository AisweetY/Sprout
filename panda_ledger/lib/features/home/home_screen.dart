import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/accessibility_utils.dart';
import '../../core/widgets/record_card.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/repository/record_repository.dart';
import '../record/record_screen.dart';
import '../settings/budget_settings_screen.dart';
import 'history_screen.dart';
import 'home_provider.dart';

/// 首页 — 核心问题：「我现在的财务状态是什么」
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncData = ref.watch(homeDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('熊猫记账'),
        centerTitle: false,
      ),
      body: asyncData.when(
        loading: () => PageSkeletons.home(),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (data) => _buildContent(context, ref, data, theme),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, HomeData data, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        // Provider 自动响应数据变更，此处 invalidate 仅为支持下拉刷新手势动画
        ref.invalidate(homeDataProvider);
        await ref.read(homeDataProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── 净存款卡片 ──
          _NetSavingCard(data: data, theme: theme),
          const SizedBox(height: 16),

          // ── 储蓄目标进度条 ──
          _SavingGoalBar(data: data, theme: theme),
          const SizedBox(height: 16),

          // ── 净资产 ──
          _NetWorthRow(data: data, theme: theme),
          const SizedBox(height: 24),

          // ── 当月按天流水 ──
          _DailyRecordsSection(data: data, theme: theme),
        ],
      ),
    );
  }
}

class _NetSavingCard extends StatelessWidget {
  final HomeData data;
  final ThemeData theme;
  const _NetSavingCard({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isPositive = data.netSaving >= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本月净存款', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: data.netSaving.abs()),
              duration: AccessibilityUtils.motionDuration(context, const Duration(milliseconds: 600)),
              curve: Curves.easeOut,
              builder: (context, value, _) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      size: 28,
                      color: isPositive ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '¥ ${value.toStringAsFixed(2)}',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.5,
                        color: isPositive ? theme.colorScheme.primary : theme.colorScheme.error,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniLabel(
                  label: '收入 ¥${data.income.toStringAsFixed(0)}',
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                _MiniLabel(
                  label: '支出 ¥${data.expense.toStringAsFixed(0)}',
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

class _SavingGoalBar extends StatelessWidget {
  final HomeData data;
  final ThemeData theme;
  const _SavingGoalBar({required this.data, required this.theme});

  void _navigateToBudget(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BudgetSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (data.savingGoalAmount == 0) {
      return Card(
        child: InkWell(
          onTap: () => _navigateToBudget(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.savings_outlined, color: theme.colorScheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('设置月度储蓄目标', style: theme.textTheme.bodyMedium),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: InkWell(
        onTap: () => _navigateToBudget(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('储蓄目标', style: theme.textTheme.titleMedium),
                Text(
                  '¥ ${data.netSaving.toStringAsFixed(0)} / ¥ ${data.savingGoalAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: data.savingGoalProgress),
                duration: AccessibilityUtils.motionDuration(context, const Duration(milliseconds: 600)),
                curve: Curves.easeOut,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: data.savingGoalProgress >= 1
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primary.withAlpha(200),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.projectedSaving > 0
                  ? '按当前节奏预计本月存 ¥${data.projectedSaving.toStringAsFixed(0)}'
                  : '继续坚持记账！',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _NetWorthRow extends StatelessWidget {
  final HomeData data;
  final ThemeData theme;
  const _NetWorthRow({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              label: '净资产',
              value: '¥ ${data.netWorth.toStringAsFixed(0)}',
              theme: theme,
            ),
            Container(width: 1, height: 32, color: theme.colorScheme.outlineVariant),
            _StatItem(
              label: '${data.month}月净存',
              value: '¥ ${data.netSaving.toStringAsFixed(0)}',
              theme: theme,
              color: data.netSaving >= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final Color? color;
  const _StatItem({required this.label, required this.value, required this.theme, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            )),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 当月按天分组的流水列表
class _DailyRecordsSection extends ConsumerWidget {
  final HomeData data;
  final ThemeData theme;
  const _DailyRecordsSection({required this.data, required this.theme});

  void _editRecord(BuildContext context, WidgetRef ref, RecordItem item) async {
    final recordDao = ref.read(recordDaoProvider);
    final record = await recordDao.getById(item.id);
    if (record == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecordScreen(editRecord: record)),
    );
    // Provider 自动响应数据变更，无需手动刷新
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行："本月流水" + "查看全部"
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('本月流水', style: theme.textTheme.titleMedium),
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('查看全部', style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  )),
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (data.dailyGroups.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Text('记一笔，看看钱都花在哪', style: theme.textTheme.bodyMedium),
          )
        else
          ...data.dailyGroups.map((group) => _DayGroup(
                group: group,
                theme: theme,
                onTapItem: (item) => _editRecord(context, ref, item),
                onDeleteItem: (item) => _deleteRecordItem(context, ref, item),
              )),
      ],
    );
  }

  Future<void> _deleteRecordItem(BuildContext context, WidgetRef ref, RecordItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定要删除这笔 ¥${item.amount.toStringAsFixed(2)} 的记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final recordDao = ref.read(recordDaoProvider);
    final record = await recordDao.getById(item.id);
    if (record == null) return;

    await ref.read(recordRepositoryProvider).deleteRecord(record);
    // Provider 自动响应数据变更，无需手动刷新
  }

}

/// 单日分组
class _DayGroup extends StatelessWidget {
  final DailyRecordGroup group;
  final ThemeData theme;
  final void Function(RecordItem item) onTapItem;
  final void Function(RecordItem item) onDeleteItem;

  const _DayGroup({
    required this.group,
    required this.theme,
    required this.onTapItem,
    required this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    final weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdayNames[group.date.weekday - 1];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 日期标题行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        group.dateLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '周$weekday',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (group.dayIncome > 0)
                        Text(
                          '收 ¥${group.dayIncome.toStringAsFixed(0)} ',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      if (group.dayExpense > 0)
                        Text(
                          '支 ¥${group.dayExpense.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              const SizedBox(height: 4),
              // 当天每一笔 — 使用统一 RecordCard
              ...group.items.map((item) => RecordCard(
                    id: item.id,
                    type: item.type,
                    amount: item.amount,
                    categoryName: item.categoryName,
                    categoryIcon: item.categoryIcon,
                    accountName: item.accountName,
                    note: item.note,
                    syncStatus: item.syncStatus,
                    onTap: () => onTapItem(item),
                    onDelete: () => onDeleteItem(item),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
