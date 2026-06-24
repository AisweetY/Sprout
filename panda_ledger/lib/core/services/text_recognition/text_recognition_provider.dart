import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/auth_provider.dart';
import 'models/parsed_transaction.dart';
import 'ai_service_interface.dart';
import 'ai_service_stub.dart';
import 'edge_function_ai_service.dart';

/// AI 服务 Provider（响应式）
///
/// 监听 authStateProvider，认证状态变化时自动切换实现：
/// - 已登录 → EdgeFunctionAiService（通过 Supabase Edge Function 调 AI）
/// - 未登录 → AiServiceStub（空实现，上层会在调用前先通过会员门禁）
///
/// 使用 ref.watch 而非直接读 currentSession，确保冷启动 / 后台恢复时
/// session 就绪后 Provider 能自动重建，不再永久返回 Stub。
final aiServiceProvider = Provider<IAiParsingService>((ref) {
  final authStatus = ref.watch(authStateProvider);
  if (authStatus != AuthStatus.authenticated) {
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
  /// 直接调用 AI 解析，不再吞掉异常——上层需自行处理：
  ///   AiMembershipRequiredException → 引导开通会员
  ///   AiAuthExpiredException        → 提示重新登录
  ///   其他异常                       → 降级为空结果
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) {
      return ParsedTransaction.empty(userInput);
    }
    // 不再 catch——语义异常（401/402）必须让上层感知
    return await aiService.parse(
      userInput: userInput,
      existingCategories: existingCategories,
      existingAccounts: existingAccounts,
    );
  }

  /// 批量解析（AI 记账）
  ///
  /// 同上，不再吞掉语义异常。
  Future<List<ParsedTransaction>> parseBatch({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) return [];
    return await aiService.parseBatch(
      userInput: userInput,
      existingCategories: existingCategories,
      existingAccounts: existingAccounts,
    );
  }
}
