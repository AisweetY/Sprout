import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/accessibility_utils.dart';
import '../../core/utils/snackbar_utils.dart';
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
    final accentColor = isPositive ? theme.colorScheme.primary : theme.colorScheme.error;

    // B2: 品牌签名卡片 — 竹青微渐变背景，区分于普通白卡片
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor.withAlpha(14),
              Colors.transparent,
            ],
          ),
        ),
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
                  // B1: ¥ 符号缩小 + 数字 w300 letterSpacing -1.5，轻盈感
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Icon(
                        isPositive ? Icons.trending_up : Icons.trending_down,
                        size: 24,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '¥ ',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w300,
                                color: accentColor,
                                letterSpacing: 0,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            TextSpan(
                              text: value.toStringAsFixed(2),
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.w300,
                                letterSpacing: -1.5,
                                color: accentColor,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
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

  /// 删除流水 — Undo 模式：直接删除 + SnackBar 撤销，无弹窗确认。
  /// 返回 true 表示卡片确认滑走，false 表示操作失败卡片弹回。
  Future<bool> _deleteRecordItem(BuildContext context, WidgetRef ref, RecordItem item) async {
    final recordDao = ref.read(recordDaoProvider);
    final record = await recordDao.getById(item.id);
    if (record == null) return false;

    try {
      await ref.read(recordRepositoryProvider).deleteRecord(record);
    } catch (e) {
      if (context.mounted) {
        SnackbarUtils.showError(context: context, message: '删除失败: $e');
      }
      return false;
    }

    if (!context.mounted) return true;

    // 显示带撤销按钮的 SnackBar（5 秒）
    SnackbarUtils.showUndo(
      context: context,
      message: '已删除 ¥${item.amount.toStringAsFixed(2)}',
      duration: const Duration(seconds: 5),
      onUndo: () async {
        try {
          await ref.read(recordRepositoryProvider).restoreRecord(record);
        } catch (e) {
          if (context.mounted) {
            SnackbarUtils.showError(context: context, message: '撤销失败: $e');
          }
        }
      },
    );

    return true; // 卡片滑走
  }

}

/// 单日分组
class _DayGroup extends StatelessWidget {
  final DailyRecordGroup group;
  final ThemeData theme;
  final void Function(RecordItem item) onTapItem;
  final Future<bool> Function(RecordItem item) onDeleteItem;

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

    // C3：去掉外层 Card 包裹（原 Card-in-Card 双重嵌套），
    // 日期标题改为轻量 label 行，RecordCards 直接呈列，呼吸感更好。
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期标题行 — 极简 label 风格，不再套 Card
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      group.dateLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '周$weekday',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                // 当日收支小计
                Row(
                  children: [
                    if (group.dayIncome > 0)
                      Text(
                        '收 ¥${group.dayIncome.toStringAsFixed(0)} ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    if (group.dayExpense > 0)
                      Text(
                        '支 ¥${group.dayExpense.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 当天流水卡片 — 直接排列，不再被外层 Card 包裹
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
    );
  }
}
