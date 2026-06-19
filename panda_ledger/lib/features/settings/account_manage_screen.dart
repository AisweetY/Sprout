import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/shimmer_loading.dart';
import '../../data/local/database.dart';
import '../../data/repository/account_repository.dart';
import '../auth/auth_provider.dart';

/// 所有账户列表 Provider — 自动响应数据变化
final allAccountsProvider = FutureProvider<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).getAllAccounts();
});

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
    ref.invalidate(allAccountsProvider);
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
      body: ref.watch(allAccountsProvider).when(
        loading: () => PageSkeletons.list(itemCount: 5),
        error: (e, _) => Center(child: Text('加载失败：$e')),
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
              ..._buildGroup(context, active, '活跃账户'),
              if (archived.isNotEmpty) ..._buildGroup(context, archived, '已归档'),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildGroup(BuildContext context, List<Account> accounts, String title) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title, style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        )),
      ),
      ...accounts.map((a) => _AccountTile(
            account: a,
            onTap: () => _showEditDialog(a),
            onLongPress: () => _showArchiveDialog(a),
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
                      if (name.isEmpty) return;
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
    final balanceCtrl = TextEditingController(text: account.balance.toStringAsFixed(2));

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
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(account.name, style: Theme.of(ctx).textTheme.titleLarge),
              Text(_typeLabel(account.type), style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 20),
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
                  final newBalance = double.tryParse(balanceCtrl.text) ?? account.balance;
                  await ref.read(accountRepositoryProvider).correctBalance(account.id, newBalance);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
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
              _showUndoSnackBar(
                '已归档「${account.name}」',
                () async {
                  await ref.read(accountRepositoryProvider).unarchive(account.id);
                  _refresh();
                },
              );
            },
            child: const Text('归档'),
          ),
        ],
      ),
    );
  }

  void _showUndoSnackBar(String message, Future<void> Function() onUndo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: onUndo,
        ),
      ),
    );
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

class _AccountTile extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AccountTile({
    required this.account,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLiability = account.isLiability;
    final balanceColor = isLiability ? theme.colorScheme.error : theme.colorScheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: CircleAvatar(
          backgroundColor: balanceColor.withAlpha(30),
          child: Icon(_typeIcon(account.type), color: balanceColor, size: 20),
        ),
        title: Text(account.name),
        subtitle: Text(_typeLabel(account.type)),
        trailing: Text(
          '¥ ${account.balance.toStringAsFixed(2)}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: balanceColor,
          ),
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
