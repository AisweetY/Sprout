import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
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
