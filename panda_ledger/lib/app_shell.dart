import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/local/seed_service.dart';
import 'data/sync/sync_queue_dao_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/home/home_screen.dart';
import 'features/record/record_screen.dart';
import 'features/record/batch_record_screen.dart';
import 'features/assets/assets_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/settings/settings_screen.dart';

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
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
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
      // 从后台回到前台 → 立即同步
      final syncService = ref.read(syncQueueServiceProvider);
      syncService.pullFromSupabase().catchError((_) {});
      syncService.processQueue().catchError((_) {});
    } else if (state == AppLifecycleState.paused) {
      ref.read(syncQueueServiceProvider).stopPeriodicSync();
    }
  }

  Future<void> _initialize() async {
    if (!mounted) return;

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
  }

  void _onTabChange(int index) {
    setState(() => _currentIndex = index);
  }

  void _onRecordTap() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecordScreen()),
    );
  }

  void _onBatchRecordTap() {
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
          // ── 三区记账卡片（仅首页显示）──
          if (_currentIndex == 0)
            _RecordEntryCard(
              theme: theme,
              onRecordTap: _onRecordTap,
              onVoiceTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('语音识别功能开发中，敬请期待'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
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
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 三区记账入口卡片
///
/// 左：「记一笔收支」→ 跳转记账页
/// 中：绿色麦克风悬浮按钮（功能开发中）
/// 右：「一口气记账」→ 跳转批量录入
class _RecordEntryCard extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onRecordTap;
  final VoidCallback onVoiceTap;
  final VoidCallback onBatchTap;

  const _RecordEntryCard({
    required this.theme,
    required this.onRecordTap,
    required this.onVoiceTap,
    required this.onBatchTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Card(
        elevation: 3,
        shadowColor: theme.colorScheme.shadow.withAlpha(60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
            width: 0.5,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 三段布局
            Row(
              children: [
                // 左侧：记一笔收支
                Expanded(
                  child: InkWell(
                    onTap: onRecordTap,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note, size: 22, color: theme.colorScheme.primary),
                          const SizedBox(height: 2),
                          Text('记一笔收支',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),

                // 中间占位（给悬浮按钮留空间）
                const SizedBox(width: 52, height: 48),

                // 右侧：一口气记账
                Expanded(
                  child: InkWell(
                    onTap: onBatchTap,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 22, color: theme.colorScheme.primary),
                          const SizedBox(height: 2),
                          Text('一口气记账',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // 中间悬浮按钮
            Positioned(
              top: -12, // 向上悬浮于卡片上方
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onVoiceTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.colorScheme.surface, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4CAF50).withAlpha(60),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
