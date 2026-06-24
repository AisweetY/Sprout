import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/notification_service.dart';

/// 每日记账提醒设置
class ReminderSettings {
  final bool loaded;
  final bool enabled;
  final int hour;
  final int minute;

  const ReminderSettings({
    required this.loaded,
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderSettings(
        loaded: true,
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

final reminderProvider =
    StateNotifierProvider<ReminderNotifier, ReminderSettings>((ref) {
  return ReminderNotifier();
});

class ReminderNotifier extends StateNotifier<ReminderSettings> {
  ReminderNotifier()
      : super(const ReminderSettings(
            loaded: false, enabled: false, hour: 21, minute: 0)) {
    _load();
  }

  static const _kEnabled = 'reminder_enabled';
  static const _kHour = 'reminder_hour';
  static const _kMinute = 'reminder_minute';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReminderSettings(
      loaded: true,
      enabled: prefs.getBool(_kEnabled) ?? false,
      hour: prefs.getInt(_kHour) ?? 21,
      minute: prefs.getInt(_kMinute) ?? 0,
    );
    // 应用启动后，若已开启则确保系统侧调度存在（覆盖重装/重启场景）
    if (state.enabled) {
      await NotificationService.instance
          .scheduleDailyReminder(state.hour, state.minute);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, state.enabled);
    await prefs.setInt(_kHour, state.hour);
    await prefs.setInt(_kMinute, state.minute);
  }

  /// 开关提醒。开启时请求权限，未授权则回退为关闭，返回是否成功开启。
  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      final granted = await NotificationService.instance.requestPermissions();
      if (!granted) {
        state = state.copyWith(enabled: false);
        await _persist();
        return false;
      }
      state = state.copyWith(enabled: true);
      await _persist();
      await NotificationService.instance
          .scheduleDailyReminder(state.hour, state.minute);
      return true;
    } else {
      state = state.copyWith(enabled: false);
      await _persist();
      await NotificationService.instance.cancelDailyReminder();
      return true;
    }
  }

  /// 修改提醒时间（若已开启则立即重新调度）
  Future<void> setTime(int hour, int minute) async {
    state = state.copyWith(hour: hour, minute: minute);
    await _persist();
    if (state.enabled) {
      await NotificationService.instance.scheduleDailyReminder(hour, minute);
    }
  }
}
