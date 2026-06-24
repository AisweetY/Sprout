import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/app_database_provider.dart';
import '../../data/local/seed_service.dart';
import '../../data/sync/sync_queue_dao_provider.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_screen.dart';
import '../auth/local_mode_provider.dart';
import '../home/home_provider.dart';
import '../insights/insights_provider.dart';
import '../assets/assets_provider.dart';
import 'account_manage_screen.dart';
import 'budget_settings_screen.dart';
import 'category_manage_screen.dart';
import 'export_service.dart';
import '../../core/services/version_service.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../membership/membership_center_screen.dart';
import '../membership/membership_provider.dart';
import 'reminder_provider.dart';

/// 设置页
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(currentUserProvider);
    final isLoggedIn = email != null;
    final reminder = ref.watch(reminderProvider);
    final membership = ref.watch(membershipProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── 账户信息 ──
          _SectionHeader(title: '账户'),
          if (isLoggedIn)
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withAlpha(25),
                child: Icon(Icons.cloud_done_outlined,
                    color: Theme.of(context).colorScheme.primary),
              ),
              title: Text(email),
              subtitle: const Text('已开启云同步'),
              trailing: TextButton(
                onPressed: () => ref.read(authStateProvider.notifier).signOut(),
                child: const Text('登出'),
              ),
            )
          else
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withAlpha(25),
                child: Icon(Icons.cloud_off_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              title: const Text('本地模式'),
              subtitle: const Text('数据仅保存在本机，点击登录以云端备份'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _loginForSync(context, ref),
            ),
          // ── 会员中心入口 ──
          ListTile(
            leading: CircleAvatar(
              backgroundColor: membership.isActive
                  ? Theme.of(context).colorScheme.primary.withAlpha(25)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.workspace_premium_rounded,
                color: membership.isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            title: const Text('会员中心'),
            subtitle: Text(
              membership.isActive
                  ? '${membership.info!.planLabel} · ${membership.info!.expiryLabel}'
                  : '开通会员解锁 AI 记账与 AI 小结',
            ),
            trailing: membership.isActive
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '生效中',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : FilledButton.tonal(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MembershipCenterScreen()),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('开通'),
                  ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const MembershipCenterScreen()),
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

          // ── 提醒 ──
          _SectionHeader(title: '提醒'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('每日记账提醒'),
            subtitle: Text(reminder.enabled
                ? '每天 ${reminder.timeLabel} 提醒记账'
                : '开启后每天定时提醒记账'),
            value: reminder.enabled,
            onChanged: (v) async {
              final ok = await ref.read(reminderProvider.notifier).setEnabled(v);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('通知权限被拒绝，请在系统设置中开启'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          if (reminder.enabled)
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('提醒时间'),
              trailing: Text(
                reminder.timeLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: reminder.timeOfDay,
                  helpText: '选择每日提醒时间',
                );
                if (picked != null) {
                  await ref
                      .read(reminderProvider.notifier)
                      .setTime(picked.hour, picked.minute);
                }
              },
            ),
          const Divider(),

          // ── 外观 ──
          _SectionHeader(title: '外观'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('主题模式'),
            subtitle: Text(ref.watch(themeModeLabelProvider)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ref.read(themeModeProvider.notifier).cycle(),
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
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            trailing: ref.watch(appVersionProvider).when(
                  data: (v) => Text(v),
                  loading: () => const Text('…'),
                  error: (_, _) => const Text('1.0.0'),
                ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () {
              // 本地记账应用：数据仅存本机。登录后同步到用户私有的 Supabase 实例。
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('隐私政策'),
                  content: const Text(
                    '熊猫记账采用本地优先架构：\n\n'
                    '• 所有数据默认保存在您的设备本地\n'
                    '• 仅当您主动登录后，数据才会加密同步至您私有的云端存储\n'
                    '• 我们不会收集、上传或分享您的任何财务数据\n'
                    '• 您可以随时导出所有数据（CSV / JSON）或清空全部数据',
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 本地模式下登录以开启云同步
///
/// 流程：push AuthScreen 登录 → 关闭本地模式 → flush 本地堆积的 sync_queue
/// → 拉取云端数据合并。本地期间所有写入已入队，登录后自动推送至新账户。
Future<void> _loginForSync(BuildContext context, WidgetRef ref) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const AuthScreen()),
  );

  // 返回后确认是否登录成功
  if (ref.read(authStateProvider) != AuthStatus.authenticated) return;

  await ref.read(localModeProvider.notifier).disable();

  final sync = ref.read(syncQueueServiceProvider);
  // 先推送本地堆积变更到云端，再拉取云端已有数据
  try {
    await sync.processQueue();
    await sync.pullFromSupabase();
    await sync.processQueue();
  } catch (_) {
    // 同步失败不阻塞，后台定时同步会继续重试
  }

  // 刷新页面数据
  ref.invalidate(homeDataProvider);
  ref.invalidate(assetsDataProvider);
  ref.invalidate(insightsDataProvider);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已开启云同步，本地数据正在上传'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 弹出清空数据二次确认对话框（要求勾选"我已导出备份"）
Future<void> _showClearDataDialog(BuildContext context, WidgetRef ref) async {
  bool backedUp = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('清空所有数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '此操作将清空所有账单、账户、分类、预算数据，'
              '并同步删除云端备份。\n\n此操作不可恢复。',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: backedUp,
              onChanged: (v) => setDialogState(() => backedUp = v ?? false),
              title: const Text('我已导出数据备份'),
              subtitle: const Text('导出 CSV / JSON 后再清空更安全'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  backedUp ? Theme.of(ctx).colorScheme.error : null,
            ),
            onPressed: backedUp ? () => Navigator.of(ctx).pop(true) : null,
            child: const Text('确认清空'),
          ),
        ],
      ),
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
