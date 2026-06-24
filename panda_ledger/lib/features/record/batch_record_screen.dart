import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/text_recognition/edge_function_ai_service.dart';
import '../../core/services/text_recognition/models/parsed_transaction.dart';
import '../../core/services/text_recognition/text_recognition_provider.dart';
import '../membership/membership_provider.dart';
import '../../core/utils/id_generator.dart';
import '../../core/widgets/record_card.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/repository/account_repository.dart';
import '../../data/repository/record_repository.dart';
import '../auth/auth_provider.dart';
import '../home/home_provider.dart';
import '../insights/insights_provider.dart';
import '../assets/assets_provider.dart';
import 'record_screen.dart';

/// AI 记账 —— 批量 AI 识别 + 卡片交互 + 批量保存
class BatchRecordScreen extends ConsumerStatefulWidget {
  const BatchRecordScreen({super.key});

  @override
  ConsumerState<BatchRecordScreen> createState() => _BatchRecordScreenState();
}

/// 可编辑的卡片数据
class _BatchCard {
  final String id; // 本地临时 ID
  final ParsedTransaction parsed;
  bool selected; // 是否选中

  _BatchCard({required this.id, required this.parsed, this.selected = true});
}

class _BatchRecordScreenState extends ConsumerState<BatchRecordScreen> {
  static const _draftKey = 'batch_record_draft';
  final _textCtrl = TextEditingController();
  final List<_BatchCard> _cards = [];
  bool _parsing = false;
  bool _saving = false;
  String? _errorMsg;
  Timer? _draftTimer;

