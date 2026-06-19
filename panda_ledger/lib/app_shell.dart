import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/local/seed_service.dart';
import 'data/sync/sync_queue_dao_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/home/home_screen.dart';
import 'features/record/record_screen.dart';
import 'features/assets/assets_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/settings/settings_screen.dart';

/// 应用外壳 — 底部导航栏
///
/// 4 个一级 Tab + 中央突出的「记一笔」FAB。
/// FAB 位于 centerDocked 位置，悬浮在导航栏中间上方。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    // 1. 种子数据初始化（首次启动自动创建预置分类）
    try {
      final seedService = ref.read(seedServiceProvider);
      final needsSeeding = await seedService.needsSeeding();
      if (needsSeeding) {
        final userId = ref.read(currentUserIdProvider);
        await seedService.seed(userId: userId);
      }
    } catch (e) {
      // 种子数据初始化失败不阻塞用户使用
      debugPrint('种子数据初始化失败: $e');
    }

    // 2. 从 Supabase 增量拉取远端数据
    try {
      final syncService = ref.read(syncQueueServiceProvider);
      await syncService.pullFromSupabase();
    } catch (e) {
      // 拉取失败不阻塞本地使用
      debugPrint('远端数据拉取失败: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: _onRecordTap,
        tooltip: '记一笔',
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}
