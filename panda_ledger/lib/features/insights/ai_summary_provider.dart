import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/error_logger.dart';
import '../../core/services/text_recognition/edge_function_ai_service.dart';
import 'insights_provider.dart';

/// AI 小结生成状态
enum AiSummaryStatus { idle, loading, done, error }

// ═══════════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════════

/// 单条洞察：结论 + 数据佐证
class AiInsightItem {
  final String conclusion; // 锐利的判断（≤15字）
  final String detail;     // 数据+历史对比（自然语言）

  const AiInsightItem({required this.conclusion, required this.detail});
}

/// 最大问题聚焦（来自 B 方案）
class AiSummaryFocus {
  final String problem;    // 本期最值得关注的问题
  final String vsHistory;  // 和历史均值/上期的量化对比

  const AiSummaryFocus({required this.problem, required this.vsHistory});
}

/// AI 小结结构化结果（A+C+B 融合）
class AiSummaryResult {
  final String userTag;              // 用户消费人格标签
  final String tagDesc;              // 标签的一句话诠释
  final String opening;              // 开篇定调（C 叙事感）
  final List<AiInsightItem> insights;// 论点式洞察（A 结构）
  final AiSummaryFocus? focus;       // 最大问题聚焦（B 历史对比）
  final String advice;               // 基于目标的具体建议

  const AiSummaryResult({
    required this.userTag,
    required this.tagDesc,
    required this.opening,
    required this.insights,
    this.focus,
    required this.advice,
  });
}

// ═══════════════════════════════════════════════════════════════
// 状态
// ═══════════════════════════════════════════════════════════════

class _CachedSummary {
  final AiSummaryResult result;
  final DateTime generatedAt;
  const _CachedSummary({required this.result, required this.generatedAt});
}

class AiSummaryState {
  final AiSummaryStatus status;
  final AiSummaryResult? result;
  final String? errorMsg;

  const AiSummaryState({
    this.status = AiSummaryStatus.idle,
    this.result,
    this.errorMsg,
  });

  AiSummaryState copyWith({
    AiSummaryStatus? status,
    AiSummaryResult? result,
    String? errorMsg,
  }) =>
      AiSummaryState(
        status: status ?? this.status,
        result: result ?? this.result,
        errorMsg: errorMsg ?? this.errorMsg,
      );
}

// ═══════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════

class AiSummaryNotifier extends StateNotifier<AiSummaryState> {
  final Map<String, _CachedSummary> _cache = {};
  String? _lastPreparedKey;

  AiSummaryNotifier() : super(const AiSummaryState());

  /// 幂等准备：切换维度时自动查缓存或回 idle
  void ensurePrepared(InsightsParams params) {
    final key = _cacheKey(params);
    if (key == _lastPreparedKey) return;
    _lastPreparedKey = key;

    final cached = _cache[key];
    state = cached != null
        ? AiSummaryState(status: AiSummaryStatus.done, result: cached.result)
        : const AiSummaryState();
  }

  Future<void> generateSummary({
    required InsightsParams params,
    required AiSummaryInput input,
  }) async {
    final key = _cacheKey(params);
    final cached = _cache[key];
    if (cached != null) {
      state = AiSummaryState(status: AiSummaryStatus.done, result: cached.result);
      return;
    }
    await _doGenerate(key, input);
  }

  Future<void> regenerateSummary({
    required InsightsParams params,
    required AiSummaryInput input,
  }) async {
    final key = _cacheKey(params);
    _cache.remove(key);
    await _doGenerate(key, input);
  }

