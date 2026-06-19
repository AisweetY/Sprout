import 'models/parsed_transaction.dart';
import 'ai_service_interface.dart';

/// AI 服务桩实现
///
/// 当前版本不调用云端 LLM，直接返回低置信度空结果。
/// 后续替换为真实 AI 服务（如 Claude API）时，只需替换此实现即可。
class AiServiceStub implements IAiParsingService {
  @override
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    // 桩实现：不做任何解析，全部交给本地规则引擎处理
    return ParsedTransaction.empty(userInput);
  }
}
