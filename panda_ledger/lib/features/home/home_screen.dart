import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/accessibility_utils.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../settings/budget_settings_screen.dart';
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

          // ── 钱去哪了 Top5 ──
          _TopSpendingSection(data: data, theme: theme),
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

class _TopSpendingSection extends StatelessWidget {
  final HomeData data;
  final ThemeData theme;
  const _TopSpendingSection({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('钱去哪了', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (data.topSpending.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Text('记一笔，看看钱都花在哪', style: theme.textTheme.bodyMedium),
          )
        else
          ...data.topSpending.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final maxAmount = data.topSpending.first.amount;
            final ratio = maxAmount > 0 ? item.amount / maxAmount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // 排名序号
                  SizedBox(
                    width: 24,
                    child: Text('${idx + 1}', style: TextStyle(
                      fontSize: 14,
                      fontWeight: idx < 3 ? FontWeight.w600 : FontWeight.w400,
                      color: idx < 3 ? theme.colorScheme.primary : theme.colorScheme.outline,
                    )),
                  ),
                  // 分类名
                  SizedBox(width: 56, child: Text(item.name, style: theme.textTheme.bodyMedium)),
                  const SizedBox(width: 8),
                  // 条形图
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: ratio),
                        duration: AccessibilityUtils.motionDuration(context, const Duration(milliseconds: 500)),
                        curve: Curves.easeOut,
                        builder: (context, value, _) {
                          return LinearProgressIndicator(
                            value: value,
                            minHeight: 12,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            color: _categoryColor(idx),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 金额
                  SizedBox(
                    width: 72,
                    child: Text(
                      '¥ ${item.amount.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Color _categoryColor(int index) {
    return AppColors.categoryColors[index % AppColors.categoryColors.length];
  }
}
