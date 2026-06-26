import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/error_logger.dart';
import 'membership_models.dart';

// ─────────────────────────────────────────────
// SharedPreferences 缓存键
// ─────────────────────────────────────────────
const _kIsActive   = 'membership_is_active';
const _kPlan       = 'membership_plan';
const _kExpiresAt  = 'membership_expires_at';  // ISO8601 字符串，null = 永久

// ─────────────────────────────────────────────
// MembershipState
// ─────────────────────────────────────────────

class MembershipState {
  final bool loading;
  final MembershipInfo? info;   // null = 非会员 or 未登录

  const MembershipState({this.loading = false, this.info});

  /// 快捷判断：是否真正有效会员
  bool get isActive => info?.isActive ?? false;

  MembershipState copyWith({bool? loading, MembershipInfo? info, bool clearInfo = false}) {
    return MembershipState(
      loading: loading ?? this.loading,
      info: clearInfo ? null : (info ?? this.info),
    );
  }
}

// ─────────────────────────────────────────────
// MembershipNotifier
// ─────────────────────────────────────────────

class MembershipNotifier extends StateNotifier<MembershipState> {
  MembershipNotifier() : super(const MembershipState()) {
    _loadFromCache();
  }

  /// 启动时先从本地缓存快速恢复（local-first，不等网络）
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive  = prefs.getBool(_kIsActive)   ?? false;
      final plan      = prefs.getString(_kPlan);
      final expiresStr = prefs.getString(_kExpiresAt);

      if (!isActive || plan == null) return;

      final expires = expiresStr != null ? DateTime.parse(expiresStr) : null;
      final info = MembershipInfo(
        plan: plan,
        status: 'active',
        expiresAt: expires,
        source: 'cache',
      );
      // 即使缓存显示 active，也需要检查时间是否已过期
      if (info.isActive) {
        if (mounted) state = MembershipState(info: info);
      } else {
        // 已过期，清掉缓存
        await _clearCache(prefs);
      }
    } catch (e, s) {
      ErrorLogger.log('读取会员缓存失败', e, s);
      debugPrint('⚠️ 读取会员缓存失败: $e');
    }
  }

  /// 从 Supabase 拉最新会员状态（异步，不阻塞 UI）
  Future<void> refresh() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      // 未登录，清空状态
      await clear();
      return;
    }

    if (mounted) state = state.copyWith(loading: true);

    try {
      final res = await Supabase.instance.client
          .from('memberships')
          .select('plan, status, expires_at, source')
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (res == null) {
        // 服务端无记录 = 非会员
        state = const MembershipState();
        await _clearCache(null);
        return;
      }

      final info = MembershipInfo.fromJson(res);
      state = MembershipState(info: info.isActive ? info : null);
      await _saveCache(info.isActive ? info : null);
    } catch (e, s) {
      ErrorLogger.log('刷新会员状态失败', e, s);
      debugPrint('⚠️ 刷新会员状态失败: $e');
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  /// 登出时清空
  Future<void> clear() async {
    if (mounted) state = const MembershipState();
    await _clearCache(null);
  }

  // ── 缓存读写 ──

  Future<void> _saveCache(MembershipInfo? info) async {
    final prefs = await SharedPreferences.getInstance();
    if (info == null || !info.isActive) {
      await _clearCache(prefs);
      return;
    }
    await prefs.setBool(_kIsActive, true);
    await prefs.setString(_kPlan, info.plan);
    if (info.expiresAt != null) {
      await prefs.setString(_kExpiresAt, info.expiresAt!.toIso8601String());
    } else {
      await prefs.remove(_kExpiresAt);
    }
  }

  Future<void> _clearCache(SharedPreferences? prefs) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.remove(_kIsActive);
    await p.remove(_kPlan);
    await p.remove(_kExpiresAt);
  }
}

// ─────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────

/// 会员状态（全局单例）
final membershipProvider =
    StateNotifierProvider<MembershipNotifier, MembershipState>((ref) {
  return MembershipNotifier();
});

/// 活跃 SKU 列表（升序排列）
final membershipSkusProvider = FutureProvider<List<MembershipSku>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return const [];

  final res = await Supabase.instance.client
      .from('membership_skus')
      .select()
      .eq('is_active', true)
      .order('sort_order');

  return (res as List)
      .map((e) => MembershipSku.fromJson(e as Map<String, dynamic>))
      .toList();
});
