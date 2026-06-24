import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地模式状态
///
/// [loaded] 标记是否已从 SharedPreferences 读取完成（避免冷启动闪屏）。
/// [enabled] 标记用户是否选择了「先在本地记账，稍后登录」。
class LocalModeState {
  final bool loaded;
  final bool enabled;
  const LocalModeState({required this.loaded, required this.enabled});
}

/// 本地优先模式开关
///
/// 用户可不登录直接使用 App（数据仅落本地 Drift）。后续在设置中登录后，
/// sync_queue 中堆积的本地写入会自动 flush 到云端。
final localModeProvider =
    StateNotifierProvider<LocalModeNotifier, LocalModeState>((ref) {
  return LocalModeNotifier();
});

class LocalModeNotifier extends StateNotifier<LocalModeState> {
  LocalModeNotifier()
      : super(const LocalModeState(loaded: false, enabled: false)) {
    _load();
  }

  static const _key = 'local_mode_enabled';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = LocalModeState(loaded: true, enabled: prefs.getBool(_key) ?? false);
  }

  /// 进入本地模式（用户点击「先在本地记账」）
  Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    state = const LocalModeState(loaded: true, enabled: true);
  }

  /// 退出本地模式（登录成功后调用，使后续登出回到登录页）
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
    state = const LocalModeState(loaded: true, enabled: false);
  }
}
