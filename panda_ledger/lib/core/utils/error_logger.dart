import 'package:flutter/foundation.dart';

/// 统一错误日志工具
///
/// 在 Debug 模式下将错误信息打印到控制台；
/// Release 模式下静默（可将来接入 Sentry / Firebase Crashlytics）。
class ErrorLogger {
  ErrorLogger._();

  /// 记录一条带上下文的错误日志。
  ///
  /// [label] — 简短描述，说明"在哪里"发生了错误（如 "账户创建同步推送失败"）。
  /// [error] — 捕获到的异常对象。
  /// [stackTrace] — 对应的堆栈信息。
  static void log(String label, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('🔴 [$label] $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 10);
    }
    // TODO: 接入远程崩溃上报（Sentry / Firebase Crashlytics）
  }
}
