import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/parsed_transaction.dart';
import 'ai_service_interface.dart';
import 'ai_service_stub.dart';
import 'edge_function_ai_service.dart';

/// AI 服务 Provider
///
/// 通过 Supabase Edge Function `ai-parse-record` 代理调用 AI 平台。
/// Key 存储在 Supabase Secrets 中，不再暴露于客户端代码。
///
/// 未登录时回退到桩实现（返回空结果，提示用户登录）。
final aiServiceProvider = Provider<IAiParsingService>((ref) {
  final isLoggedIn = Supabase.instance.client.auth.currentSession != null;
  if (!isLoggedIn) {
    return AiServiceStub();
  }
  return const EdgeFunctionAiService();
});

/// 文字识别服务 — 直接调用 AI 解析
final textRecognitionProvider = Provider<TextRecognitionService>((ref) {
  return TextRecognitionService(
    aiService: ref.watch(aiServiceProvider),
  );
});

class TextRecognitionService {
  final IAiParsingService aiService;

  TextRecognitionService({
    required this.aiService,
  });

  /// 解析用户输入（单笔）
  ///
  /// 直接调用 AI 解析，不再使用本地规则引擎兜底。
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) {
      return ParsedTransaction.empty(userInput);
    }

    try {
      final result = await aiService.parse(
        userInput: userInput,
        existingCategories: existingCategories,
        existingAccounts: existingAccounts,
      );
      return result;
    } catch (e) {
      // AI 调用失败时返回空结果，由 UI 层提示用户手动填写
      return ParsedTransaction.empty(userInput);
    }
  }

  /// 批量解析（一口气记账）
  ///
  /// 直接调用 AI 批量解析，不再使用本地规则引擎兜底。
  Future<List<ParsedTransaction>> parseBatch({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) return [];

    try {
      final results = await aiService.parseBatch(
        userInput: userInput,
        existingCategories: existingCategories,
        existingAccounts: existingAccounts,
      );
      return results;
    } catch (e) {
      // AI 调用失败时返回空列表，由 UI 层提示用户手动填写
      return [];
    }
  }
}
