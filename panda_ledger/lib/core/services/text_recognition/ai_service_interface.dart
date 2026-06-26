import 'models/parsed_transaction.dart';

/// AI 文本解析服务抽象接口
///
/// 实现类：
/// - [EdgeFunctionAiService] — 通过 Supabase Edge Function 调用 AI 解析
/// - [AiServiceStub] — 未登录时的桩实现，返回空结果
abstract class IAiParsingService {
  /// 解析用户输入的自然语言（单笔）
  ///
  /// [userInput] 用户说的或打的一句话
  /// [existingCategories] 用户当前的分类列表（名称→ID 映射），AI 优先从中匹配
  /// [existingAccounts] 用户当前的账户列表（名称→ID 映射），AI 优先从中匹配
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  });

  /// 批量解析用户输入的自然语言（多笔）
  ///
  /// AI 先判断输入文本中有几笔独立收支，拆分后再逐笔提取字段。
  /// 返回解析结果列表。
  Future<List<ParsedTransaction>> parseBatch({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  });
}
