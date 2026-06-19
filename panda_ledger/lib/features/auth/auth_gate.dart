import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_shell.dart';
import '../../core/widgets/shimmer_loading.dart';
import 'auth_provider.dart';
import 'auth_screen.dart';

/// 认证网关
///
/// 根据登录状态决定显示 AppShell 还是 AuthScreen。
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(authStateProvider);

    switch (authStatus) {
      case AuthStatus.unknown:
        return Scaffold(
          body: Center(child: PageSkeletons.list(itemCount: 3)),
        );
      case AuthStatus.authenticated:
        return const AppShell();
      case AuthStatus.unauthenticated:
        return const AuthScreen();
    }
  }
}