  Future<void> _doGenerate(String cacheKey, AiSummaryInput input) async {
    state = const AiSummaryState(status: AiSummaryStatus.loading);

    try {
      final response = await Supabase.instance.client.functions
          .invoke('ai-financial-summary', body: input.toJson())
          .timeout(const Duration(minutes: 5));

      final body = _decodeResponse(response.data);
      if (body == null) {
        if (cacheKey != _lastPreparedKey) return;
        state = const AiSummaryState(
          status: AiSummaryStatus.error,
          errorMsg: '无法解析服务端响应',
        );
        return;
      }

      if (body['error'] != null) {
        debugPrint('⚠️ AI 小结失败: ${body['error']}');
        if (cacheKey != _lastPreparedKey) return;
        state = AiSummaryState(
          status: AiSummaryStatus.error,
          errorMsg: body['error'].toString(),
        );
        return;
      }

      // ── 解析结构化字段 ──
      final userTag = (body['user_tag'] as String?)?.trim() ?? '';
      final tagDesc = (body['tag_desc'] as String?)?.trim() ?? '';
      final opening = (body['opening'] as String?)?.trim() ?? '';
      final advice  = (body['advice']  as String?)?.trim() ?? '';

      final rawInsights = body['insights'];
      final insights = rawInsights is List
          ? rawInsights
              .whereType<Map<String, dynamic>>()
              .map((e) => AiInsightItem(
                    conclusion: (e['conclusion'] as String?)?.trim() ?? '',
                    detail:     (e['detail']     as String?)?.trim() ?? '',
                  ))
              .where((i) => i.conclusion.isNotEmpty && i.detail.isNotEmpty)
              .toList()
          : <AiInsightItem>[];

      if (userTag.isEmpty || opening.isEmpty || insights.isEmpty || advice.isEmpty) {
        if (cacheKey != _lastPreparedKey) return;
        state = const AiSummaryState(
          status: AiSummaryStatus.error,
          errorMsg: 'AI 返回了不完整的内容',
        );
        return;
      }

      // focus 可选
      AiSummaryFocus? focus;
      final rawFocus = body['focus'];
      if (rawFocus is Map<String, dynamic>) {
        final problem    = (rawFocus['problem']    as String?)?.trim() ?? '';
        final vsHistory  = (rawFocus['vs_history'] as String?)?.trim() ?? '';
        if (problem.isNotEmpty) {
          focus = AiSummaryFocus(problem: problem, vsHistory: vsHistory);
        }
      }

      final result = AiSummaryResult(
        userTag: userTag,
        tagDesc: tagDesc,
        opening: opening,
        insights: insights,
        focus: focus,
        advice: advice,
      );

      _cache[cacheKey] = _CachedSummary(result: result, generatedAt: DateTime.now());
      // 生成期间用户可能已切换到其他维度 → 缓存保留但状态不覆盖
      if (cacheKey != _lastPreparedKey) return;
      state = AiSummaryState(status: AiSummaryStatus.done, result: result);
    } catch (e, s) {
      ErrorLogger.log('AI小结生成异常', e, s);
      debugPrint('⚠️ AI 小结异常: $e');
      // 维度已切换时，不展示旧维度的错误
      if (cacheKey != _lastPreparedKey) return;
      final errorMsg = (e is AiMembershipRequiredException ||
              e.toString().contains('MEMBERSHIP_REQUIRED'))
          ? '请先开通会员以使用 AI 小结'
          : '生成失败，请稍后重试';
      state = AiSummaryState(status: AiSummaryStatus.error, errorMsg: errorMsg);
    }
  }

  void reset() => state = const AiSummaryState();

  /// 外部触发的错误（如 prepareAiSummaryInput 异常）
  void setError(String msg) =>
      state = AiSummaryState(status: AiSummaryStatus.error, errorMsg: msg);

  String _cacheKey(InsightsParams params) =>
      '${params.dimension.name}_${params.start.toIso8601String()}_${params.end.toIso8601String()}';

  Map<String, dynamic>? _decodeResponse(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return null; }
    }
    if (raw is List<int>) {
      try { return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>; } catch (_) { return null; }
    }
    return null;
  }
}

final aiSummaryProvider =
    StateNotifierProvider<AiSummaryNotifier, AiSummaryState>(
      (_) => AiSummaryNotifier(),
    );
