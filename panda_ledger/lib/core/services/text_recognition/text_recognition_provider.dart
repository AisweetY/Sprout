import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/auth/auth_provider.dart';
import 'models/parsed_transaction.dart';
import 'ai_service_interface.dart';
import 'ai_service_stub.dart';
import 'edge_function_ai_service.dart';

/// AI 服务 Provider（响应式，三重保护）
///
/// **方案一（预热）**：认证成功时在后台触发 preheat()，唤醒 Edge Function 冷启动。
///
/// **方案三（修复 auth 竞态）**：
/// `authStateProvider` 基于 `onAuthStateChange` 流，该流在初次订阅时可能短暂
/// 发出 session=null 事件（Token 刷新过渡期），导致 Provider 瞬间切回 AiServiceStub，
/// 用户此时调用 AI 得到空结果。
///
/// 修复：双重判断——
/// 1. `authStateProvider` 仍订阅（保证真正登出时能切回 Stub）
/// 2. 当 authStatus 为非 authenticated 时，**再用 Supabase SDK 直读 currentSession 兜底**
///    SDK 的内存缓存不受流事件抖动影响，避免误判为未登录
final aiServiceProvider = Provider<IAiParsingService>((ref) {
  final authStatus = ref.watch(authStateProvider);

  // 方案三核心：authStateProvider 短暂处于非 authenticated 时，
  // 用 SDK 直读内存 session 兜底，防止竞态导致误返回 AiServiceStub
  final hasLiveSession =
      Supabase.instance.client.auth.currentSession != null;

  if (authStatus != AuthStatus.authenticated && !hasLiveSession) {
    return AiServiceStub();
  }

  const service = EdgeFunctionAiService();
  // 方案一：异步预热，不阻塞 Provider 返回，不影响任何 UI
  service.preheat();
  return service;
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
