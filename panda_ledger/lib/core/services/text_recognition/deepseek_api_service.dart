import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_service_interface.dart';
import 'models/parsed_transaction.dart';

/// DeepSeek API 服务 — 云端 LLM 智能记账解析
///
/// 调用 DeepSeek 的 [model] 模型（默认 deepseek-v4-flash）解析自然语言账单。
/// 解析结果回填到 [ParsedTransaction]，由上层组件负责表单回填。
class DeepSeekApiService implements IAiParsingService {
  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration timeout;

  const DeepSeekApiService({
    required this.apiKey,
    this.model = 'deepseek-v4-flash',
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.timeout = const Duration(seconds: 15),
  });

  @override
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) {
      return ParsedTransaction.empty(userInput);
    }

    final client = http.Client();

    try {
      final uri = Uri.parse('$baseUrl/chat/completions');

      // 构建候选列表文本
      final catList = existingCategories.entries
          .map((e) => '- ${e.key} (id: ${e.value})')
          .join('\n');
      final acctList = existingAccounts.entries
          .map((e) => '- ${e.key} (id: ${e.value})')
          .join('\n');

      final response = await client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {
                  'role': 'system',
                  'content': _systemPrompt(catList, acctList),
                },
                {
                  'role': 'user',
                  'content': userInput,
                },
              ],
              'temperature': 0.1,
              'max_tokens': 512,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        // API 返回错误时返回空结果，由上层回退到规则引擎
        return ParsedTransaction.empty(userInput);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return ParsedTransaction.empty(userInput);
      }

      final content = choices[0]['message']['content'] as String?;
      if (content == null) {
        return ParsedTransaction.empty(userInput);
      }

      return _parseResponse(content, userInput);
    } catch (_) {
      // 网络异常、超时、JSON 解析失败等均返回空结果，由上层回退到规则引擎
      return ParsedTransaction.empty(userInput);
    } finally {
      client.close();
    }
  }

  /// 构建系统提示词
  String _systemPrompt(String catList, String acctList) {
    return '''你是一个记账助手。用户会用中文描述一笔账单，你需要提取结构化信息并返回 JSON。

## 字段说明
- type: "expense"（支出）或 "income"（收入）
- amount: 金额数字（如 32.0）
- categoryName: 不再使用此字段，始终留空
- categoryId: 不再使用此字段，始终留空
- subcategoryName: 子分类名称（二级分类），从候选列表中做语义匹配，这是最细粒度的分类
- subcategoryId: 子分类 ID（候选列表中有），对应 subcategoryName
- accountName: 账户名称，优先从候选列表中选择
- accountId: 账户 ID（候选列表中有）
- note: 一句完整通顺的中文自然语言描述，概括这笔账单的关键信息（如"购买钢笔一支"、"打车去公司"、"午餐点了一份宫保鸡丁饭"），不要分词堆砌，不要只有关键词
- occurredAt: ISO 8601 日期字符串（如 "2026-06-19"），默认今天
- matchType: "existing"（已有分类匹配）/ "suggestNew"（建议新分类）/ "partial"（部分识别）
- newCategorySuggestion: 当 matchType 为 "suggestNew" 时的建议分类名，格式为"一级分类名→二级分类名"
- confidence: 0.0~1.0 之间的置信度

## 已有分类（名称→ID映射）
$catList

## 已有账户（名称→ID映射）
$acctList

## 规则
1. **分类匹配规则**：只应匹配到二级分类（叶子节点），categoryName 和 categoryId 始终留空，在 subcategoryName 和 subcategoryId 中填入最细粒度的分类
2. 如果没有合适的已有分类，设置 matchType 为 "suggestNew" 并在 newCategorySuggestion 中填入建议的分类名（格式："一级分类→二级分类"，如"餐饮→快餐"）
3. 金额单位如果是"万"，转换为数字（如 1万 = 10000）
4. **备注生成规则**：note 字段必须是完整通顺的中文短句，不是分词列表。例如："午餐点了一份宫保鸡丁饭，花费35元"提取为"午餐宫保鸡丁饭"；"昨天打车从公司回家花了32元"提取为"打车回家"。备注读起来应该像一句自然的日常记账备注
5. 只返回 JSON，不要其他文字''';
  }

  /// 解析 API 返回的 JSON 内容
  ParsedTransaction _parseResponse(String content, String userInput) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;

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
        confidence: ((json['confidence'] as num?)?.toDouble() ?? 0.5)
            .clamp(0.0, 1.0),
        rawInput: userInput,
      );
    } catch (_) {
      return ParsedTransaction.empty(userInput);
    }
  }
}
