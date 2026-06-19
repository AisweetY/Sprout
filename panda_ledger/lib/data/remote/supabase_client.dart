import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 客户端便捷访问
///
/// 注意：Supabase 已在 main.dart 中通过 [Supabase.initialize] 初始化，
/// 本类提供便捷的 getter 方法，不重复初始化。
class SupabaseClientWrapper {
  SupabaseClientWrapper._();

  /// 获取 Supabase 客户端实例
  static SupabaseClient get instance => Supabase.instance.client;

  /// 获取当前登录用户 ID
  static String? get currentUserId =>
      Supabase.instance.client.auth.currentUser?.id;

  /// 获取当前登录用户邮箱
  static String? get currentUserEmail =>
      Supabase.instance.client.auth.currentUser?.email;

  /// 是否已登录
  static bool get isLoggedIn =>
      Supabase.instance.client.auth.currentSession != null;
}
