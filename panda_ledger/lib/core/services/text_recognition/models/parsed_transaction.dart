/// AI 解析结果
///
/// 由本地规则引擎或云端 AI 服务填充。
/// 所有字段需经用户确认后才写入数据库。
class ParsedTransaction {
  /// 金额（必填）
  final double? amount;

  /// 交易类型：expense / income
  final String? type;

  /// 匹配到的已有分类 ID
  final String? categoryId;

  /// 匹配到的分类名称
  final String? categoryName;

  /// 匹配到的子分类 ID（可选）
  final String? subcategoryId;

  /// 子分类名称
  final String? subcategoryName;

  /// 推测的账户提示词
  final String? accountHint;

  /// 推测的账户 ID
  final String? accountId;

  /// 备注（提取的关键词）
  final String? note;

  /// 时间词提取
  final DateTime? occurredAt;

  /// 匹配类型
  final MatchType matchType;

  /// 当 matchType 为 suggestNew 时，建议的新分类名
  final String? newCategorySuggestion;

  /// 置信度 0.0 ~ 1.0
  final double confidence;

  /// 原始用户输入
  final String rawInput;

  const ParsedTransaction({
    this.amount,
    this.type,
    this.categoryId,
    this.categoryName,
    this.subcategoryId,
    this.subcategoryName,
    this.accountHint,
    this.accountId,
    this.note,
    this.occurredAt,
    this.matchType = MatchType.partial,
    this.newCategorySuggestion,
    this.confidence = 0.0,
    this.rawInput = '',
  });

  /// 是否所有关键字段都已被识别
  bool get isComplete =>
      amount != null && type != null && categoryId != null;

  /// 是否有部分字段被识别
  bool get hasPartialResult =>
      amount != null || categoryId != null || accountHint != null;

  /// 创建一个空结果
  factory ParsedTransaction.empty(String input) {
    return ParsedTransaction(rawInput: input, confidence: 0);
  }
}

/// 匹配类型
enum MatchType {
  /// 完全匹配已有分类
  existing,

  /// 无匹配，建议新增分类
  suggestNew,

  /// 部分字段识别，其余留空
  partial,
}
