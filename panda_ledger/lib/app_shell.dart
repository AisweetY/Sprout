import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/local/seed_service.dart';
import 'data/sync/sync_queue_dao_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/home/home_screen.dart';
import 'features/membership/membership_guard.dart';
import 'features/membership/membership_provider.dart';
import 'features/record/record_screen.dart';
import 'features/record/batch_record_screen.dart';
import 'features/assets/assets_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/settings/reminder_provider.dart';

/// 应用外壳 — 底部导航栏
///
/// 4 个一级 Tab + 底部导航栏上方的三区记账卡片。
/// 卡片挂载在 Scaffold 的 bottomNavigationBar 上方。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  static const _screens = [
    HomeScreen(),
    AssetsScreen(),
    InsightsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
      // 监听登出事件 → 清理用户相关状态
      ref.listen(authStateProvider, (previous, next) {
        if (previous == AuthStatus.authenticated &&
            next == AuthStatus.unauthenticated) {
          _onSignOut();
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(syncQueueServiceProvider).stopPeriodicSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    } else if (state == AppLifecycleState.paused) {
      ref.read(syncQueueServiceProvider).stopPeriodicSync();
    }
  }

  /// 从后台恢复：pull → process 顺序执行，避免竞态
  Future<void> _onResumed() async {
    final syncService = ref.read(syncQueueServiceProvider);
    try {
      await syncService.pullFromSupabase();
      await syncService.processQueue();
    } catch (_) {}
    // 会员状态刷新放在同步之后（获取最新过期时间）
    ref.read(membershipProvider.notifier).refresh().catchError((_) {});
  }

  /// 登出清理：会员缓存 + sync_queue 待处理项
  void _onSignOut() {
    ref.read(membershipProvider.notifier).clear();
    ref.read(syncQueueServiceProvider).clearQueue().catchError((_) {});
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    // 触发 ReminderProvider 初始化（若有已启用的提醒，自动重调度）
    ref.read(reminderProvider);

    final syncService = ref.read(syncQueueServiceProvider);

    // 1. 先从 Supabase 拉取远端数据（新设备恢复 / 增量同步）
    try {
      await syncService.pullFromSupabase();
    } catch (e) {
      debugPrint('远端数据拉取失败: $e');
    }

    // 2. 拉取完成后再判断是否需要种子数据（真正新用户）
    try {
      final seedService = ref.read(seedServiceProvider);
      final needsSeeding = await seedService.needsSeeding();
      if (needsSeeding) {
        final userId = ref.read(currentUserIdProvider);
        await seedService.seed(userId: userId);
      }
    } catch (e) {
      debugPrint('种子数据初始化失败: $e');
    }

    // 3. 推送本地离线期间积累的变更
    await syncService.processQueue().catchError((e) {
      debugPrint('启动同步推送失败: $e');
    });

    // 3.5 一致性对账：修复 processQueue 未完整执行 / conflict 记录
    await syncService.reconcileOnStartup().catchError((e) {
      debugPrint('启动对账失败: $e');
    });

    // 对账可能重新入队了记录 → 再推一次
    syncService.processQueue().catchError((e) {
      debugPrint('对账后同步推送失败: $e');
    });

    // 4. 启动后台定时同步
    syncService.startPeriodicSync();

    // 5. 刷新会员状态（异步，不阻塞启动流程）
    ref.read(membershipProvider.notifier).refresh().catchError((e) {
      debugPrint('会员状态刷新失败: $e');
    });
  }

  void _onTabChange(int index) {
    setState(() => _currentIndex = index);
  }

  void _onRecordTap() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecordScreen()),
    );
  }

  Future<void> _onBatchRecordTap() async {
    // 会员门禁：未会员弹付费墙，有会员直接进入
    if (!await requireMembership(context, ref)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BatchRecordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 记账入口卡片（仅首页显示）──
          if (_currentIndex == 0)
            _RecordEntryCard(
              theme: theme,
              onRecordTap: _onRecordTap,
              onBatchTap: _onBatchRecordTap,
            ),

          // ── 底部导航栏 ──
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabChange,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: '资产',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: '分析',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 记账入口卡片
///
/// 主操作「记一笔」占据主视觉权重；「AI 记账」（批量 AI 识别）作为次级入口。
class _RecordEntryCard extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onRecordTap;
  final VoidCallback onBatchTap;

  const _RecordEntryCard({
    required this.theme,
    required this.onRecordTap,
    required this.onBatchTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          // 主操作：记一笔
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: onRecordTap,
                icon: const Icon(Icons.edit_note, size: 22),
                label: const Text(
                  '记一笔',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 次级操作：AI 批量记账
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: onBatchTap,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI 记账'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
