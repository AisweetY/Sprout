import 'models/parsed_transaction.dart';
import 'ai_service_interface.dart';

/// 本地规则引擎
///
/// 纯本地正则匹配，无需网络，50ms 内完成。
/// 覆盖常见简短表达，不覆盖的边缘情况留空让用户手动补全。
/// 场景匹配结果
class _SceneMatch {
  final String parent;
  final String? sub;
  const _SceneMatch({required this.parent, this.sub});
}

class RuleEngine implements IAiParsingService {
  // ── 时间词 → 偏移天数 ──
  static const _timeOffsets = {
    '今天': 0,
    '刚才': 0,
    '刚': 0,
    '昨天': -1,
    '前天': -2,
    '大前天': -3,
    '明天': 1, // 极少用，但保留
  };

  // ── 场景词 → (一级分类, 二级分类?) ──
  // 子分类名需与 DefaultCategories.subcategories 种子数据对齐
  static const _sceneToCategory = <String, _SceneMatch>{
    // 餐饮 — 子分类: 工作餐, 外卖, 请客, 买菜
    '午饭': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '晚饭': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '早餐': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '午餐': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '晚餐': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '吃饭': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '外卖': _SceneMatch(parent: '餐饮', sub: '外卖'),
    '聚餐': _SceneMatch(parent: '餐饮', sub: '请客'),
    '请客': _SceneMatch(parent: '餐饮', sub: '请客'),
    '买菜': _SceneMatch(parent: '餐饮', sub: '买菜'),
    '食堂': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '咖啡': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '奶茶': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '饮料': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '水果': _SceneMatch(parent: '餐饮', sub: '买菜'),
    '零食': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '宵夜': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '夜宵': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '星巴克': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    '面包': _SceneMatch(parent: '餐饮', sub: '工作餐'),
    // 交通 — 子分类: 地铁, 打车, 加油, 停车
    '打车': _SceneMatch(parent: '交通', sub: '打车'),
    '地铁': _SceneMatch(parent: '交通', sub: '地铁'),
    '公交': _SceneMatch(parent: '交通', sub: '地铁'),
    '加油': _SceneMatch(parent: '交通', sub: '加油'),
    '停车': _SceneMatch(parent: '交通', sub: '停车'),
    '出租车': _SceneMatch(parent: '交通', sub: '打车'),
    '滴滴': _SceneMatch(parent: '交通', sub: '打车'),
    '高铁': _SceneMatch(parent: '交通', sub: '打车'),
    '火车': _SceneMatch(parent: '交通', sub: '打车'),
    '机票': _SceneMatch(parent: '交通', sub: '打车'),
    '飞机': _SceneMatch(parent: '交通', sub: '打车'),
    // 购物 — 子分类: 日用品, 服装, 数码, 家居
    '买': _SceneMatch(parent: '购物'),
    '淘宝': _SceneMatch(parent: '购物', sub: '数码'),
    '京东': _SceneMatch(parent: '购物', sub: '数码'),
    '拼多多': _SceneMatch(parent: '购物', sub: '日用品'),
    '超市': _SceneMatch(parent: '购物', sub: '日用品'),
    '快递': _SceneMatch(parent: '购物'),
    '衣服': _SceneMatch(parent: '购物', sub: '服装'),
    '裤子': _SceneMatch(parent: '购物', sub: '服装'),
    '鞋子': _SceneMatch(parent: '购物', sub: '服装'),
    // 娱乐 — 子分类: 电影, 游戏, 旅行, 运动
    '电影': _SceneMatch(parent: '娱乐', sub: '电影'),
    '游戏': _SceneMatch(parent: '娱乐', sub: '游戏'),
    'KTV': _SceneMatch(parent: '娱乐', sub: '电影'),
    '唱歌': _SceneMatch(parent: '娱乐', sub: '电影'),
    '旅游': _SceneMatch(parent: '娱乐', sub: '旅行'),
    '门票': _SceneMatch(parent: '娱乐', sub: '旅行'),
    '运动': _SceneMatch(parent: '娱乐', sub: '运动'),
    // 居住 — 子分类: 房租, 水电, 物业, 维修
    '房租': _SceneMatch(parent: '居住', sub: '房租'),
    '水电': _SceneMatch(parent: '居住', sub: '水电'),
    '物业': _SceneMatch(parent: '居住', sub: '物业'),
    '电费': _SceneMatch(parent: '居住', sub: '水电'),
    '水费': _SceneMatch(parent: '居住', sub: '水电'),
    '燃气': _SceneMatch(parent: '居住', sub: '水电'),
    // 健康 — 子分类: 看病, 药品, 健身, 体检
    '看病': _SceneMatch(parent: '健康', sub: '看病'),
    '药品': _SceneMatch(parent: '健康', sub: '药品'),
    '药': _SceneMatch(parent: '健康', sub: '药品'),
    '医院': _SceneMatch(parent: '健康', sub: '看病'),
    '健身': _SceneMatch(parent: '健康', sub: '健身'),
    '体检': _SceneMatch(parent: '健康', sub: '体检'),
  };

