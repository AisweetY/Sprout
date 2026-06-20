import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'insights_provider.dart';

/// AI 小结生成状态
enum AiSummaryStatus { idle, loading, done, error }

/// 小结缓存快照
class _CachedSummary {
  final String text;
  final DateTime generatedAt;
  const _CachedSummary({required this.text, required this.generatedAt});
}

/// AI 小结状态
class AiSummaryState {
  final AiSummaryStatus status;
  final String? text;      // 成功时的小结文本
  final String? errorMsg;  // 失败时的错误信息

  const AiSummaryState({
    this.status = AiSummaryStatus.idle,
    this.text,
    this.errorMsg,
  });

  AiSummaryState copyWith({
    AiSummaryStatus? status,
    String? text,
    String? errorMsg,
  }) {
    return AiSummaryState(
      status: status ?? this.status,
      text: text ?? this.text,
      errorMsg: errorMsg ?? this.errorMsg,
    );
  }
}

/// AI 小结状态管理
///
/// - 缓存：同一时间维度数据不变时，不重复生成
/// - 非阻塞：loading 期间页面可正常操作
/// - 重新生成：忽略缓存强制调用
class AiSummaryNotifier extends StateNotifier<AiSummaryState> {
  /// 缓存 Map，key 为维度标识
  final Map<String, _CachedSummary> _cache = {};

  /// 上次 prepare 的 key（避免重复切换）
  String? _lastPreparedKey;

  AiSummaryNotifier() : super(const AiSummaryState());

  /// 确保已为当前参数准备好状态（幂等，可在 build 中安全调用）
  void ensurePrepared(InsightsParams params) {
    final key = _cacheKey(params);
    if (key == _lastPreparedKey) return;
    _lastPreparedKey = key;

    final cached = _cache[key];
    if (cached != null) {
      state = AiSummaryState(status: AiSummaryStatus.done, text: cached.text);
    } else {
      state = const AiSummaryState();
    }
  }

  /// 获取缓存
  String? getCached(InsightsParams params) {
    return _cache[_cacheKey(params)]?.text;
  }

  /// 生成小结（如有缓存则直接返回）
  Future<void> generateSummary({
    required InsightsParams params,
    required AiSummaryInput input,
  }) async {
    // 1. 检查缓存
    final key = _cacheKey(params);
    final cached = _cache[key];
    if (cached != null) {
      state = AiSummaryState(status: AiSummaryStatus.done, text: cached.text);
      return;
    }

    await _doGenerate(key, input);
  }

  /// 强制重新生成（忽略缓存）
  Future<void> regenerateSummary({
    required InsightsParams params,
    required AiSummaryInput input,
  }) async {
    final key = _cacheKey(params);
    _cache.remove(key);
    await _doGenerate(key, input);
  }

  /// 核心生成逻辑
  Future<void> _doGenerate(String cacheKey, AiSummaryInput input) async {
    state = const AiSummaryState(status: AiSummaryStatus.loading);

    try {
      final response = await Supabase.instance.client.functions
          .invoke(
            'ai-financial-summary',
            body: input.toJson(),
          )
          .timeout(const Duration(minutes: 5));

      final body = _decodeResponse(response.data);
      if (body == null) {
        state = const AiSummaryState(
          status: AiSummaryStatus.error,
          errorMsg: '无法解析服务端响应',
        );
        return;
      }

      if (body['error'] != null) {
        debugPrint('⚠️ AI 小结生成失败: ${body['error']}');
        state = AiSummaryState(
          status: AiSummaryStatus.error,
          errorMsg: body['error'].toString(),
        );
        return;
      }

      final summary = body['summary'] as String?;
      if (summary == null || summary.trim().isEmpty) {
        state = const AiSummaryState(
          status: AiSummaryStatus.error,
          errorMsg: 'AI 返回了空内容',
        );
        return;
      }

      // 写入缓存
      _cache[cacheKey] = _CachedSummary(
        text: summary.trim(),
        generatedAt: DateTime.now(),
      );

      state = AiSummaryState(status: AiSummaryStatus.done, text: summary.trim());
    } catch (e) {
      debugPrint('⚠️ AI 小结调用异常: $e');
      state = AiSummaryState(
        status: AiSummaryStatus.error,
        errorMsg: '生成失败: $e',
      );
    }
  }

  /// 重置状态（切换维度时调用）
  void reset() {
    state = const AiSummaryState();
  }

  /// 缓存 key：维度_开始日期_结束日期
  String _cacheKey(InsightsParams params) {
    return '${params.dimension.name}_${params.start.toIso8601String()}_${params.end.toIso8601String()}';
  }

  /// 解码 Function 返回
  Map<String, dynamic>? _decodeResponse(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    if (raw is List<int>) {
      try {
        return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

/// AI 小结 Provider（全局单例，跨维度共享缓存）
final aiSummaryProvider =
    StateNotifierProvider<AiSummaryNotifier, AiSummaryState>((ref) {
  return AiSummaryNotifier();
});