  // 分类 / 账户映射
  Map<String, String> _catMap = {};
  Map<String, String> _acctMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMaps());
    _restoreDraft();
    _textCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  /// 恢复上次未发送的草稿
  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(_draftKey);
    if (draft != null && draft.isNotEmpty && mounted) {
      _textCtrl.text = draft;
    }
  }

  /// 文本变化时防抖保存草稿（500ms）
  void _onTextChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, _textCtrl.text);
    });
  }

  /// 清除草稿（解析或保存成功后调用）
  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  Future<void> _loadMaps() async {
    final catDao = ref.read(categoryDaoProvider);
    final acctRepo = ref.read(accountRepositoryProvider);
    final cats = await catDao.getActiveCategories();
    final accts = await acctRepo.getActiveAccounts();

    final catMap = <String, String>{};
    for (final c in cats) {
      catMap[c.name] = c.id;
    }
    final acctMap = <String, String>{};
    for (final a in accts) {
      acctMap[a.name] = a.id;
    }
    if (mounted) {
      setState(() {
        _catMap = catMap;
        _acctMap = acctMap;
      });
    }
  }

  Future<void> _parse() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _parsing = true;
      _errorMsg = null;
    });

    try {
      debugPrint('🔍 [batch] 开始解析: "$text"');
      debugPrint('🔍 [batch] 分类映射 ${_catMap.length} 条, 账户映射 ${_acctMap.length} 条');

      final service = ref.read(textRecognitionProvider);
      final results = await service.parseBatch(
        userInput: text,
        existingCategories: _catMap,
        existingAccounts: _acctMap,
      );

      debugPrint('🔍 [batch] 解析完成, 获得 ${results.length} 条结果');
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        debugPrint('🔍 [batch]   结果$i: amount=${r.amount}, type=${r.type}, '
            'catId=${r.categoryId}, subCatId=${r.subcategoryId}, '
            'subCatName=${r.subcategoryName}, accountId=${r.accountId}, '
            'accountHint=${r.accountHint}, note=${r.note}, '
            'occurredAt=${r.occurredAt}, confidence=${r.confidence}');
      }

      if (mounted) {
        setState(() {
          _cards.clear();
          for (final r in results) {
            _cards.add(_BatchCard(
              id: IdGenerator.generate(),
              parsed: r,
            ));
          }
          _parsing = false;
          if (_cards.isEmpty) {
            _errorMsg = '未能识别出有效的收支记录，请尝试更具体的描述（如：中午吃饭35元）';
          } else {
            _clearDraft(); // 解析成功，清除草稿
          }
        });
      }
    } catch (e, stack) {
      if (!mounted) return;

      if (e is AiMembershipRequiredException) {
        // 会员未开通/已过期：刷新会员状态，提示用户
        ref.read(membershipProvider.notifier).refresh().catchError((_) {});
        setState(() {
          _parsing = false;
          _errorMsg = '请先开通会员以使用 AI 记账';
        });
        return;
      }

      if (e is AiAuthExpiredException) {
        setState(() {
          _parsing = false;
          _errorMsg = '登录状态已过期，请重新登录';
        });
        return;
      }

      debugPrint('🔴 [batch] 解析异常: $e\n$stack');
      setState(() {
        _parsing = false;
        _errorMsg = '识别失败，请稍后重试';
      });
    }
  }

  // ═══ 卡片交互 ═══

  void _editCard(int index) async {
    final card = _cards[index];
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordScreen(
          batchParsed: card.parsed,
          onBatchSaved: (updated) {
            setState(() {
              _cards[index] = _BatchCard(
                id: card.id,
                parsed: updated,
                selected: card.selected,
              );
            });
          },
        ),
      ),
    );
  }

  /// 批量记账列表删除 — 无需 Undo（仅移除本地草稿，未入库），直接返回 true。
  Future<bool> _deleteCard(int index) async {
    setState(() => _cards.removeAt(index));
    return true;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // onReorderItem already adjusts newIndex for removed item
      final card = _cards.removeAt(oldIndex);
      _cards.insert(newIndex, card);
    });
  }

  // ═══ 批量保存 ═══

  Future<void> _batchSave() async {
    if (_cards.isEmpty) return;

    // 检查是否有可保存的记录（金额必须 > 0，排除 AI 返回 null 或 0 的无效卡片）
    final validCards = _cards.where((c) => c.parsed.amount != null && c.parsed.amount! > 0).toList();
    debugPrint('🔍 [batch-save] 总卡片: ${_cards.length}, 有效卡片: ${validCards.length}');
    if (validCards.isEmpty) {
      setState(() => _errorMsg = '没有可保存的记录（缺少金额）');
      return;
    }

    setState(() => _saving = true);

    try {
      final userId = ref.read(currentUserIdProvider);
      final repo = ref.read(recordRepositoryProvider);
      debugPrint('🔍 [batch-save] userId=$userId');

      // 默认账户
      final accts = await ref.read(accountRepositoryProvider).getActiveAccounts();
      final defaultAccountId = accts.isNotEmpty ? accts.first.id : null;
      debugPrint('🔍 [batch-save] 默认账户: $defaultAccountId, 活跃账户数: ${accts.length}');

      if (defaultAccountId == null) {
        setState(() {
          _saving = false;
          _errorMsg = '请先创建至少一个账户';
        });
        return;
      }

      int savedCount = 0;
      for (var i = 0; i < validCards.length; i++) {
        final card = validCards[i];
        final p = card.parsed;
        final effectiveAccountId = p.accountId ?? defaultAccountId;
        final effectiveCategoryId = p.subcategoryId ?? p.categoryId;
        final effectiveOccurredAt = p.occurredAt ?? DateTime.now();
        debugPrint('🔍 [batch-save] 保存第${i+1}笔: amount=${p.amount}, type=${p.type}, '
            'accountId=$effectiveAccountId, categoryId=$effectiveCategoryId, '
            'note=${p.note}, rawInput=${p.rawInput}, occurredAt=$effectiveOccurredAt');
        try {
          await repo.createRecord(
            userId: userId,
            accountId: effectiveAccountId,
            amount: p.amount!,
            type: p.type ?? 'expense',
            categoryId: effectiveCategoryId,
            note: p.note ?? p.rawInput,
            occurredAt: effectiveOccurredAt,
          );
          savedCount++;
          debugPrint('🟢 [batch-save] 第${i+1}笔保存成功');
        } catch (e, stack) {
          debugPrint('🔴 [batch-save] 第${i+1}笔保存失败: $e\n$stack');
        }
      }

      // 通知所有相关页面刷新
      ref.invalidate(homeDataProvider);
      ref.invalidate(insightsDataProvider);
      ref.invalidate(assetsDataProvider);

      _clearDraft(); // 保存成功，清除草稿

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功保存 $savedCount/${validCards.length} 笔记录'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(); // 返回上一页
      }
    } catch (e, stack) {
      debugPrint('🔴 [batch-save] 批量保存异常: $e\n$stack');
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMsg = '批量保存失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记账'),
        actions: [
          if (_cards.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: Text('保存 (${_cards.length})'),
              onPressed: _saving ? null : _batchSave,
            ),
        ],
      ),
      body: Column(
        children: [
          // 输入区（半屏高度）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              child: TextField(
                controller: _textCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: '输入一段包含多笔收支的文字…\n如：中午吃饭35元；打车去公司20元；晚上买水果花了50',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: _parsing
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send_rounded),
                          onPressed: _parse,
                          tooltip: '识别',
                        ),
                ),
                onSubmitted: (_) => _parse(),
              ),
            ),
          ),
          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_errorMsg!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ),

          // 卡片列表
          Expanded(
            child: _cards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('输入文字后点击发送识别', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: _cards.length,
                    onReorderItem: _onReorder,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) => Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        ),
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final card = _cards[index];
                      final p = card.parsed;
                      final catName =
                          p.subcategoryName ?? p.categoryName ?? '未分类';
                      final acctName = p.accountHint ?? '未选择';

                      return RecordCard(
                        key: ValueKey(card.id),
                        id: card.id,
                        type: p.type ?? 'expense',
                        amount: p.amount ?? 0,
                        categoryName: catName,
                        categoryIcon: null, // 批量解析暂无法获取 DB icon
                        accountName: acctName,
                        note: p.note,
                        occurredAt: p.occurredAt, // AI 识别的日期（非今天时卡片上显示）
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle,
                              color: theme.colorScheme.onSurfaceVariant, size: 20),
                        ),
                        onTap: () => _editCard(index),
                        onDelete: () => _deleteCard(index),
                      );
                    },
                  ),
          ),

          // 底部保存按钮
          if (_cards.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_alt),
                    label: Text(_saving ? '保存中…' : '批量保存 (${_cards.length} 笔)'),
                    onPressed: _saving ? null : _batchSave,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
