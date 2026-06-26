import 'dart:async';
import 'package:flutter/material.dart';

/// 统一的错误状态组件，用于替代各页面简陋的 "加载失败: $e"
///
/// 特性：
/// - 品牌熊猫插画（使用 emoji 降级方案，后续可替换为 SVG）
/// - 友好的中文错误文案
/// - 重试按钮（可自定义回调）
/// - 弱网环境自动重试（2 秒后自动重试一次）
class ErrorStateWidget extends StatefulWidget {
  const ErrorStateWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.autoRetry = true,
    this.autoRetryDelay = const Duration(seconds: 2),
  });

  /// 错误信息（建议用友好文案，不要直接传异常 message）
  final String message;

  /// 重试回调。为 null 时不显示重试按钮，仅展示错误信息
  final VoidCallback? onRetry;

  /// 是否自动重试一次（默认 true）
  final bool autoRetry;

  /// 自动重试延迟（默认 2 秒）
  final Duration autoRetryDelay;

  /// 将原始异常转换为用户友好的中文文案
  static String friendlyMessage(Object error) {
    final str = error.toString();
    if (str.contains('SocketException') || str.contains('HandshakeException')) {
      return '网络连接失败，请检查网络后重试';
    }
    if (str.contains('TimeoutException') || str.contains('timeout')) {
      return '请求超时，请稍后重试';
    }
    if (str.contains('Permission')) {
      return '没有权限执行此操作';
    }
    if (str.contains('SqliteException') || str.contains('database')) {
      return '本地数据读取失败，请重启应用';
    }
    return '数据加载失败，请稍后重试';
  }

  @override
  State<ErrorStateWidget> createState() => _ErrorStateWidgetState();
}

class _ErrorStateWidgetState extends State<ErrorStateWidget> {
  bool _autoRetried = false;
  Timer? _autoRetryTimer;

  @override
  void initState() {
    super.initState();
    if (widget.autoRetry && widget.onRetry != null && !_autoRetried) {
      _autoRetryTimer = Timer(widget.autoRetryDelay, () {
        if (mounted) {
          _autoRetried = true;
          widget.onRetry?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 品牌插画区 — 🐼 emoji 作为降级方案，后续可替换为 Lottie/SVG
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.sentiment_dissatisfied_rounded,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 错误标题
            Text(
              '出了点小问题',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // 错误详情
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // 重试按钮
            if (widget.onRetry != null)
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新加载'),
              ),
          ],
        ),
      ),
    );
  }
}
