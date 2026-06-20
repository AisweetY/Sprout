import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/app_database_provider.dart';
import '../../data/local/seed_service.dart';
import '../auth/auth_provider.dart';
import '../home/home_provider.dart';
import '../insights/insights_provider.dart';
import '../assets/assets_provider.dart';
import 'account_manage_screen.dart';
import 'budget_settings_screen.dart';
import 'category_manage_screen.dart';
import 'export_service.dart';

/// 设置页
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── 账户信息 ──
          _SectionHeader(title: '账户'),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(25),
              child: Icon(Icons.savings, color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(email ?? '未登录'),
            subtitle: const Text('邮箱登录'),
            trailing: TextButton(
              onPressed: () => ref.read(authStateProvider.notifier).signOut(),
              child: const Text('登出'),
            ),
          ),
          const Divider(),

          // ── 数据管理 ──
          _SectionHeader(title: '数据'),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('导出 CSV'),
            onTap: () async {
              try {
                final exportService = ref.read(exportServiceProvider);
                await exportService.exportCsv();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导出 CSV 失败: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('导出 JSON'),
            onTap: () async {
              try {
                final exportService = ref.read(exportServiceProvider);
                await exportService.exportJson();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导出 JSON 失败: $e')),
                  );
                }
              }
            },
          ),
          const Divider(),

          // ── 账户与分类 ──
          _SectionHeader(title: '记账'),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('账户管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountManageScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('分类管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CategoryManageScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('预算与储蓄目标'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BudgetSettingsScreen()),
              );
            },
          ),
          const Divider(),

          // ── 清空数据 ──
          _SectionHeader(title: '危险操作'),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('清空所有数据', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('清空本地和云端全部数据，不可恢复'),
            onTap: () => _showClearDataDialog(context, ref),
          ),
          const Divider(),

          // ── 关于 ──
          _SectionHeader(title: '关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本'),
            trailing: Text('1.0.0'),
          ),
        ],
      ),
    );
  }
}

/// 弹出清空数据二次确认对话框
Future<void> _showClearDataDialog(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('清空所有数据'),
      content: const Text(
        '此操作将清空所有账单、账户、分类、预算数据，'
        '并同步删除云端备份。\n\n此操作不可恢复，确认清空？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('确认清空'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    await _clearAllData(ref);

    // 清空后重新初始化种子数据
    final userId = ref.read(currentUserIdProvider);
    final seedService = ref.read(seedServiceProvider);
    await seedService.seed(userId: userId);

    // 刷新所有页面
    ref.invalidate(homeDataProvider);
    ref.invalidate(assetsDataProvider);
    ref.invalidate(insightsDataProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('所有数据已清空'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清空数据失败: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// 清空本地数据库和云端 Supabase 数据
Future<void> _clearAllData(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);

  // 1. 清空本地 SQLite（注意外键顺序：先子表后主表）
  await db.delete(db.records).go();
  await db.delete(db.budgets).go();
  await db.delete(db.syncQueue).go();
  await db.delete(db.accounts).go();
  await db.delete(db.categories).go();

  // 2. 清空 Supabase 远端对应数据
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId != null) {
    await Future.wait([
      supabase.from('records').delete().eq('user_id', userId),
      supabase.from('budgets').delete().eq('user_id', userId),
      supabase.from('accounts').delete().eq('user_id', userId),
      supabase.from('categories').delete().eq('user_id', userId),
    ]);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
