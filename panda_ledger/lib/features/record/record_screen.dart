import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/utils/id_generator.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/record_repository.dart';
import '../../data/repository/account_repository.dart';
import '../auth/auth_provider.dart';
import '../home/home_provider.dart';
import '../insights/insights_provider.dart';
import '../assets/assets_provider.dart';
import '../../core/services/text_recognition/models/parsed_transaction.dart';
import '../../core/services/text_recognition/text_recognition_provider.dart';

/// 完整记账页面（重设计版）
///
/// 结构：AI 输入区 → 金额显示 → 类型 Tab → 分类网格 → 账户卡片 → 备注 → 日期 → 键盘
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  // ── 核心状态 ──
  String _amount = ''; // 不再预设为 '0'，空字符串表示未输入
  String _recordType = 'expense'; // expense / income / transfer
  String? _categoryId;
  String? _subcategoryId;
  String? _accountId;
  String? _toAccountId;
  String _note = '';
  DateTime _occurredAt = DateTime.now();
  bool _isSubmitting = false;

  // ── 控制器（复用，避免每次 build 重建）──
  late final TextEditingController _noteController;

  // ── 数据 ──
  List<Category> _allCategories = [];
  // parentId → children 分组
  Map<String, List<Category>> _childrenByParent = {};
  // 有子分类的一级分类
  List<Category> _parentCategoriesWithChildren = [];
  List<Account> _accounts = [];


  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _loadData() {
    final categoryDao = ref.read(categoryDaoProvider);
    final accountRepo = ref.read(accountRepositoryProvider);

    categoryDao.getCategoriesByKind(_recordType).then((cats) {
      if (mounted) {
        setState(() {
          _allCategories = cats;
          _rebuildCategoryGroups();
        });
      }
    });

    accountRepo.getActiveAccounts().then((accts) {
      if (mounted) {
        setState(() {
          _accounts = accts;
          if (accts.isNotEmpty && _accountId == null) {
            _accountId = accts.first.id;
          }
        });
      }
    });
  }

  void _refreshCategories() {
    ref.read(categoryDaoProvider).getCategoriesByKind(_recordType).then((cats) {
      if (mounted) {
        setState(() {
          _allCategories = cats;
          _rebuildCategoryGroups();
        });
      }
    });
  }

  /// 异步刷新分类（用于 AI 解析流程中的 await）
  Future<void> _refreshCategoriesAsync() async {
    final cats = await ref.read(categoryDaoProvider).getCategoriesByKind(_recordType);
    if (mounted) {
      setState(() {
        _allCategories = cats;
        _rebuildCategoryGroups();
      });
    }
  }

  /// 从扁平列表重建层级分组：只保留有子分类的一级分类
  void _rebuildCategoryGroups() {
    _childrenByParent = {};
    for (final cat in _allCategories.where((c) => c.parentId != null)) {
      _childrenByParent.putIfAbsent(cat.parentId!, () => []).add(cat);
    }
    // 只保留有关联子分类的一级分类
    _parentCategoriesWithChildren = _allCategories
        .where((c) => c.parentId == null && _childrenByParent.containsKey(c.id))
        .toList();
  }

  /// 获取当前选中分类的显示名称
  String? get _selectedCategoryName {
    if (_subcategoryId != null) {
      return _allCategories
          .where((c) => c.id == _subcategoryId)
          .map((c) => c.name)
          .firstOrNull;
    }
    if (_categoryId != null) {
      return _allCategories
          .where((c) => c.id == _categoryId)
          .map((c) => c.name)
          .firstOrNull;
    }
    return null;
  }

  /// 获取当前选中账户的显示名称
  String? get _selectedAccountName {
    if (_accountId == null) return null;
    return _accounts.where((a) => a.id == _accountId).map((a) => a.name).firstOrNull;
  }

  /// 弹出分类选择底部弹窗
  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CategoryPickerSheet(
        parentCategories: _parentCategoriesWithChildren,
        childrenByParent: _childrenByParent,
        selectedSubId: _subcategoryId,
        onSelectChild: (childId) {
          setState(() {
            _subcategoryId = childId;
            // 反查 child 的 parentId 设为 _categoryId
            final child = _allCategories.firstWhere((c) => c.id == childId);
            _categoryId = child.parentId;
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  /// 弹出账户选择底部弹窗
  void _showAccountPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AccountPickerSheet(
        accounts: _accounts,
        selectedId: _accountId,
        onSelect: (id) {
          setState(() => _accountId = id);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _onTypeChanged(String type) {
    setState(() {
      _recordType = type;
      _categoryId = null;
      _subcategoryId = null;
      _childrenByParent = {};
      _parentCategoriesWithChildren = [];
      _toAccountId = null;
    });
    _refreshCategories();
  }

  // ═════════════════════════════════════════════════════════
  // AI 智能解析
  // ═════════════════════════════════════════════════════════

  /// 弹出 AI 智能记账输入对话框
  Future<void> _showAiDialog() async {
    final inputCtrl = TextEditingController();
    bool isParsing = false;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.auto_awesome, color: Theme.of(ctx).colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text('AI 智能记账'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: inputCtrl,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  hintText: '描述这笔账单，如：昨天打车花了32元',
                  hintStyle: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant.withAlpha(120)),
                  border: const OutlineInputBorder(),
                ),
                enabled: !isParsing,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isParsing ? null : () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              icon: isParsing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(isParsing ? '识别中…' : '确定'),
              onPressed: isParsing
                  ? null
                  : () async {
                      final input = inputCtrl.text.trim();
                      if (input.isEmpty) return;
                      setDialogState(() => isParsing = true);
                      try {
                        await _aiParseFromInput(input);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() => isParsing = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('识别失败: $e'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// AI 解析核心逻辑（由弹窗入口调用）
  Future<void> _aiParseFromInput(String input) async {
    if (input.isEmpty) return;

    try {
      final service = ref.read(textRecognitionProvider);
      final categoryDao = ref.read(categoryDaoProvider);

      // 构建已有分类映射（含二级分类：名称→ID）
      final cats = await categoryDao.getActiveCategories();
      final catMap = <String, String>{};
      for (final c in cats) {
        catMap[c.name] = c.id;
      }

      // 构建账户映射
      final accountRepo = ref.read(accountRepositoryProvider);
      final accts = await accountRepo.getActiveAccounts();
      final acctMap = <String, String>{};
      for (final a in accts) {
        acctMap[a.name] = a.id;
      }

      final result = await service.parse(
        userInput: input,
        existingCategories: catMap,
        existingAccounts: acctMap,
      );

      if (!mounted) return;

      // 处理分类匹配 — 确保最终只填入二级分类
      if (result.matchType == MatchType.suggestNew &&
          result.newCategorySuggestion != null) {
        // 解析 "一级分类→二级分类" 格式
        final suggestion = result.newCategorySuggestion!;
        final parts = suggestion.split('→');
        final parentName = parts.length > 1 ? parts[0].trim() : null;
        final childName = parts.length > 1 ? parts[1].trim() : suggestion;

        final confirmMsg = parentName != null
            ? '新增到「$parentName」下的「$childName」分类？'
            : '是否新增「$childName」分类？';

        final shouldCreate = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未找到匹配分类'),
            content: Text(confirmMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('否'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('是'),
              ),
            ],
          ),
        );

        if (shouldCreate == true) {
          final userId = ref.read(currentUserIdProvider);

          // 如果需要一级分类，先查找或创建
          String? parentId;
          if (parentName != null) {
            // 查找已有的一级分类
            final existingParent = await categoryDao.getByName(parentName, _recordType);
            if (existingParent != null) {
              parentId = existingParent.id;
            } else {
              // 创建新的一级分类
              parentId = IdGenerator.generate();
              await categoryDao.insertCategory(CategoriesCompanion(
                id: Value(parentId),
                userId: Value(userId),
                name: Value(parentName),
                kind: Value(_recordType),
              ));
            }
          }

          // 创建二级分类
          final childId = IdGenerator.generate();
          await categoryDao.insertCategory(CategoriesCompanion(
            id: Value(childId),
            userId: Value(userId),
            name: Value(childName),
            parentId: Value.absentIfNull(parentId),
            kind: Value(_recordType),
          ));

          // 刷新分类数据并自动选中新分类
          await _refreshCategoriesAsync();
          if (mounted) {
            setState(() {
              _subcategoryId = childId;
              _categoryId = parentId;
            });
          }
        }
      }

      // 回填表单
      setState(() {
        if (result.amount != null) {
          _amount = result.amount!.toStringAsFixed(0);
          if (result.amount! % 1 != 0) {
            _amount = result.amount!.toStringAsFixed(2);
          }
        }
        if (result.type != null && result.type != _recordType) {
          _recordType = result.type!;
          _refreshCategories();
        }

        // 分类回填：优先使用 subcategoryId（二级分类），从中推导一级分类
        if (result.subcategoryId != null) {
          _subcategoryId = result.subcategoryId;
          // 反查该二级分类所属的一级分类
          final childCat = _allCategories
              .where((c) => c.id == result.subcategoryId)
              .firstOrNull;
          if (childCat != null && childCat.parentId != null) {
            _categoryId = childCat.parentId;
          }
        } else if (result.categoryId != null) {
          // 只有一级分类 ID（来自规则引擎或旧版 AI）→ 判断是否为叶子节点
          final matched = _allCategories
              .where((c) => c.id == result.categoryId)
              .firstOrNull;
          if (matched != null) {
            if (matched.parentId != null) {
              // 本身是二级分类，直接使用
              _subcategoryId = matched.id;
              _categoryId = matched.parentId;
            } else {
              // 是一级分类，不直接填入（等待用户选择二级分类）
              // 不清除已有选择，给用户留下提示
            }
          }
        }

        if (result.accountId != null) {
          _accountId = result.accountId;
        }
        if (result.note != null) {
          _note = result.note!;
          _noteController.text = result.note!;
        }
        if (result.occurredAt != null) _occurredAt = result.occurredAt!;
      });
    } catch (e) {
      rethrow; // 由弹窗层处理错误展示
    }
  }

  // ═════════════════════════════════════════════════════════
  // 键盘处理
  // ═════════════════════════════════════════════════════════

  void _onKeyTap(String key) {
    if (_isSubmitting) return;
    setState(() {
      if (key == '⌫') {
        _amount = _amount.length > 1 ? _amount.substring(0, _amount.length - 1) : '';
      } else if (key == '.') {
        if (_amount.isEmpty) {
          _amount = '0.';
        } else if (!_amount.contains('.') && _amount.length < 9) {
          _amount += '.';
        }
      } else if (key == '清空') {
        _amount = '';
      } else if (key == '完成') {
        _submitRecord();
        return;
      } else {
        if (_amount.isEmpty || _amount == '0') {
          _amount = key;
        } else if (_amount.length < 10) {
          _amount += key;
        }
      }
    });
  }

  // ═════════════════════════════════════════════════════════
  // 提交
  // ═════════════════════════════════════════════════════════

  Future<void> _submitRecord() async {
    // 防重入：如果上一次提交尚未完成，直接忽略本次调用
    if (_isSubmitting) return;

    final amount = double.tryParse(_amount);
    if (amount == null || amount <= 0) {
      _showValidationError('请输入金额');
      return;
    }
    if (_recordType != 'transfer' && _accountId == null) {
      _showValidationError('请选择账户');
      return;
    }
    if (_recordType == 'transfer' &&
        (_accountId == null || _toAccountId == null)) {
      _showValidationError('请选择转出和转入账户');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = ref.read(currentUserIdProvider);
      await ref.read(recordRepositoryProvider).createRecord(
            userId: userId,
            accountId: _accountId!,
            amount: amount,
            type: _recordType,
            toAccountId: _toAccountId,
            categoryId: _subcategoryId ?? _categoryId,
            note: _note.isEmpty ? null : _note,
            occurredAt: _occurredAt,
          );

      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已记录 ¥$_amount'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }

      // 通知所有相关页面刷新
      ref.invalidate(homeDataProvider);
      ref.invalidate(insightsDataProvider);
      ref.invalidate(assetsDataProvider);

      // 重置表单
      setState(() {
        _amount = '';
        _isSubmitting = false;
        _note = '';
        _noteController.clear();
        _categoryId = null;
        _subcategoryId = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记录失败: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime.now().subtract(const Duration(days: AppConstants.maxBackdateDays)),
      lastDate: DateTime.now(),
      helpText: '选择记账日期',
    );
    if (picked != null) {
      setState(() => _occurredAt = picked);
    }
  }

  // ═════════════════════════════════════════════════════════
  // Build
  // ═════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('记一笔'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI 智能记账',
            onPressed: _showAiDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 金额显示区 ──
            _AmountDisplay(
              amount: _amount,
              recordType: _recordType,
              theme: theme,
            ),

            // ── 类型 Tab ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('支出'), icon: Icon(Icons.shopping_cart_outlined)),
                  ButtonSegment(value: 'income', label: Text('收入'), icon: Icon(Icons.payments_outlined)),
                  ButtonSegment(value: 'transfer', label: Text('转账'), icon: Icon(Icons.swap_horiz)),
                ],
                selected: {_recordType},
                onSelectionChanged: (sel) => _onTypeChanged(sel.first),
              ),
            ),
            const SizedBox(height: 8),

            // ── 表单区域（可滚动）──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 日期快捷选择
                    _DateRow(date: _occurredAt, onTap: _pickDate, onToday: () => setState(() => _occurredAt = DateTime.now())),
                    const SizedBox(height: 16),

                    // 分类选择（支出/收入）—— 点击弹出底部弹窗
                    if (_recordType != 'transfer') ...[
                      _PickerField(
                        label: '选择分类',
                        selectedName: _selectedCategoryName,
                        icon: Icons.category_outlined,
                        onTap: _showCategoryPicker,
                      ),
                    ] else ...[
                      _TransferAccountSelector(
                        accounts: _accounts,
                        fromId: _accountId,
                        toId: _toAccountId,
                        onFromChanged: (id) => setState(() => _accountId = id),
                        onToChanged: (id) => setState(() => _toAccountId = id),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // 账户选择（非转账）—— 点击弹出底部弹窗
                    if (_recordType != 'transfer') ...[
                      _PickerField(
                        label: '选择账户',
                        selectedName: _selectedAccountName,
                        icon: Icons.account_balance_wallet_outlined,
                        onTap: _showAccountPicker,
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 备注
                    TextField(
                      decoration: const InputDecoration(
                        hintText: '备注（选填）',
                        prefixIcon: Icon(Icons.notes),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      controller: _noteController,
                      onChanged: (v) => _note = v,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── 数字键盘 ──
            _Numpad(onKeyTap: _onKeyTap, isSubmitting: _isSubmitting),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 金额显示
// ═══════════════════════════════════════════════════════════════

class _AmountDisplay extends StatelessWidget {
  final String amount;
  final String recordType;
  final ThemeData theme;

  const _AmountDisplay({
    required this.amount,
    required this.recordType,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final prefix = recordType == 'income' ? '+' : recordType == 'transfer' ? '↔ ' : '-';
    final color = recordType == 'income'
        ? theme.colorScheme.primary
        : recordType == 'transfer'
            ? theme.colorScheme.secondary
            : theme.colorScheme.error;
    final displayAmount = amount.isEmpty ? '0' : amount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '$prefix¥ $displayAmount',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.w300,
          letterSpacing: -1,
          color: amount.isEmpty ? theme.colorScheme.onSurfaceVariant.withAlpha(128) : color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 日期行
// ═══════════════════════════════════════════════════════════════

class _DateRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  final VoidCallback onToday;

  const _DateRow({required this.date, required this.onTap, required this.onToday});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final label = isToday ? '今天' : '${date.month}/${date.day}';

    return Row(
      children: [
        Icon(Icons.calendar_today_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        InkWell(
          onTap: onTap,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
          ),
        ),
        if (!isToday) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.today, size: 14),
            label: const Text('今天', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: onToday,
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用选择器输入框（点击弹出底部弹窗）
// ═══════════════════════════════════════════════════════════════

class _PickerField extends StatelessWidget {
  final String label;
  final String? selectedName;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerField({
    required this.label,
    required this.selectedName,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selectedName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasSelection
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              color: hasSelection
                  ? theme.colorScheme.primaryContainer.withAlpha(40)
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: hasSelection ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selectedName ?? '请选择',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: hasSelection ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 分类选择底部弹窗
// ═══════════════════════════════════════════════════════════════

class _CategoryPickerSheet extends StatelessWidget {
  final List<Category> parentCategories;
  final Map<String, List<Category>> childrenByParent;
  final String? selectedSubId;
  final ValueChanged<String> onSelectChild;

  const _CategoryPickerSheet({
    required this.parentCategories,
    required this.childrenByParent,
    required this.selectedSubId,
    required this.onSelectChild,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖拽指示条
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('选择分类', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: parentCategories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category_outlined, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('请先在设置中创建分类', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: parentCategories.length,
                    itemBuilder: (context, index) {
                      final parent = parentCategories[index];
                      final children = childrenByParent[parent.id] ?? [];
                      return _CategoryGroup(
                        parentName: parent.name,
                        parentIcon: _iconForCategory(parent.name),
                        children: children,
                        selectedSubId: selectedSubId,
                        onSelectChild: onSelectChild,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  final String parentName;
  final IconData parentIcon;
  final List<Category> children;
  final String? selectedSubId;
  final ValueChanged<String> onSelectChild;

  const _CategoryGroup({
    required this.parentName,
    required this.parentIcon,
    required this.children,
    required this.selectedSubId,
    required this.onSelectChild,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 一级分类标题
          Row(
            children: [
              Icon(parentIcon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                parentName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 二级分类网格：4 列
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children.map((child) {
              final isSelected = selectedSubId == child.id;
              return _ChildCategoryChip(
                name: child.name,
                icon: _iconForCategory(child.name),
                selected: isSelected,
                onTap: () => onSelectChild(child.id),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ChildCategoryChip extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChildCategoryChip({
    required this.name,
    required this.icon,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          // 选中态：浅色底色 + 描边高亮，不遮挡图标和文字
          color: selected
              ? theme.colorScheme.primaryContainer.withAlpha(60)
              : theme.colorScheme.surfaceContainerHighest.withAlpha(40),
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: theme.colorScheme.primary, width: 1.8)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 账户选择底部弹窗
// ═══════════════════════════════════════════════════════════════

class _AccountPickerSheet extends StatelessWidget {
  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _AccountPickerSheet({
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.75,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('选择账户', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: accounts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('暂无可用账户', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final acct = accounts[index];
                      final isSelected = selectedId == acct.id;
                      final icon = _accountTypeIcon(acct.type);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => onSelect(acct.id),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isSelected
                                  ? theme.colorScheme.primaryContainer.withAlpha(60)
                                  : theme.colorScheme.surfaceContainerHighest.withAlpha(30),
                              border: isSelected
                                  ? Border.all(color: theme.colorScheme.primary, width: 1.8)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(icon, size: 24, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    acct.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  '¥ ${acct.balance.toStringAsFixed(2)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isSelected)
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check, size: 14, color: Colors.white),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

IconData _accountTypeIcon(String type) {
  switch (type) {
    case 'cash': return Icons.money;
    case 'bank': return Icons.account_balance;
    case 'credit': return Icons.credit_card;
    case 'loan': return Icons.real_estate_agent;
    case 'invest': return Icons.trending_up;
    default: return Icons.more_horiz;
  }
}

/// 根据分类名称返回默认图标
IconData _iconForCategory(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('餐') || lower.contains('食') || lower.contains('饭')) return Icons.restaurant;
  if (lower.contains('交通') || lower.contains('行') || lower.contains('车')) return Icons.directions_car;
  if (lower.contains('购物') || lower.contains('买')) return Icons.shopping_bag;
  if (lower.contains('娱乐') || lower.contains('玩')) return Icons.movie;
  if (lower.contains('医') || lower.contains('药') || lower.contains('健康')) return Icons.local_hospital;
  if (lower.contains('住') || lower.contains('房') || lower.contains('租')) return Icons.home;
  if (lower.contains('教育') || lower.contains('学') || lower.contains('书')) return Icons.school;
  if (lower.contains('通讯') || lower.contains('手机') || lower.contains('话费')) return Icons.phone_android;
  if (lower.contains('衣') || lower.contains('服') || lower.contains('鞋')) return Icons.checkroom;
  if (lower.contains('工资') || lower.contains('薪')) return Icons.payments;
  if (lower.contains('理财') || lower.contains('投资') || lower.contains('股票')) return Icons.trending_up;
  if (lower.contains('红包') || lower.contains('礼金')) return Icons.card_giftcard;
  if (lower.contains('宠物') || lower.contains('猫') || lower.contains('狗')) return Icons.pets;
  if (lower.contains('运动') || lower.contains('健身')) return Icons.fitness_center;
  if (lower.contains('美') || lower.contains('发') || lower.contains('容')) return Icons.face;
  if (lower.contains('零食') || lower.contains('水') || lower.contains('饮')) return Icons.local_cafe;
  if (lower.contains('日用') || lower.contains('生活')) return Icons.format_paint;
  if (lower.contains('水电') || lower.contains('燃') || lower.contains('物业')) return Icons.bolt;
  if (lower.contains('保险')) return Icons.shield;
  return Icons.category;
}

// ═══════════════════════════════════════════════════════════════
// 转账账户选择器
// ═══════════════════════════════════════════════════════════════

class _TransferAccountSelector extends StatelessWidget {
  final List<Account> accounts;
  final String? fromId;
  final String? toId;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;

  const _TransferAccountSelector({
    required this.accounts,
    required this.fromId,
    required this.toId,
    required this.onFromChanged,
    required this.onToChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildAccountCards(List<Account> accts, String? selected, ValueChanged<String> onSel) {
      if (accts.isEmpty) {
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text('暂无可用账户', style: theme.textTheme.bodyMedium),
        );
      }
      return SizedBox(
        height: 64,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: accts.length,
          itemBuilder: (context, index) {
            final acct = accts[index];
            final isSel = selected == acct.id;
            final icon = _accountTypeIcon(acct.type);
            return Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
              child: GestureDetector(
                onTap: () => onSel(acct.id),
                child: Container(
                  width: 96,
                  decoration: BoxDecoration(
                    color: isSel
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: isSel ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 22, color: isSel ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 2),
                      Text(acct.name, style: TextStyle(fontSize: 12, fontWeight: isSel ? FontWeight.w600 : FontWeight.w400),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('转出账户', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        buildAccountCards(accounts, fromId, onFromChanged),
        const SizedBox(height: 16),
        Center(child: Icon(Icons.arrow_downward, color: theme.colorScheme.outline)),
        const SizedBox(height: 8),
        Text('转入账户', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        buildAccountCards(accounts.where((a) => a.id != fromId).toList(), toId, onToChanged),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 数字键盘
// ═══════════════════════════════════════════════════════════════

class _Numpad extends StatelessWidget {
  final void Function(String) onKeyTap;
  final bool isSubmitting;
  const _Numpad({required this.onKeyTap, required this.isSubmitting});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Row(children: [
            _KeyButton('1', onKeyTap, theme),
            _KeyButton('2', onKeyTap, theme),
            _KeyButton('3', onKeyTap, theme),
          ]),
          Row(children: [
            _KeyButton('4', onKeyTap, theme),
            _KeyButton('5', onKeyTap, theme),
            _KeyButton('6', onKeyTap, theme),
          ]),
          Row(children: [
            _KeyButton('7', onKeyTap, theme),
            _KeyButton('8', onKeyTap, theme),
            _KeyButton('9', onKeyTap, theme),
          ]),
          Row(children: [
            _KeyButton('.', onKeyTap, theme),
            _KeyButton('0', onKeyTap, theme),
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: isSubmitting ? null : () => onKeyTap('完成'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: theme.colorScheme.primary,
                  ),
                  child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('完成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ]),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextButton(
                  onPressed: () => onKeyTap('清空'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('清空', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextButton(
                  onPressed: () => onKeyTap('⌫'),
                  child: const Icon(Icons.backspace_outlined),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final void Function(String) onTap;
  final ThemeData theme;

  const _KeyButton(this.label, this.onTap, this.theme);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 56,
        child: TextButton(
          onPressed: () => onTap(label),
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w400),
          ),
        ),
      ),
    );
  }
}
