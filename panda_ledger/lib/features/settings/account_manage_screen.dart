import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/snackbar_utils.dart';
import '../../core/widgets/error_state_widget.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/account_repository.dart';
import '../auth/auth_provider.dart';

/// 账户管理页面
class AccountManageScreen extends ConsumerStatefulWidget {
  const AccountManageScreen({super.key});

  @override
  ConsumerState<AccountManageScreen> createState() => _AccountManageScreenState();
}

class _AccountManageScreenState extends ConsumerState<AccountManageScreen> {
  @override
  void initState() {
    super.initState();
  }

  void _refresh() {
    // StreamProvider 自动响应数据变更，无需手动 invalidate
    // 保留此方法以供兼容
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('账户管理'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        icon: const Icon(Icons.add),
        label: const Text('添加账户'),
      ),
      body: ref.watch(allAccountsStreamProvider).when(
        loading: () => PageSkeletons.list(itemCount: 5),
        error: (e, _) => ErrorStateWidget(
          message: ErrorStateWidget.friendlyMessage(e),
          onRetry: () => ref.invalidate(allAccountsStreamProvider),
        ),
        data: (accounts) {
          if (accounts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('还没有账户', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text('点击下方按钮添加第一个账户',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }

          // 按类型分组
          final active = accounts.where((a) => !a.isArchived).toList();
          final archived = accounts.where((a) => a.isArchived).toList();

          final groupOrder = ['cash', 'bank', 'credit', 'loan', 'invest', 'other'];
          active.sort((a, b) {
            final ai = groupOrder.indexOf(a.type);
            final bi = groupOrder.indexOf(b.type);
            return ai.compareTo(bi);
          });

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ..._buildActiveGroup(context, active),
              if (archived.isNotEmpty) ..._buildArchivedGroup(context, archived),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildActiveGroup(BuildContext context, List<Account> accounts) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('活跃账户', style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        )),
      ),
      ...accounts.map((a) => _AccountTile(
            account: a,
            onTap: () => _showEditDialog(a),
            onLongPress: () => _showArchiveDialog(a),
            onCalibrate: () => _showCalibrateDialog(a),
          )),
    ];
  }

  List<Widget> _buildArchivedGroup(BuildContext context, List<Account> accounts) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('已归档', style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.w600,
        )),
      ),
      ...accounts.map((a) => _AccountTile(
            account: a,
            onTap: () => _showRestoreDialog(a),
            onLongPress: () => _showRestoreDialog(a),
          )),
    ];
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0');
    String type = 'cash';
    bool isLiability = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
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
                  Text('添加账户', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '账户名称',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: '账户类型',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('现金')),
                      DropdownMenuItem(value: 'bank', child: Text('储蓄卡')),
                      DropdownMenuItem(value: 'credit', child: Text('信用卡')),
                      DropdownMenuItem(value: 'loan', child: Text('贷款')),
                      DropdownMenuItem(value: 'invest', child: Text('投资')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) {
                      setSheetState(() {
                        type = v!;
                        isLiability = (v == 'credit' || v == 'loan');
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: balanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '当前余额',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  if (isLiability) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16,
                            color: Theme.of(ctx).colorScheme.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('负债类账户余额将以负数计入净资产',
                              style: Theme.of(ctx).textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final balance = double.tryParse(balanceCtrl.text) ?? 0;
                      if (name.isEmpty) {
                        if (ctx.mounted) {
                          SnackbarUtils.showError(context: ctx, message: '请输入账户名称');
                        }
                        return;
                      }
                      final repo = ref.read(accountRepositoryProvider);
                      final userId = ref.read(currentUserIdProvider);
                      await repo.createAccount(
                        userId: userId,
                        name: name,
                        type: type,
                        balance: balance,
                        isLiability: isLiability,
                      );
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      _refresh();
                    },
                    child: const Text('创建'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditDialog(Account account) {
    final nameCtrl = TextEditingController(text: account.name);
    final balanceCtrl = TextEditingController(text: account.balance.toStringAsFixed(2));
    String type = account.type;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('编辑账户', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  // 账户名称
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '账户名称',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 账户类型
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: '账户类型',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('现金')),
                      DropdownMenuItem(value: 'bank', child: Text('储蓄卡')),
                      DropdownMenuItem(value: 'credit', child: Text('信用卡')),
                      DropdownMenuItem(value: 'loan', child: Text('贷款')),
                      DropdownMenuItem(value: 'invest', child: Text('投资')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => type = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  // 余额校正
                  TextField(
                    controller: balanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '校正余额',
                      helperText: '直接修改余额会自动生成一条余额调整流水',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      final repo = ref.read(accountRepositoryProvider);

                      // 更新名称和类型
                      if (name != account.name || type != account.type) {
                        await repo.updateNameAndType(account.id, name, type);
                      }

                      // 校正余额（如有变化）
                      final newBalance = double.tryParse(balanceCtrl.text) ?? account.balance;
                      if (newBalance != account.balance) {
                        await repo.correctBalance(account.id, newBalance);
                      }

                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      _refresh();
                      if (name != account.name || type != account.type) {
                        if (mounted) {
                          SnackbarUtils.show(
                            context: context,
                            message: '已更新「$name」',
                            afterDialogClose: true,
                          );
                        }
                      }
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 余额校准 — 专为「实际余额对不上」场景设计
  ///
  /// 展示当前系统余额 + 输入实际余额，差额自动生成 adjustment 记录。
  /// 弹窗聚焦单一任务，比编辑页的「校正余额」字段更可发现。
  void _showCalibrateDialog(Account account) {
    final newBalanceCtrl = TextEditingController();
    final oldBalance = account.balance;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final newText = newBalanceCtrl.text;
          final newVal = double.tryParse(newText);
          final diff =
              newVal != null ? (newVal - oldBalance) : 0.0;
          final hasDiff = diff.abs() > 0;

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.tune, size: 22,
                    color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(child: Text('余额校准')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前系统余额',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text('¥ ${oldBalance.toStringAsFixed(2)}',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                const SizedBox(height: 16),
                TextField(
                  controller: newBalanceCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '实际余额',
                    helperText: '输入真实余额，差额会自动生成调整记录',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (hasDiff)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Icon(
                          diff > 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 16,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          diff > 0
                              ? '系统余额将增加 ¥${diff.toStringAsFixed(2)}'
                              : '系统余额将减少 ¥${(-diff).toStringAsFixed(2)}',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: hasDiff
                    ? () async {
                        // 捕获当前值，避免闭包中的 null safety 推断问题
                        final confirmed = double.tryParse(newBalanceCtrl.text);
                        if (confirmed == null || confirmed == oldBalance) return;
                        final repo = ref.read(accountRepositoryProvider);
                        await repo.correctBalance(account.id, confirmed);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        if (mounted) {
                          SnackbarUtils.show(
                            context: context,
                            message:
                                '已校准「${account.name}」余额至 ¥${confirmed.toStringAsFixed(2)}',
                            afterDialogClose: true,
                          );
                        }
                      }
                    : null,
                child: const Text('确认校准'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showArchiveDialog(Account account) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档账户'),
        content: Text('确定要归档「${account.name}」吗？\n归档后将从首页隐藏，历史数据保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(accountRepositoryProvider).archive(account.id);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              _refresh();
              if (mounted) {
                SnackbarUtils.showUndo(
                  context: context,
                  message: '已归档「${account.name}」',
                  onUndo: () async {
                    await ref.read(accountRepositoryProvider).unarchive(account.id);
                    _refresh();
                  },
                  afterDialogClose: true,
                );
              }
            },
            child: const Text('归档'),
          ),
        ],
      ),
    );
  }

  /// 恢复已归档账户
  void _showRestoreDialog(Account account) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复账户'),
        content: Text('确定要恢复「${account.name}」吗？\n恢复后该账户将重新出现在首页和记账页面。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(accountRepositoryProvider).unarchive(account.id);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              _refresh();
              if (mounted) {
                SnackbarUtils.show(
                  context: context,
                  message: '已恢复「${account.name}」',
                  afterDialogClose: true,
                );
              }
            },
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }

}

class _AccountTile extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onCalibrate;

  const _AccountTile({
    required this.account,
    required this.onTap,
    required this.onLongPress,
    this.onCalibrate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLiability = account.isLiability;
    final balanceColor = isLiability ? theme.colorScheme.error : theme.colorScheme.primary;
    final isArchived = account.isArchived;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: CircleAvatar(
          backgroundColor: isArchived
              ? theme.colorScheme.surfaceContainerHighest
              : balanceColor.withAlpha(30),
          child: Icon(
            isArchived ? Icons.archive : _typeIcon(account.type),
            color: isArchived ? theme.colorScheme.outline : balanceColor,
            size: 20,
          ),
        ),
        title: Text(
          account.name,
          style: isArchived
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline)
              : null,
        ),
        subtitle: Text(
          isArchived ? '已归档 · ${_typeLabel(account.type)}' : _typeLabel(account.type),
          style: isArchived
              ? TextStyle(color: theme.colorScheme.outline.withAlpha(180))
              : null,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isArchived && onCalibrate != null)
              IconButton(
                icon: const Icon(Icons.tune, size: 18),
                tooltip: '余额校准',
                onPressed: onCalibrate,
                visualDensity: VisualDensity.compact,
              ),
            Text(
              '¥ ${account.balance.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: isArchived ? theme.colorScheme.outline : balanceColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'cash' => Icons.money,
      'bank' => Icons.account_balance,
      'credit' => Icons.credit_card,
      'loan' => Icons.real_estate_agent,
      'invest' => Icons.trending_up,
      _ => Icons.more_horiz,
    };
  }

  String _typeLabel(String type) {
    return switch (type) {
      'cash' => '现金',
      'bank' => '储蓄卡',
      'credit' => '信用卡',
      'loan' => '贷款',
      'invest' => '投资',
      _ => '其他',
    };
  }
}
