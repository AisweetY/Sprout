import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(authStateProvider);

    // 已登录优先，无需等待本地模式标记
    if (authStatus == AuthStatus.authenticated) {
      return const AppShell();
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
