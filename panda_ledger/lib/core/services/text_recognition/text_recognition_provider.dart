import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/parsed_transaction.dart';
import 'rule_engine.dart';
import 'ai_service_interface.dart';
import 'ai_service_stub.dart';
import 'deepseek_api_service.dart';

/// 规则引擎 Provider（单例）
final ruleEngineProvider = Provider<RuleEngine>((ref) => RuleEngine());

/// AI 服务 Provider
///
/// 使用 DeepSeek API。API Key 通过编译时环境变量 `DEEPSEEK_API_KEY` 传入：
///   flutter run --dart-define=DEEPSEEK_API_KEY=sk-xxx
///
/// 未配置 Key 时自动回退到桩实现（仅规则引擎生效）。
final aiServiceProvider = Provider<IAiParsingService>((ref) {
  const apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
  if (apiKey.isEmpty) {
    return AiServiceStub();
  }
  return DeepSeekApiService(apiKey: apiKey);
});

/// 文字识别服务 — 组合规则引擎 + AI 兜底
final textRecognitionProvider = Provider<TextRecognitionService>((ref) {
  return TextRecognitionService(
    ruleEngine: ref.watch(ruleEngineProvider),
    aiService: ref.watch(aiServiceProvider),
  );
});

class TextRecognitionService {
  final RuleEngine ruleEngine;
  final IAiParsingService aiService;

  TextRecognitionService({
    required this.ruleEngine,
    required this.aiService,
  });

  /// 解析用户输入
  ///
  /// 策略：本地规则引擎优先 → AI 兜底（仅当置信度不足时）
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    // 第一层：本地规则引擎
    final localResult = await ruleEngine.parse(
      userInput: userInput,
      existingCategories: existingCategories,
      existingAccounts: existingAccounts,
    );

    // 如果本地引擎置信度足够高，直接返回
    if (localResult.confidence >= 0.6 && localResult.amount != null) {
      return localResult;
    }

    // 第二层：AI 兜底（当前为桩实现，返回低置信度结果）
    // 未来：调用真实 AI 服务，将已有分类列表作为上下文传递
    final aiResult = await aiService.parse(
      userInput: userInput,
      existingCategories: existingCategories,
      existingAccounts: existingAccounts,
    );

    // 合并结果：优先取 AI 的字段，缺失则用本地引擎的
    return ParsedTransaction(
      amount: aiResult.amount ?? localResult.amount,
      type: aiResult.type ?? localResult.type,
      categoryId: aiResult.categoryId ?? localResult.categoryId,
      categoryName: aiResult.categoryName ?? localResult.categoryName,
      subcategoryId: aiResult.subcategoryId ?? localResult.subcategoryId,
      subcategoryName: aiResult.subcategoryName ?? localResult.subcategoryName,
      accountHint: aiResult.accountHint ?? localResult.accountHint,
      accountId: aiResult.accountId ?? localResult.accountId,
      note: aiResult.note ?? localResult.note,
      occurredAt: aiResult.occurredAt ?? localResult.occurredAt,
      matchType: aiResult.confidence > localResult.confidence
          ? aiResult.matchType
          : localResult.matchType,
      newCategorySuggestion:
          aiResult.newCategorySuggestion ?? localResult.newCategorySuggestion,
      confidence: aiResult.confidence > localResult.confidence
          ? aiResult.confidence
          : localResult.confidence,
      rawInput: userInput,
    );
  }
}
