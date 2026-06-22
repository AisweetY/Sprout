import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      final response = await Supabase.instance.client.functions
          .invoke(
            _functionName,
            body: {
              'mode': 'single',
              'input_text': userInput.trim(),
              'today': _todayString(), // 传入本地今日日期，用于 AI 换算相对时间词
            },
          )
          .timeout(timeout);

      // response.data 是 Edge Function 返回的 JSON body
      final body = _decodeResponse(response.data);
      if (body == null) {
        return ParsedTransaction.empty(userInput);
      }

      // 检查是否返回了错误
      if (body['error'] != null) {
        debugPrint('⚠️ Edge Function 返回错误: ${body['error']}');
        return ParsedTransaction.empty(userInput);
      }

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) {
        return ParsedTransaction.empty(userInput);
      }

      return _parseSingleResult(data, userInput);
    } catch (e) {
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
      final response = await Supabase.instance.client.functions
          .invoke(
            _functionName,
            body: {
              'mode': 'batch',
              'input_text': userInput.trim(),
              'today': _todayString(), // 传入本地今日日期，用于 AI 换算相对时间词
            },
          )
          .timeout(timeout);

      final body = _decodeResponse(response.data);
      if (body == null) return [];

      if (body['error'] != null) {
        debugPrint('⚠️ Edge Function 返回错误: ${body['error']}');
        return [];
      }

      final data = body['data'];
      if (data is! List) return [];

      return data
          .map((e) => _parseSingleResult(e as Map<String, dynamic>?, ''))
          .where((p) => p.hasPartialResult)
          .toList();
    } catch (e) {
      debugPrint('⚠️ Edge Function 批量调用失败: $e');
      return [];
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
