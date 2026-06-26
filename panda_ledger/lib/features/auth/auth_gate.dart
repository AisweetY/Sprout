import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_shell.dart';
import '../../core/widgets/shimmer_loading.dart';
import 'auth_provider.dart';
import 'auth_screen.dart';
import 'local_mode_provider.dart';

/// 认证网关
///
/// 决策顺序：
/// 1. 已登录 → AppShell（云同步模式）
/// 2. 状态未知或本地模式尚未读取完成 → 骨架屏（避免闪屏）
/// 3. 未登录 + 本地模式已开启 → AppShell（本地优先，数据仅落本地）
/// 4. 未登录 + 未开启本地模式 → AuthScreen
///
/// **防止 AppShell 因 auth 竞态被错误卸载/重挂载**
/// `onAuthStateChange` 在 JWT 刷新期间可能短暂发出 session=null，
/// 导致 authStatus 短暂变为 unauthenticated，引发 AppShell 卸载 → 重挂载，
/// 触发 _initialize() 再次执行，造成重复 seed（重复分类/账户）。
/// 修复：当 authStatus 为 unauthenticated 时，先查 SDK 内存缓存中的 currentSession；
/// 若 session 仍在，说明是短暂抖动，继续保持 AppShell 展示，不做切换。
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(authStateProvider);

    // 已登录优先，无需等待本地模式标记
    if (authStatus == AuthStatus.authenticated) {
      return const AppShell();
    }

    // 防止 JWT 刷新竞态导致 AppShell 被误卸载：
    // authStatus 短暂变为 unauthenticated，但 SDK 内存 session 仍在 → 视为已登录
    if (authStatus == AuthStatus.unauthenticated) {
      final hasLiveSession =
          Supabase.instance.client.auth.currentSession != null;
      if (hasLiveSession) {
        return const AppShell();
      }
    }

    final localMode = ref.watch(localModeProvider);

    if (authStatus == AuthStatus.unknown || !localMode.loaded) {
      return Scaffold(
        body: Center(child: PageSkeletons.list(itemCount: 3)),
      );
    }

    // 未登录：本地模式直接进入，否则展示登录页
    return localMode.enabled ? const AppShell() : const AuthScreen();
  }
}
