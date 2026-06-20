import 'package:flutter/material.dart';

/// 统一 SnackBar 提示工具
///
/// 所有提示信息都通过此工具显示，确保行为一致：
/// - 自动清除已显示的 SnackBar（避免叠加）
/// - 统一时长（成功提示 2 秒，可撤销提示 3 秒）
/// - 从对话框关闭后显示时，自动延迟到关闭动画完成
class SnackbarUtils {
  /// 显示简单提示（无操作按钮，2 秒后自动消失）
  static void show({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 2),
    bool afterDialogClose = false,
  }) {
    _doShow(
      context: context,
      snackBar: SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
      ),
      afterDialogClose: afterDialogClose,
    );
  }

  /// 显示可撤销提示（带"撤销"按钮，3 秒后自动消失）
  static void showUndo({
    required BuildContext context,
    required String message,
    required VoidCallback onUndo,
    Duration duration = const Duration(seconds: 3),
    bool afterDialogClose = false,
  }) {
    _doShow(
      context: context,
      snackBar: SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
        action: SnackBarAction(
          label: '撤销',
          onPressed: onUndo,
        ),
      ),
      afterDialogClose: afterDialogClose,
    );
  }

  /// 显示错误提示
  static void showError({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    _doShow(
      context: context,
      snackBar: SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ),
      afterDialogClose: false,
    );
  }

  /// 核心显示逻辑：先清除已有 SnackBar，再显示新的
  static void _doShow({
    required BuildContext context,
    required SnackBar snackBar,
    required bool afterDialogClose,
  }) {
    void showIt() {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }

    if (afterDialogClose) {
      // 延迟到对话框关闭动画完成后显示
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 再等一帧确保对话框真正关闭
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showIt();
        });
      });
    } else {
      showIt();
    }
  }
}