  // ── 支付方式词 → 账户提示 ──
  static const _paymentToAccount = {
    '支付宝': '支付宝',
    '微信': '微信',
    '花呗': '花呗',
    '信用卡': '信用卡',
    '招行': '招商银行',
    '工行': '工商银行',
    '建行': '建设银行',
    '农行': '农业银行',
    '中国银行': '中国银行',
    '储蓄卡': '储蓄卡',
    '银联': '银联',
  };

  @override
  Future<ParsedTransaction> parse({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    double? amount;
    String? type;
    String? categoryName;
    String? categoryId;
    DateTime? occurredAt;
    String? accountHint;
    String? accountId;
    String? note;
    MatchType matchType = MatchType.partial;
    double confidence = 0.0;

    final input = userInput.trim();
    if (input.isEmpty) {
      return ParsedTransaction.empty(input);
    }

    // 1. 提取金额
    amount = _extractAmount(input);
    if (amount != null) confidence += 0.4;

    // 2. 判断类型
    type = _inferType(input);
    if (type != null) confidence += 0.1;

    // 3. 提取场景词 → 分类
    String? subcategoryName;
    String? subcategoryId;
    final sceneResult = _matchScene(input);
    if (sceneResult != null) {
      categoryName = sceneResult.parent;
      subcategoryName = sceneResult.sub;

      // 优先匹配已有分类（精确匹配二级 → 一级）
      if (subcategoryName != null && existingCategories.containsKey(subcategoryName)) {
        subcategoryId = existingCategories[subcategoryName];
        // 二级匹配成功，还需要匹配一级
        if (existingCategories.containsKey(categoryName)) {
          categoryId = existingCategories[categoryName];
        }
        matchType = MatchType.existing;
        confidence += 0.3;
      } else if (existingCategories.containsKey(categoryName)) {
        categoryId = existingCategories[categoryName];
        matchType = MatchType.existing;
        confidence += 0.3;
      } else {
        // 尝试模糊匹配已有分类
        final matched = _fuzzyMatchCategory(categoryName, existingCategories);
        if (matched != null) {
          categoryName = matched['name'];
          categoryId = matched['id'];
          matchType = MatchType.existing;
          confidence += 0.2;
        } else {
          matchType = MatchType.suggestNew;
          confidence += 0.1;
        }
      }
    }

    // 4. 提取支付方式 → 账户
    accountHint = _matchPaymentMethod(input);
    if (accountHint != null) {
      // 尝试匹配已有账户
      if (existingAccounts.containsKey(accountHint)) {
        accountId = existingAccounts[accountHint];
      } else {
        // 模糊匹配
        final matched = _fuzzyMatchAccount(accountHint, existingAccounts);
        if (matched != null) {
          accountHint = matched['name'];
          accountId = matched['id'];
        }
      }
      confidence += 0.15;
    }

    // 5. 提取时间词
    occurredAt = _extractTime(input);

    // 6. 提取备注（去除金额和关键词后的剩余文字）
    note = _extractNote(input);

    return ParsedTransaction(
      amount: amount,
      type: type ?? 'expense', // 默认支出
      categoryId: categoryId,
      categoryName: categoryName,
      subcategoryId: subcategoryId,
      subcategoryName: subcategoryName,
      accountHint: accountHint,
      accountId: accountId,
      note: note,
      occurredAt: occurredAt,
      matchType: matchType,
      newCategorySuggestion: matchType == MatchType.suggestNew ? categoryName : null,
      confidence: confidence.clamp(0.0, 1.0),
      rawInput: input,
    );
  }

  /// 提取金额
  double? _extractAmount(String input) {
    // 匹配数字+可选单位
    final pattern = RegExp(r'(\d+\.?\d{0,2})\s*[元块钱]?');
    final match = pattern.firstMatch(input);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// 判断类型（默认为支出）
  String? _inferType(String input) {
    // 收入关键词
    const incomeKeywords = ['工资', '奖金', '报销', '退款', '红包', '收', '到账', '入账'];
    for (final kw in incomeKeywords) {
      if (input.contains(kw)) return 'income';
    }
    return 'expense';
  }

  /// 场景词匹配分类名（返回一级+可选二级）
  _SceneMatch? _matchScene(String input) {
    for (final entry in _sceneToCategory.entries) {
      if (input.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// 模糊匹配已有分类
  Map<String, String>? _fuzzyMatchCategory(
    String name,
    Map<String, String> existing,
  ) {
    // 直接包含匹配
    for (final entry in existing.entries) {
      if (entry.key.contains(name) || name.contains(entry.key)) {
        return {'name': entry.key, 'id': entry.value};
      }
    }
    return null;
  }

  /// 提取支付方式
  String? _matchPaymentMethod(String input) {
    for (final entry in _paymentToAccount.entries) {
      if (input.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// 模糊匹配已有账户
  Map<String, String>? _fuzzyMatchAccount(
    String hint,
    Map<String, String> existing,
  ) {
    for (final entry in existing.entries) {
      if (entry.key.contains(hint) || hint.contains(entry.key)) {
        return {'name': entry.key, 'id': entry.value};
      }
    }
    return null;
  }

  /// 提取时间词
  DateTime? _extractTime(String input) {
    for (final entry in _timeOffsets.entries) {
      if (input.contains(entry.key)) {
        return DateTime.now().add(Duration(days: entry.value));
      }
    }
    return null; // 默认今天
  }

  /// 提取备注：移除金额和已知关键词后的残文
  String? _extractNote(String input) {
    var note = input;
    // 移除金额部分
    note = note.replaceAll(RegExp(r'\d+\.?\d{0,2}\s*[元块钱]?'), '');
    // 移除支付方式
    for (final kw in _paymentToAccount.keys) {
      note = note.replaceAll(kw, '');
    }
    // 移除时间词
    for (final kw in _timeOffsets.keys) {
      note = note.replaceAll(kw, '');
    }
    // 移除场景词
    for (final kw in _sceneToCategory.keys) {
      note = note.replaceAll(kw, '');
    }

    note = note.trim();
    // 清理常见冗余词
    note = note.replaceAll(RegExp(r'[花费了用]'), '').trim();

    return note.isEmpty ? null : note;
  }

  @override
  Future<List<ParsedTransaction>> parseBatch({
    required String userInput,
    required Map<String, String> existingCategories,
    required Map<String, String> existingAccounts,
  }) async {
    // 按换行、中文句号、分号分割
    final chunks = userInput
        .split(RegExp(r'[。；\n;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final results = <ParsedTransaction>[];
    for (final chunk in chunks) {
      // 尝试进一步分割（如"吃饭30，坐车5元"）
      final subChunks = _splitByCommaOrAmount(chunk);
      for (final sub in subChunks) {
        final result = await parse(
          userInput: sub,
          existingCategories: existingCategories,
          existingAccounts: existingAccounts,
        );
        if (result.hasPartialResult) {
          results.add(result);
        }
      }
    }
    return results;
  }

  /// 按逗号或金额特征进一步拆分子句
  static List<String> _splitByCommaOrAmount(String text) {
    final parts = text.split(RegExp(r'[，,]'));
    if (parts.length > 1) {
      return parts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [text];
  }
}
