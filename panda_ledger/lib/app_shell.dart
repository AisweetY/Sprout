import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/services/text_recognition/edge_function_ai_service.dart';
import 'data/account_dedup_service.dart';
import 'data/category_dedup_service.dart';
import 'data/local/app_database_provider.dart';
import 'data/local/dao/sync_metadata_dao.dart';
import 'data/local/seed_service.dart';
import 'data/sync/sync_queue_dao_provider.dart';
import 'data/sync/sync_state_provider.dart';
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

  /// 从后台恢复：pull → dedup → process 顺序执行，避免竞态
  Future<void> _onResumed() async {
    final syncService = ref.read(syncQueueServiceProvider);
    try {
      await syncService.pullFromSupabase();
      // pull 可能拉取云端数据与本地 seed 产生同名重复 → 去重后再推送
      await ref.read(categoryDedupServiceProvider).deduplicateOnce().catchError((_) => 0);
      await ref.read(accountDedupServiceProvider).deduplicateOnce().catchError((_) => 0);
      await syncService.processQueue();
    } catch (_) {}
    // 会员状态刷新放在同步之后（获取最新过期时间）
    ref.read(membershipProvider.notifier).refresh().catchError((_) {});

    // AI Edge Function 预热：后台停留超过 ~10 分钟后函数会进入冷启动状态，
    // 在 resume 时提前触发一次 ping，使用户下次打开 AI 记账时第一次即可成功。
    // 仅在已登录时发起（未登录 / 本地模式下 preheat 内部的 _ensureFreshSession 会提前返回）。
    const EdgeFunctionAiService().preheat();
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

    // 仅"刚登录"（首次全量同步）时显示进度；已登录的普通启动静默同步
    // 判断依据：initial_sync_done 标记未设置说明还没做过初始同步
    final hasLoggedInUser =
        Supabase.instance.client.auth.currentUser != null;
    final metadataDao = SyncMetadataDao(ref.read(appDatabaseProvider));
    final isFirstSync =
        hasLoggedInUser && !(await metadataDao.hasDoneInitialSync());

    if (isFirstSync) {
      ref.read(syncStateProvider.notifier).start();
    }

    // 是否为真正新用户（云端无数据 + 本地无分类 → 仅需种子初始化，无需"同步"）
    var wasNewUser = false;

    try {
      // 1. 先从 Supabase 拉取远端数据（新设备恢复 / 增量同步）
      try {
        await syncService.pullFromSupabase();
      } catch (e) {
        debugPrint('远端数据拉取失败: $e');
      }
      if (!mounted) return; // ← AppShell 若因 auth 竞态已被卸载，终止后续流程

      // 2. 拉取完成后再判断是否需要种子数据（真正新用户）
      try {
        final seedService = ref.read(seedServiceProvider);
        final needsSeeding = await seedService.needsSeeding();
        if (needsSeeding && mounted) {
          wasNewUser = true;
          // 新用户无需展示同步进度条：云端无数据，pull 几乎是瞬时完成
          // 提前 reset 让进度条消失，后续 seed + push 静默执行
          if (isFirstSync) {
            ref.read(syncStateProvider.notifier).reset();
          }
          final userId = ref.read(currentUserIdProvider);
          await seedService.seed(userId: userId);
        }
      } catch (e) {
        debugPrint('种子数据初始化失败: $e');
      }
      if (!mounted) return;

      // 2.5 去重：分类 + 账户（本地 seed 与云端拉取数据同名时自动合并）
      // 分类去重：合并同 kind+name 的一级分类，迁移子分类和流水
      try {
        await ref.read(categoryDedupServiceProvider).deduplicateOnce();
      } catch (e) {
        debugPrint('分类去重失败: $e');
      }
      // 账户去重：合并同 name+type 的账户，迁移引用该账户的流水
      try {
        await ref.read(accountDedupServiceProvider).deduplicateOnce();
      } catch (e) {
        debugPrint('账户去重失败: $e');
      }
      if (!mounted) return;

      // 3. 推送本地离线期间积累的变更
      await syncService.processQueue().catchError((e) {
        debugPrint('启动同步推送失败: $e');
      });
      if (!mounted) return;

      // 3.5 一致性对账：修复 processQueue 未完整执行 / conflict 记录
      await syncService.reconcileOnStartup().catchError((e) {
        debugPrint('启动对账失败: $e');
      });
      if (!mounted) return;

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

      // 同步完成：通知 UI（仅刚登录 + 非新用户）
      // 新用户（wasNewUser）已在 seed 阶段提前 reset，无需再次通知
      // 进度条会持续到 homeDataProvider 数据刷新完成后才收起（见 home_screen）
      if (isFirstSync && !wasNewUser && mounted) {
        ref.read(syncStateProvider.notifier).done('数据同步完成');
      }
    } catch (e) {
      debugPrint('初始化异常: $e');
      if (isFirstSync && !wasNewUser && mounted) {
        ref.read(syncStateProvider.notifier).reset();
      }
    }
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
