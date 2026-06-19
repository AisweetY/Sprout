import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/remote/supabase_client.dart';

/// 认证状态
enum AuthStatus {
  unknown,
  authenticated,
  unauthenticated,
}

/// 认证状态管理
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthStatus>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AuthStatus> {
  AuthNotifier() : super(AuthStatus.unknown) {
    _checkInitialSession();
    _listenToAuthChanges();
  }

  /// 检查初始会话
  void _checkInitialSession() {
    final hasSession = SupabaseClientWrapper.isLoggedIn;
    state = hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }

  /// 监听认证状态变化
  void _listenToAuthChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        state = AuthStatus.authenticated;
      } else {
        state = AuthStatus.unauthenticated;
      }
    });
  }

  /// 注册
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    try {
      await SupabaseClientWrapper.instance.auth.signUp(
        email: email,
        password: password,
      );
      state = AuthStatus.authenticated;
    } catch (e) {
      rethrow;
    }
  }

  /// 登录
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await SupabaseClientWrapper.instance.auth.signInWithPassword(
        email: email,
        password: password,
      );
      state = AuthStatus.authenticated;
    } catch (e) {
      rethrow;
    }
  }

  /// 登出
  Future<void> signOut() async {
    await SupabaseClientWrapper.instance.auth.signOut();
    state = AuthStatus.unauthenticated;
  }

  /// 发送密码重置邮件
  Future<void> resetPassword(String email) async {
    await SupabaseClientWrapper.instance.auth.resetPasswordForEmail(email);
  }
}

/// 当前用户邮箱
final currentUserProvider = Provider<String?>((ref) {
  return Supabase.instance.client.auth.currentUser?.email;
});

/// 当前用户 ID（未登录时回退到 'local' 用于本地开发）
final currentUserIdProvider = Provider<String>((ref) {
  return Supabase.instance.client.auth.currentUser?.id ?? 'local';
});
