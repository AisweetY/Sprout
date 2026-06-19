import 'package:flutter/widgets.dart';

/// 无障碍辅助工具
///
/// 提供 reduced-motion 检测，确保动画尊重系统减弱动态效果设置。
class AccessibilityUtils {
  AccessibilityUtils._();

  /// 根据 reduced-motion 设置返回合适的动画时长。
  ///
  /// 用户开启减弱动态效果时返回 Duration.zero（瞬间完成），
  /// 否则返回原始时长。
  static Duration motionDuration(BuildContext context, Duration normal) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disableAnimations ? Duration.zero : normal;
  }

  /// 检查是否应跳过动画。
  static bool shouldReduceMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }
}
