import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/accessibility_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/widgets/error_state_widget.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_queue_dao_provider.dart';
import '../auth/auth_provider.dart';
import 'budget_settings_provider.dart';

/// 预算设置页 — 月度储蓄目标 + 分类预算上限 + 超支提示
class BudgetSettingsScreen extends ConsumerStatefulWidget {
  const BudgetSettingsScreen({super.key});

  @override
  ConsumerState<BudgetSettingsScreen> createState() =>
      _BudgetSettingsScreenState();
}

class _BudgetSettingsScreenState extends ConsumerState<BudgetSettingsScreen> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncData = ref.watch(
      categoryBudgetDataProvider(BudgetParams(year: _year, month: _month)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('预算设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _changeMonth(-1),
          ),
          Text('$_year年$_month月', style: theme.textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
      body: asyncData.when(
        loading: () => PageSkeletons.list(itemCount: 4),
        error: (e, _) => ErrorStateWidget(
          message: ErrorStateWidget.friendlyMessage(e),
          onRetry: () => ref.invalidate(
            categoryBudgetDataProvider(BudgetParams(year: _year, month: _month)),
          ),
        ),
        data: (data) => _buildContent(context, data, theme),
      ),
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _month += delta;
      if (_month > 12) {
        _month = 1;
        _year++;
      } else if (_month < 1) {
        _month = 12;
        _year--;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 主体内容
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent(
      BuildContext context, CategoryBudgetData data, ThemeData theme) {
    if (!data.hasAnyBudget && data.categoryItems.every((c) => c.spent == 0)) {
      return _buildEmptyState(context, theme);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ── 储蓄目标卡片 ──
        _SavingGoalCard(
          data: data,
          theme: theme,
          onTap: () => _showSavingGoalEditor(context, data, theme),
        ),
        const SizedBox(height: 16),

        // ── 超支提示 ──
        if (_hasOverBudget(data)) _OverBudgetBanner(data: data, theme: theme),

        // ── 分类预算列表 ──
        _SectionHeader(title: '分类预算', theme: theme),
        const SizedBox(height: 8),
        if (data.categoryItems.isEmpty)
          _EmptyHint(text: '暂无支出分类，请先在分类管理中创建', theme: theme)
        else
          ...data.categoryItems.map(
            (item) => _CategoryBudgetTile(
              item: item,
              theme: theme,
              onTap: () => _showCategoryBudgetEditor(context, item, theme),
            ),
          ),

        // 底部留白
        const SizedBox(height: 88),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 空状态
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('设置预算，控制支出',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('设定月度储蓄目标和分类预算上限\n帮你更好地管理资金',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showSavingGoalEditor(
                  context,
                  CategoryBudgetData(
                    categoryItems: [],
                    totalExpense: 0,
                    totalBudget: 0,
                    hasAnyBudget: false,
                  ),
                  theme),
              icon: const Icon(Icons.add),
              label: const Text('设置储蓄目标'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 储蓄目标编辑弹窗
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSavingGoalEditor(
      BuildContext context, CategoryBudgetData data, ThemeData theme) {
    final amountCtrl = TextEditingController(
      text: data.savingGoal?.targetAmount.toStringAsFixed(0) ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('月度储蓄目标', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('每月计划存下多少钱？',
                  style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 20),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '目标金额 (¥)',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text.trim());
                  if (amount == null || amount <= 0) {
                    if (mounted) {
                      SnackbarUtils.showError(context: context, message: '请输入有效金额');
                    }
                    return;
                  }

                  final budgetDao = ref.read(budgetDaoProvider);
                  final monthStr =
                      '$_year-${_month.toString().padLeft(2, '0')}';

                  final userId = ref.read(currentUserIdProvider);
                  if (data.savingGoal != null) {
                    await budgetDao.updateBudgetAmount(
                        data.savingGoal!.id, amount);
                    _syncBudget(data.savingGoal!.id, 'update', {
                      'id': data.savingGoal!.id,
                      'month': monthStr,
                      'type': 'saving_goal',
                      'target_amount': amount,
                    });
                  } else {
                    final newId = IdGenerator.generate();
                    await budgetDao.insertBudget(
                      BudgetsCompanion(
                        id: Value(newId),
                        userId: Value(userId),
                        month: Value(monthStr),
                        type: const Value('saving_goal'),
                        targetAmount: Value(amount),
                      ),
                    );
                    _syncBudget(newId, 'insert', {
                      'id': newId,
                      'month': monthStr,
                      'type': 'saving_goal',
                      'target_amount': amount,
                    });
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _refresh();
                },
                child: Text(data.savingGoal != null ? '更新目标' : '设定目标'),
              ),
              if (data.savingGoal != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    final savedGoal = data.savingGoal!;
                    final budgetDao = ref.read(budgetDaoProvider);
                    await budgetDao.softDeleteBudget(savedGoal.id);
                    _syncBudget(savedGoal.id, 'update', {
                      'id': savedGoal.id,
                      'month': savedGoal.month,
                      'type': 'saving_goal',
                      'target_amount': savedGoal.targetAmount,
                      'deleted': true,
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    });
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    _refresh();
                    if (mounted) {
                      SnackbarUtils.showUndo(
                        context: context,
                        message: '已删除储蓄目标',
                        onUndo: () async {
                          // 重新创建被删除的预算
                          final userId = ref.read(currentUserIdProvider);
                          final newId = IdGenerator.generate();
                          await budgetDao.insertBudget(
                            BudgetsCompanion(
                              id: Value(newId),
                              userId: Value(userId),
                              month: Value(savedGoal.month),
                              type: const Value('saving_goal'),
                              targetAmount: Value(savedGoal.targetAmount),
                            ),
                          );
                          _syncBudget(newId, 'insert', {
                            'id': newId,
                            'month': savedGoal.month,
                            'type': 'saving_goal',
                            'target_amount': savedGoal.targetAmount,
                          });
                          _refresh();
                        },
                        afterDialogClose: true,
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('删除目标'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 分类预算编辑弹窗
  // ═══════════════════════════════════════════════════════════════════════════

  void _showCategoryBudgetEditor(
      BuildContext context, CategoryBudgetItem item, ThemeData theme) {
    final amountCtrl = TextEditingController(
      text: item.budgetCap?.toStringAsFixed(0) ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${item.categoryName} 预算',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('本月已支出 ¥${item.spent.toStringAsFixed(2)}',
                  style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 20),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '预算上限 (¥)',
                  prefixText: '¥ ',
                  hintText: '留空表示不设上限',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final budgetDao = ref.read(budgetDaoProvider);
                  final monthStr =
                      '$_year-${_month.toString().padLeft(2, '0')}';

                  // 查找该分类已有预算
                  final existing =
                      await budgetDao.getCategoryBudget(monthStr, item.categoryId);

                  final text = amountCtrl.text.trim();
                  if (text.isEmpty) {
                    // 删除预算
                    if (existing != null) {
                      await budgetDao.softDeleteBudget(existing.id);
                      _syncBudget(existing.id, 'update', {
                        'id': existing.id,
                        'month': monthStr,
                        'type': 'category_budget',
                        'category_id': item.categoryId,
                        'target_amount': existing.targetAmount,
                        'deleted': true,
                        'updated_at': DateTime.now().toUtc().toIso8601String(),
                      });
                    }
                  } else {
                    final amount = double.tryParse(text);
                    if (amount == null || amount <= 0) return;

                    if (existing != null) {
                      await budgetDao.updateBudgetAmount(existing.id, amount);
                      _syncBudget(existing.id, 'update', {
                        'id': existing.id,
                        'month': monthStr,
                        'type': 'category_budget',
                        'category_id': item.categoryId,
                        'target_amount': amount,
                      });
                    } else {
                      final userId = ref.read(currentUserIdProvider);
                      final newId = IdGenerator.generate();
                      await budgetDao.insertBudget(
                        BudgetsCompanion(
                          id: Value(newId),
                          userId: Value(userId),
                          month: Value(monthStr),
                          type: const Value('category_budget'),
                          categoryId: Value(item.categoryId),
                          targetAmount: Value(amount),
                        ),
                      );
                      _syncBudget(newId, 'insert', {
                        'id': newId,
                        'month': monthStr,
                        'type': 'category_budget',
                        'category_id': item.categoryId,
                        'target_amount': amount,
                      });
                    }
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _refresh();
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _refresh() {
    ref.invalidate(categoryBudgetDataProvider(
        BudgetParams(year: _year, month: _month)));
  }

  /// 将预算变更同步到 Supabase
  void _syncBudget(String budgetId, String operation, Map<String, dynamic> payload) {
    final syncQueue = ref.read(syncQueueServiceProvider);
    syncQueue.enqueue(
      operationType: operation,
      tableName: 'budgets',
      recordId: budgetId,
      payload: jsonEncode(payload),
    );
    syncQueue.processQueue().catchError((_) {});
  }

  bool _hasOverBudget(CategoryBudgetData data) {
    return data.categoryItems.any((item) => item.isOverBudget);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 子组件
// ═════════════════════════════════════════════════════════════════════════════

/// 储蓄目标卡片
class _SavingGoalCard extends StatelessWidget {
  final CategoryBudgetData data;
  final ThemeData theme;
  final VoidCallback onTap;

  const _SavingGoalCard({
    required this.data,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasGoal = data.savingGoal != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasGoal
                      ? theme.colorScheme.primary.withAlpha(25)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.savings_outlined,
                  color: hasGoal
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('月度储蓄目标',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      hasGoal
                          ? '¥ ${data.savingGoal!.targetAmount.toStringAsFixed(0)}'
                          : '点击设置目标金额',
                      style: hasGoal
                          ? theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )
                          : theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 超支提示横幅
class _OverBudgetBanner extends StatefulWidget {
  final CategoryBudgetData data;
  final ThemeData theme;

  const _OverBudgetBanner({required this.data, required this.theme});

  @override
  State<_OverBudgetBanner> createState() => _OverBudgetBannerState();
}

class _OverBudgetBannerState extends State<_OverBudgetBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final overItems = widget.data.categoryItems
        .where((item) => item.isOverBudget)
        .toList();
    if (overItems.isEmpty) return const SizedBox.shrink();

    final names = overItems.map((e) => e.categoryName).join('、');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MaterialBanner(
        backgroundColor: widget.theme.colorScheme.error.withAlpha(20),
        padding: const EdgeInsets.all(12),
        leading: Icon(Icons.warning_amber_rounded,
            color: widget.theme.colorScheme.error),
        content: Text(
          '$names 已超出预算',
          style: widget.theme.textTheme.bodyMedium?.copyWith(
            color: widget.theme.colorScheme.error,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _dismissed = true),
            child: Text(
              '知道了',
              style: TextStyle(color: widget.theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类预算行
class _CategoryBudgetTile extends StatelessWidget {
  final CategoryBudgetItem item;
  final ThemeData theme;
  final VoidCallback onTap;

  const _CategoryBudgetTile({
    required this.item,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBudget = item.budgetCap != null && item.budgetCap! > 0;
    final isOver = item.isOverBudget;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：分类名 + 金额
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.categoryName,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '¥ ${item.spent.toStringAsFixed(2)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isOver
                                ? theme.colorScheme.error
                                : null,
                          ),
                        ),
                        if (hasBudget)
                          Text(
                            '/ ¥ ${item.budgetCap!.toStringAsFixed(0)}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),

                // 第二行：进度条（仅当有预算时显示）
                if (hasBudget) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: item.progress),
                      duration: AccessibilityUtils.motionDuration(context, const Duration(milliseconds: 600)),
                      curve: Curves.easeOut,
                      builder: (context, value, _) {
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          color: isOver
                              ? theme.colorScheme.error
                              : item.progress > 0.8
                                  ? theme.colorScheme.error.withAlpha(180)
                                  : theme.colorScheme.primary,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '已使用 ${(item.progress * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isOver
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                      if (isOver)
                        Text(
                          '超支 ¥${(item.spent - item.budgetCap!).toStringAsFixed(2)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],

                // 无预算时显示提示
                if (!hasBudget && item.spent > 0) ...[
                  const SizedBox(height: 4),
                  Text('未设定预算上限', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 分区标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 空提示占位
class _EmptyHint extends StatelessWidget {
  final String text;
  final ThemeData theme;

  const _EmptyHint({required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      alignment: Alignment.center,
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
  }
}
