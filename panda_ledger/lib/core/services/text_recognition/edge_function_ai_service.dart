import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/error_logger.dart';
import 'ai_service_interface.dart';
import 'models/parsed_transaction.dart';

/// 通过 Supabase Edge Function 代理调用 AI 服务
///
/// 不再直接调用 DeepSeek API，而是调用部署在 Supabase 项目中的
/// `ai-parse-record` Edge Function，由服务端持有 Key 并代理请求。
///
/// Edge Function 内部：
/// 1. 校验 JWT 身份
/// 2. 读 ai_provider_configs 表获取当前生效的平台配置
/// 3. 从 Supabase Secrets 取出对应 API Key
/// 4. 查询该用户真实的账户/分类列表作为匹配上下文
/// 5. 调用 AI 平台完成解析
/// 6. 返回结构化 JSON
class EdgeFunctionAiService implements IAiParsingService {
  /// Edge Function 名称
  static const _functionName = 'ai-parse-record';

  /// 单笔识别超时
  final Duration timeout;

  const EdgeFunctionAiService({
    this.timeout = const Duration(seconds: 30),
  });

  /// 确保 JWT 未过期，快到期时主动刷新
  ///
  /// 应用从后台恢复时 JWT 可能已过期但 supabase_flutter 刷新还未完成，
  /// 在发起 Edge Function 调用之前主动刷新，避免 401 被当成「识别失败」静默丢弃。
  Future<void> _ensureFreshSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final expiresAtSecs = session.expiresAt;
    if (expiresAtSecs == null) return;
    // expiresAt 是 Unix 秒时间戳
    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(expiresAtSecs * 1000);
    // 距离过期不足 60 秒则主动刷新
    if (expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 60)))) {
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (e, s) {
        ErrorLogger.log('JWT刷新失败', e, s);
        // 刷新失败不阻断——让后续调用正常失败并抛出，由上层处理
      }
    }
  }

  /// 预热：登录后在后台调用一次，唤醒 Supabase Edge Function
  ///
  /// Edge Function 在 Deno Deploy 上有冷启动延迟，长时间未调用后第一次
  /// 请求会失败或超时。此方法在用户认证成功后立即触发（异步、忽略结果），
  /// 使函数保持"热"状态，保证用户首次使用 AI 记账时第一次调用成功。
  Future<void> preheat() async {
    try {
      await _ensureFreshSession();
      // 使用 ping 模式：空 input_text，Edge Function 会提前返回，不调用 LLM
      await Supabase.instance.client.functions
          .invoke(
            _functionName,
            body: {'mode': 'ping', 'input_text': '', 'today': ''},
          )
          .timeout(const Duration(seconds: 20));
    } catch (e, s) {
      ErrorLogger.log('Edge Function预热失败', e, s);
      // 预热失败不影响任何功能，静默忽略
    }
  }

  /// 将 DateTime 格式化为 YYYY-MM-DD 字符串（本地时区）
  String _todayString() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) {
      return ParsedTransaction.empty(userInput);
    }

    try {
      await _ensureFreshSession();

      final response = await Supabase.instance.client.functions
          .invoke(
            _functionName,
            body: {
              'mode': 'single',
              'input_text': userInput.trim(),
              'today': _todayString(),
            },
          )
          .timeout(timeout);

      final body = _decodeResponse(response.data);
      if (body == null) {
        return ParsedTransaction.empty(userInput);
      }

      if (body['error'] != null) {
        _throwIfAuthOrMembership(body['error'].toString());
        debugPrint('⚠️ Edge Function 返回错误: ${body['error']}');
        return ParsedTransaction.empty(userInput);
      }

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) {
        return ParsedTransaction.empty(userInput);
      }

      return _parseSingleResult(data, userInput);
    } catch (e, s) {
      _rethrowIfAuthOrMembership(e);
      ErrorLogger.log('Edge Function调用失败', e, s);
      debugPrint('⚠️ Edge Function 调用失败: $e');
      return ParsedTransaction.empty(userInput);
    }
  }

  @override
  Future<List<ParsedTransaction>> parseBatch({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) return [];

    try {
      await _ensureFreshSession();

      final response = await Supabase.instance.client.functions
          .invoke(
            _functionName,
            body: {
              'mode': 'batch',
              'input_text': userInput.trim(),
              'today': _todayString(),
            },
          )
          .timeout(timeout);

      final body = _decodeResponse(response.data);
      if (body == null) return [];

      if (body['error'] != null) {
        _throwIfAuthOrMembership(body['error'].toString());
        debugPrint('⚠️ Edge Function 返回错误: ${body['error']}');
        return [];
      }

      final data = body['data'];
      if (data is! List) return [];

      return data
          .map((e) => _parseSingleResult(e as Map<String, dynamic>?, ''))
          .where((p) => p.hasPartialResult)
          .toList();
    } catch (e, s) {
      _rethrowIfAuthOrMembership(e);
      ErrorLogger.log('Edge Function批量调用失败', e, s);
      debugPrint('⚠️ Edge Function 批量调用失败: $e');
      return [];
    }
  }

  /// body['error'] 包含 401/402 语义时向上抛，其余静默降级
  void _throwIfAuthOrMembership(String error) {
    if (error == 'MEMBERSHIP_REQUIRED') {
      throw const AiMembershipRequiredException();
    }
    if (error.contains('登录') || error.contains('身份校验') ||
        error.contains('UNAUTHORIZED')) {
      throw AiAuthExpiredException(error);
    }
  }

  /// catch 到的异常中：已经是我们的语义异常则直接 rethrow
  void _rethrowIfAuthOrMembership(Object e) {
    if (e is AiMembershipRequiredException || e is AiAuthExpiredException) {
      throw e;
    }
    // supabase_flutter 部分版本对 402 抛 FunctionsException
    final msg = e.toString().toLowerCase();
    if (msg.contains('membership_required')) {
      throw const AiMembershipRequiredException();
    }
    if (msg.contains('401') || msg.contains('unauthorized') ||
        msg.contains('身份校验')) {
      throw AiAuthExpiredException(e.toString());
    }
  }

  /// 解码函数响应（可能是 String 或 Map）
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
    // 有时 supabase_flutter 返回的是 List<int>（原始字节）
    if (raw is List<int>) {
      try {
        return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 解析单条 AI 结果

  ParsedTransaction _parseSingleResult(
    Map<String, dynamic>? json,
    String userInput,
  ) {
    if (json == null) return ParsedTransaction.empty(userInput);

    DateTime? occurredAt;
    if (json['occurredAt'] != null) {
      occurredAt = DateTime.tryParse(json['occurredAt'].toString());
    }

    final matchTypeStr = json['matchType'] as String? ?? 'partial';
    final matchType = switch (matchTypeStr) {
      'existing' => MatchType.existing,
      'suggestNew' => MatchType.suggestNew,
      _ => MatchType.partial,
    };

    return ParsedTransaction(
      amount: (json['amount'] as num?)?.toDouble(),
      type: json['type'] as String?,
      categoryId: json['categoryId'] as String?,
      categoryName: json['categoryName'] as String?,
      subcategoryId: json['subcategoryId'] as String?,
      subcategoryName: json['subcategoryName'] as String?,
      accountHint: json['accountName'] as String?,
      accountId: json['accountId'] as String?,
      note: json['note'] as String?,
      occurredAt: occurredAt,
      matchType: matchType,
      newCategorySuggestion: json['newCategorySuggestion'] as String?,
      confidence:
          ((json['confidence'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
      rawInput: userInput,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// AI 语义异常（供上层区分错误类型，给出有针对性的提示）
// ─────────────────────────────────────────────────────────────────────

/// 会员未开通或已过期：需要引导用户进入会员中心
class AiMembershipRequiredException implements Exception {
  const AiMembershipRequiredException();
  @override
  String toString() => 'AI 功能需要开通会员';
}

/// JWT 已过期 / 未认证：需要重新登录
class AiAuthExpiredException implements Exception {
  final String detail;
  const AiAuthExpiredException(this.detail);
  @override
  String toString() => '登录状态已过期，请重新登录';
}
