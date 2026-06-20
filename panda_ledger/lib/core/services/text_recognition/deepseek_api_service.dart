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

  @override
  Future<List<ParsedTransaction>> parseBatch({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    if (userInput.trim().isEmpty) return [];

    final client = http.Client();

    try {
      final uri = Uri.parse('$baseUrl/chat/completions');

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
                  'content': _batchSystemPrompt(catList, acctList),
                },
                {
                  'role': 'user',
                  'content': userInput,
                },
              ],
              'temperature': 0.1,
              'max_tokens': 2048,
              // 注意：不设置 json_object，因为批量返回应是数组
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return [];

      final content = choices[0]['message']['content'] as String?;
      if (content == null) return [];

      return _parseBatchResponse(content);
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }

  /// 解析批量 API 返回的 JSON 数组
  List<ParsedTransaction> _parseBatchResponse(String content) {
    try {
      final decoded = jsonDecode(content);
      List<dynamic> list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map<String, dynamic>) {
        // json_object 格式下模型可能把数组包在对象里，尝试常见字段名
        final raw = decoded['transactions'] ??
            decoded['items'] ??
            decoded['results'] ??
            decoded['records'] ??
            decoded['data'];
        list = (raw is List<dynamic>) ? raw : [];
      } else {
        return [];
      }

      return list
          .map((e) => _parseResponse(jsonEncode(e), ''))
          .where((p) => p.hasPartialResult)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 构建系统提示词（单笔）
  String _systemPrompt(String catList, String acctList) {
    return '''你是一个记账助手。用户会用中文描述一笔账单，你需要提取结构化信息并返回 JSON。

## 字段说明
- type: "expense"（支出）或 "income"（收入）
- amount: 金额数字（如 32.0）
- categoryName: 不再使用此字段，始终留空
- categoryId: 不再使用此字段，始终留空
- subcategoryName: 子分类名称（二级分类），从候选列表中做语义匹配，这是最细粒度的分类
- subcategoryId: 子分类 ID（候选列表中有），对应 subcategoryName
- accountName: 账户名称，从候选列表中做语义匹配
- accountId: 账户 ID（候选列表中有），对应 accountName；匹配不到则设为 null
- note: 一句完整通顺的中文自然语言描述，概括这笔账单的关键信息（如"购买钢笔一支"、"打车去公司"、"午餐宫保鸡丁饭"），不要分词堆砌，不要只有关键词
- occurredAt: ISO 8601 日期字符串，默认今天
- matchType: "existing"（已有分类匹配）/ "suggestNew"（建议新分类）/ "partial"（部分识别）
- newCategorySuggestion: 当 matchType 为 "suggestNew" 时的建议分类名，格式为"一级分类名→二级分类名"
- confidence: 0.0~1.0 之间的置信度

## 已有分类（名称→ID映射）
$catList

## 已有账户（名称→ID映射）
$acctList

## 核心规则
1. **分类模糊匹配**：用户可能用口语化称呼（如"午饭"指"午餐"、"夜宵"指"宵夜"、"星巴克"指"咖啡"），请根据语义相似度在已有分类列表中寻找最接近的匹配，不要求字符串完全一致。只匹配到二级分类（叶子节点）。
2. **分类匹配不到**：如果找不到合适的已有分类，matchType 设为 "suggestNew"，newCategorySuggestion 格式为"一级分类名→二级分类"（如"餐饮→快餐"）。
3. **账户模糊匹配**：用户可能用简称（如"花呗"指"支付宝花呗"），请在已有账户列表中按语义匹配最近的账户。如果确实匹配不到任何已有账户，accountId 和 accountName 都设为 null（不要凭空生成账户名称）。
4. **金额转换**：金额单位如果是"万"，转换为数字（如 1万 = 10000）。
5. **备注生成**：note 必须是完整通顺的中文短句，读起来像自然的日常记账备注。例如："午餐点了一份宫保鸡丁饭，花费35元"→"午餐宫保鸡丁饭"；"昨天打车从公司回家花了32元"→"打车回家"。不要分词堆砌。
6. 只返回 JSON，不要其他文字''';
  }

  /// 构建系统提示词（批量）
  String _batchSystemPrompt(String catList, String acctList) {
    return '''你是批量记账助手。用户输入一段文本，可能包含多笔独立的收支记录。

## 工作步骤
1. **拆分**：先判断输入文本中包含几笔独立的收支事件。按消费/收入行为拆分，不要仅按标点分割。例如："中午吃饭35元，晚上看电影60元"应拆为2笔。
2. **逐笔提取**：对拆分出的每一笔，分别提取以下字段。
3. **返回**：JSON 数组 [{...}, {...}]，每笔一个对象。

## 每笔字段说明
- type: "expense"（支出）或 "income"（收入）
- amount: 金额数字（如 32.0）
- categoryName: 始终留空
- categoryId: 始终留空
- subcategoryName: 二级分类名称，从候选列表做语义匹配
- subcategoryId: 子分类 ID（候选列表中有）
- accountName: 账户名称，从候选列表语义匹配；匹配不到则设为 null
- accountId: 账户 ID，匹配不到则设为 null
- note: 完整通顺的中文短句，不是分词堆砌
- occurredAt: ISO 8601 日期字符串，默认今天
- matchType: "existing" / "suggestNew" / "partial"
- newCategorySuggestion: 当 matchType 为 "suggestNew" 时，格式"一级分类名→二级分类名"
- confidence: 0.0~1.0

## 已有分类（名称→ID映射）
$catList

## 已有账户（名称→ID映射）
$acctList

## 核心规则
1. **拆分判断**：仔细分析语义，将不同时间/场景/对象的收支事件拆开。不要合并，也不要漏掉任何一笔。
2. **分类模糊匹配**：用户可能用口语化称呼，请在已有分类列表中按语义相似度匹配最近的，不要求字符串完全一致。
3. **分类匹配不到**：matchType 设为 "suggestNew"，newCategorySuggestion 格式"一级分类名→二级分类"。
4. **账户模糊匹配**：优先在已有账户列表中匹配。如果确实匹配不到，accountId 和 accountName 设为 null。
5. **金额转换**："万"转换为数字（1万=10000）。
6. **备注生成**：每笔的 note 必须是完整通顺的中文短句。
7. 只返回 JSON 数组，不要其他文字''';
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
