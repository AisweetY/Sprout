import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式状态（system → light → dark 三态循环）
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

/// 主题模式可读标签（响应式跟随 themeModeProvider）
final themeModeLabelProvider = Provider<String>((ref) {
  return switch (ref.watch(themeModeProvider)) {
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
    _ => '跟随系统',
  };
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  static const _key = 'theme_mode_index'; // 0=system, 1=light, 2=dark

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_key) ?? 0;
    state = _modeFromIndex(idx);
  }

  Future<void> cycle() async {
    final idx = (_indexFromMode(state) + 1) % 3;
    state = _modeFromIndex(idx);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, idx);
  }

  ThemeMode _modeFromIndex(int idx) => switch (idx) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  int _indexFromMode(ThemeMode m) => switch (m) {
        ThemeMode.light => 1,
        ThemeMode.dark => 2,
        _ => 0,
      };

  String get label => switch (state) {
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
        _ => '跟随系统',
      };
}
