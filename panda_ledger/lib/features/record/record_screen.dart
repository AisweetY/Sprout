import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/utils/category_icon_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/record_repository.dart';
import '../../data/repository/account_repository.dart';
import '../../data/sync/sync_queue_dao_provider.dart';
import '../auth/auth_provider.dart';
import '../home/home_provider.dart';
import '../insights/insights_provider.dart';
import '../assets/assets_provider.dart';
import '../../core/services/text_recognition/models/parsed_transaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记一笔页（极简重构版）
///
/// 布局（从上到下，全屏固定，无滚动）：
///   类型 Tab → 金额大字区 → 分类横向滑动 → 辅助信息行 → 数字键盘
///
/// 键盘始终显示，省去"展开详情"步骤。
/// 备注通过底部弹窗输入，账户/日期通过 chip 点击弹出。
class RecordScreen extends ConsumerStatefulWidget {
  final Record? editRecord;
  final ParsedTransaction? batchParsed;
  final void Function(ParsedTransaction)? onBatchSaved;

  const RecordScreen({
    super.key,
    this.editRecord,
    this.batchParsed,
    this.onBatchSaved,
  });

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  // ── 核心状态 ──
  String _amount = '';
  String _recordType = 'expense';
  String? _categoryId;
  String? _subcategoryId;
  String? _accountId;
  String? _toAccountId;
  String _note = '';
  DateTime _occurredAt = DateTime.now();
  bool _isSubmitting = false;
  bool _showSuccess = false;
  bool _categoriesLoading = false;

  late final TextEditingController _noteController;

  // ── 数据 ──
  List<Category> _allCategories = [];
  Map<String, List<Category>> _childrenByParent = {};
  List<Category> _parentCategoriesWithChildren = [];
  List<Account> _accounts = [];
  List<Category> _recentLeafCategories = [];

  // ── 分类横向行滚动控制 ──
  final ScrollController _categoryScrollCtrl = ScrollController();

  // ── SharedPreferences 键 ──
  static const _pkType = 'last_record_type';
  static const _pkCat = 'last_category_id';
  static const _pkParentCat = 'last_parent_category_id';
  static const _pkAcct = 'last_account_id';
  static const _pkToAcct = 'last_to_account_id';
  static const _pkRecentExpenseCats = 'recent_expense_category_ids';
  static const _pkRecentIncomeCats = 'recent_income_category_ids';

  bool get _isEditMode => widget.editRecord != null;
  bool get _isBatchMode => widget.batchParsed != null;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _initFromEditRecord();
    _initFromBatchParsed();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _initFromEditRecord() {
    final r = widget.editRecord;
    if (r == null) return;
    _amount = r.amount.toStringAsFixed(0);
    if (r.amount % 1 != 0) _amount = r.amount.toStringAsFixed(2);
    _recordType = r.type;
    _categoryId = r.categoryId;
    _accountId = r.accountId;
    _toAccountId = r.toAccountId;
    _note = r.note ?? '';
    _noteController.text = _note;
    _occurredAt = r.occurredAt;
  }

  void _initFromBatchParsed() {
    final p = widget.batchParsed;
    if (p == null) return;
    if (p.amount != null) {
      _amount = p.amount!.toStringAsFixed(0);
      if (p.amount! % 1 != 0) _amount = p.amount!.toStringAsFixed(2);
    }
    _recordType = p.type ?? 'expense';
    _categoryId = p.subcategoryId ?? p.categoryId;
    _accountId = p.accountId;
    _note = p.note ?? '';
    _noteController.text = _note;
    if (p.occurredAt != null) _occurredAt = p.occurredAt!;
  }

  @override
  void dispose() {
    _noteController.dispose();
    _categoryScrollCtrl.dispose();
    super.dispose();
  }

  void _loadData() {
    final categoryDao = ref.read(categoryDaoProvider);
    final accountRepo = ref.read(accountRepositoryProvider);

    Future.wait([
      categoryDao.getCategoriesByKind(_recordType),
      accountRepo.getActiveAccounts(),
    ]).then((results) {
      if (!mounted) return;
      final cats = results[0] as List<Category>;
      final accts = results[1] as List<Account>;
      setState(() {
        _allCategories = cats;
        _accounts = accts;
        _rebuildCategoryGroups();
        if ((_isEditMode || _isBatchMode) && _categoryId != null) {
          final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
          if (cat != null && cat.parentId != null) {
            _subcategoryId = _categoryId;
            _categoryId = cat.parentId;
          }
        }
        if (accts.isNotEmpty && _accountId == null) {
          _accountId = accts.first.id;
        }
      });
      if (!_isEditMode && widget.batchParsed == null) {
        _restoreLastSelection();
      }
      _loadRecentCategories();
    });
  }

  void _refreshCategories() {
    ref.read(categoryDaoProvider).getCategoriesByKind(_recordType).then((cats) {
      if (mounted) {
        setState(() {
          _allCategories = cats;
          _rebuildCategoryGroups();
          _categoriesLoading = false;
        });
        _loadRecentCategories();
      }
    });
  }

  void _onCategoryCreated(String newCategoryId) {
    ref.read(categoryDaoProvider).getCategoriesByKind(_recordType).then((cats) {
      if (!mounted) return;
      final found = cats.where((c) => c.id == newCategoryId).firstOrNull;
      if (found != null) {
        setState(() {
          _allCategories = cats;
          _rebuildCategoryGroups();
          if (found.parentId != null) {
            _subcategoryId = newCategoryId;
            _categoryId = found.parentId;
          } else {
            _categoryId = newCategoryId;
            _subcategoryId = null;
          }
        });
        Navigator.of(context).pop();
        _loadRecentCategories();
      }
    });
  }

  Future<void> _refreshCategoriesAsync() async {
    final cats = await ref.read(categoryDaoProvider).getCategoriesByKind(_recordType);
    if (mounted) {
      setState(() {
        _allCategories = cats;
        _rebuildCategoryGroups();
      });
      await _loadRecentCategories();
    }
  }

  void _rebuildCategoryGroups() {
    _childrenByParent = {};
    for (final cat in _allCategories.where((c) => c.parentId != null)) {
      _childrenByParent.putIfAbsent(cat.parentId!, () => []).add(cat);
    }
    _parentCategoriesWithChildren = _allCategories
        .where((c) => c.parentId == null && _childrenByParent.containsKey(c.id))
        .toList();
  }

  List<Category> _getLeafCategories() {
    return _allCategories.where((c) => c.parentId != null && !c.isArchived).toList();
  }

  Future<void> _loadRecentCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _recordType == 'income' ? _pkRecentIncomeCats : _pkRecentExpenseCats;
    final recentIds = prefs.getStringList(key) ?? [];
    final allLeafs = _getLeafCategories();
    final result = <Category>[];

    if (_subcategoryId != null) {
      final sel = allLeafs.where((c) => c.id == _subcategoryId).firstOrNull;
      if (sel != null) result.add(sel);
    }
    for (final id in recentIds) {
      if (result.length >= 8) break;
      final cat = allLeafs.where((c) => c.id == id).firstOrNull;
      if (cat != null && !result.any((r) => r.id == cat.id)) result.add(cat);
    }
    if (result.length < 8) {
      final existingIds = result.map((c) => c.id).toSet();
      for (final cat in allLeafs) {
        if (result.length >= 8) break;
        if (!existingIds.contains(cat.id)) result.add(cat);
      }
    }

    if (mounted) setState(() => _recentLeafCategories = result);
  }

  Future<void> _updateRecentCategory(String categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _recordType == 'income' ? _pkRecentIncomeCats : _pkRecentExpenseCats;
    final current = prefs.getStringList(key) ?? [];
    current.removeWhere((id) => id == categoryId);
    current.insert(0, categoryId);
    if (current.length > 12) current.removeRange(12, current.length);
    await prefs.setStringList(key, current);
  }

  String? get _selectedAccountName {
    if (_accountId == null) return null;
    return _accounts.where((a) => a.id == _accountId).map((a) => a.name).firstOrNull;
  }

  // ─────────────────────────────────────────────
  // 弹窗：分类选择
  // ─────────────────────────────────────────────

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
        recordType: _recordType,
        onSelectChild: (childId) {
          setState(() {
            _subcategoryId = childId;
            final child = _allCategories.firstWhere((c) => c.id == childId);
            _categoryId = child.parentId;
          });
          Navigator.pop(ctx);
          // 选中后刷新最近分类列表（置顶），并滚回行首
          _loadRecentCategories().then((_) {
            if (_categoryScrollCtrl.hasClients) {
              _categoryScrollCtrl.animateTo(
                0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
              );
            }
          });
        },
        onCategoryCreated: _onCategoryCreated,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 弹窗：账户选择
  // ─────────────────────────────────────────────

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

  void _showFromAccountPicker() {
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
        title: '选择转出账户',
        onSelect: (id) {
          setState(() {
            _accountId = id;
            // 若转入与转出相同，清空转入
            if (_toAccountId == id) _toAccountId = null;
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showToAccountPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AccountPickerSheet(
        accounts: _accounts.where((a) => a.id != _accountId).toList(),
        selectedId: _toAccountId,
        title: '选择转入账户',
        onSelect: (id) {
          setState(() => _toAccountId = id);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 弹窗：备注输入
  // ─────────────────────────────────────────────

  void _showNoteSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('备注', style: Theme.of(ctx).textTheme.titleMedium),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('完成'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '描述这笔账…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    suffixIcon: _noteController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _noteController.clear();
                              setState(() => _note = '');
                              setSheetState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() => _note = v);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 类型切换
  // ─────────────────────────────────────────────

  void _onTypeChanged(String type) {
    setState(() {
      _recordType = type;
      _categoryId = null;
      _subcategoryId = null;
      _childrenByParent = {};
      _parentCategoriesWithChildren = [];
      _recentLeafCategories = [];
      _toAccountId = null;
      _categoriesLoading = true;
    });
    _refreshCategories();
  }

  // ─────────────────────────────────────────────
  // 键盘输入
  // ─────────────────────────────────────────────

  void _onKeyTap(String key) {
    if (_isSubmitting) return;
    HapticFeedback.lightImpact();
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

  // ─────────────────────────────────────────────
  // 提交
  // ─────────────────────────────────────────────

  Future<void> _submitRecord() async {
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
    if (_recordType == 'transfer' && _accountId == _toAccountId) {
      _showValidationError('转出和转入账户不能相同');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? effectiveCategoryId = _subcategoryId ?? _categoryId;
      if (effectiveCategoryId == null && _recordType != 'transfer') {
        final categoryDao = ref.read(categoryDaoProvider);
        final defaultName = _recordType == 'income' ? '其他收入' : '其他';
        final defaultCat = await categoryDao.getByName(defaultName, _recordType);
        effectiveCategoryId = defaultCat?.id;
      }

      final userId = ref.read(currentUserIdProvider);
      final repo = ref.read(recordRepositoryProvider);

      if (_isBatchMode) {
        final updated = ParsedTransaction(
          amount: amount,
          type: _recordType,
          categoryId: effectiveCategoryId,
          subcategoryId: _subcategoryId,
          accountId: _accountId,
          accountHint: _accountId != null
              ? _accounts.where((a) => a.id == _accountId).firstOrNull?.name
              : null,
          note: _note.isEmpty ? null : _note,
          occurredAt: _occurredAt,
          confidence: 1.0,
          matchType: MatchType.existing,
          rawInput: widget.batchParsed?.rawInput ?? '',
        );
        widget.onBatchSaved?.call(updated);
      } else if (_isEditMode) {
        final oldRecord = widget.editRecord!;
        await repo.updateRecord(
          recordId: oldRecord.id,
          accountId: _accountId!,
          amount: amount,
          type: _recordType,
          toAccountId: _toAccountId,
          categoryId: effectiveCategoryId,
          note: _note.isEmpty ? null : _note,
          occurredAt: _occurredAt,
          oldAmount: oldRecord.amount,
          oldType: oldRecord.type,
          oldAccountId: oldRecord.accountId,
          oldToAccountId: oldRecord.toAccountId,
        );
      } else {
        await repo.createRecord(
          userId: userId,
          accountId: _accountId!,
          amount: amount,
          type: _recordType,
          toAccountId: _toAccountId,
          categoryId: effectiveCategoryId,
          note: _note.isEmpty ? null : _note,
          occurredAt: _occurredAt,
        );
      }

      if (_isBatchMode) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() => _showSuccess = true);
        await Future.delayed(const Duration(milliseconds: 400));

        if (mounted) {
          SnackbarUtils.show(
            context: context,
            message: _isEditMode ? '已保存修改' : '已记录 ¥$_amount',
            duration: const Duration(seconds: 1),
          );
        }
      }

      ref.invalidate(homeDataProvider);
      ref.invalidate(insightsDataProvider);
      ref.invalidate(assetsDataProvider);

      if (!_isBatchMode) {
        _saveLastSelection(
          type: _recordType,
          catId: _subcategoryId ?? _categoryId,
          parentCatId: _categoryId,
          acctId: _accountId,
          toAcctId: _toAccountId,
        );
        final savedCatId = _subcategoryId ?? _categoryId;
        if (savedCatId != null && _recordType != 'transfer') {
          _updateRecentCategory(savedCatId);
        }
      }

      if (mounted) {
        setState(() {
          if (!_isEditMode) {
            _amount = '';
            _note = '';
            _noteController.clear();
            _categoryId = null;
            _subcategoryId = null;
          }
          _showSuccess = false;
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        if (!_isBatchMode) {
          SnackbarUtils.showError(context: context, message: '记录失败: $e');
        }
      }
    }
  }

  // ─────────────────────────────────────────────
  // SharedPreferences 记忆上次选择
  // ─────────────────────────────────────────────

  Future<void> _saveLastSelection({
    String? type,
    String? catId,
    String? parentCatId,
    String? acctId,
    String? toAcctId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (type != null) await prefs.setString(_pkType, type);
    if (catId != null) await prefs.setString(_pkCat, catId);
    if (parentCatId != null) await prefs.setString(_pkParentCat, parentCatId);
    if (acctId != null) await prefs.setString(_pkAcct, acctId);
    if (toAcctId != null) await prefs.setString(_pkToAcct, toAcctId);
  }

  Future<void> _restoreLastSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final lastType = prefs.getString(_pkType);
    final lastCatId = prefs.getString(_pkCat);
    final lastParentCatId = prefs.getString(_pkParentCat);
    final lastAcctId = prefs.getString(_pkAcct);
    final lastToAcctId = prefs.getString(_pkToAcct);

    bool needRefresh = false;
    if (lastType != null && lastType != _recordType) {
      _recordType = lastType;
      needRefresh = true;
    }
    if (needRefresh) await _refreshCategoriesAsync();
    if (!mounted) return;

    if (lastCatId != null) {
      final cat = _allCategories
          .where((c) => c.id == lastCatId && !c.isArchived)
          .firstOrNull;
      if (cat != null) {
        setState(() {
          if (cat.parentId != null) {
            _subcategoryId = lastCatId;
            _categoryId = cat.parentId;
          } else {
            _categoryId = lastCatId;
            _subcategoryId = null;
          }
        });
      }
    }
    if (_categoryId == null && _subcategoryId == null && lastParentCatId != null) {
      final parent = _allCategories
          .where((c) => c.id == lastParentCatId && !c.isArchived)
          .firstOrNull;
      if (parent != null) setState(() => _categoryId = lastParentCatId);
    }

    if (lastAcctId != null) {
      final acct =
          _accounts.where((a) => a.id == lastAcctId && !a.isArchived).firstOrNull;
      if (acct != null) setState(() => _accountId = lastAcctId);
    }

    if (lastToAcctId != null &&
        _recordType == 'transfer' &&
        lastToAcctId != _accountId) {
      final toAcct = _accounts
          .where((a) => a.id == lastToAcctId && !a.isArchived)
          .firstOrNull;
      if (toAcct != null) setState(() => _toAccountId = lastToAcctId);
    }
  }

  void _showValidationError(String message) {
    SnackbarUtils.show(context: context, message: message);
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime.now()
          .subtract(const Duration(days: AppConstants.maxBackdateDays)),
      lastDate: DateTime.now(),
      helpText: '选择记账日期',
    );
    if (picked != null) setState(() => _occurredAt = picked);
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // 键盘始终显示，不随系统键盘（备注弹窗）压缩
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_isBatchMode || _isEditMode ? '编辑账单' : '记一笔'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. 类型 Tab ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'expense',
                    label: Text('支出'),
                    icon: Icon(Icons.arrow_upward_rounded, size: 15),
                  ),
                  ButtonSegment(
                    value: 'income',
                    label: Text('收入'),
                    icon: Icon(Icons.arrow_downward_rounded, size: 15),
                  ),
                  ButtonSegment(
                    value: 'transfer',
                    label: Text('转账'),
                    icon: Icon(Icons.swap_horiz_rounded, size: 15),
                  ),
                ],
                selected: {_recordType},
                onSelectionChanged: (sel) {
                  final t = sel.first;
                  if (t != _recordType) _onTypeChanged(t);
                },
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),

            // ── 2. 金额大字区 ──
            _AmountDisplay(
              amount: _amount,
              recordType: _recordType,
              theme: theme,
              showSuccess: _showSuccess,
            ),

            // ── 3. 分类横向滑动 OR 紧凑转账选择器 ──
            if (_recordType != 'transfer')
              _HorizontalCategoryRow(
                categories: _recentLeafCategories,
                selectedSubId: _subcategoryId,
                loading: _categoriesLoading,
                scrollController: _categoryScrollCtrl,
                onSelect: (cat) {
                  setState(() {
                    _subcategoryId = cat.id;
                    _categoryId = cat.parentId;
                  });
                  HapticFeedback.selectionClick();
                },
                onMoreTap: _showCategoryPicker,
              )
            else
              _CompactTransferBar(
                accounts: _accounts,
                fromId: _accountId,
                toId: _toAccountId,
                onFromTap: _showFromAccountPicker,
                onToTap: _showToAccountPicker,
              ),

            // ── 4. 辅助信息行（账户 / 日期 / 备注）──
            _InfoChipsRow(
              accountName: _recordType != 'transfer'
                  ? (_selectedAccountName ?? '选择账户')
                  : null,
              accountHasValue: _accountId != null,
              date: _occurredAt,
              note: _note,
              onAccountTap:
                  _recordType != 'transfer' ? _showAccountPicker : null,
              onDateTap: _pickDate,
              onNoteTap: _showNoteSheet,
            ),

            const Spacer(),

            // ── 5. 数字键盘（常驻底部）──
            _Numpad(
              onKeyTap: _onKeyTap,
              isSubmitting: _isSubmitting,
              isEditMode: _isEditMode || _isBatchMode,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 金额显示区（重新设计：大字号 + 颜色背景）
// ═══════════════════════════════════════════════════════════════

class _AmountDisplay extends StatelessWidget {
  final String amount;
  final String recordType;
  final ThemeData theme;
  final bool showSuccess;

  const _AmountDisplay({
    required this.amount,
    required this.recordType,
    required this.theme,
    this.showSuccess = false,
  });

  Color get _typeColor {
    return recordType == 'income'
        ? theme.colorScheme.primary
        : recordType == 'transfer'
            ? theme.colorScheme.secondary
            : theme.colorScheme.error;
  }

  String get _prefix {
    return recordType == 'income'
        ? '+'
        : recordType == 'transfer'
            ? ''
            : '-';
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor;
    final isEmpty = amount.isEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 82,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: color.withAlpha(isEmpty ? 8 : 14),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        child: showSuccess
            ? TweenAnimationBuilder<double>(
                key: const ValueKey('success'),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.scale(
                  scale: v,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 28),
                  ),
                ),
              )
            : Padding(
                key: const ValueKey('amount'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      isEmpty ? '¥' : '$_prefix¥',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        color: isEmpty
                            ? theme.colorScheme.onSurfaceVariant.withAlpha(80)
                            : color,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      isEmpty ? '0' : amount,
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -2,
                        color: isEmpty
                            ? theme.colorScheme.onSurfaceVariant.withAlpha(80)
                            : color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 分类横向滑动行（替代原 Wrap 网格）
// ═══════════════════════════════════════════════════════════════

class _HorizontalCategoryRow extends StatelessWidget {
  final List<Category> categories;
  final String? selectedSubId;
  final bool loading;
  final ValueChanged<Category> onSelect;
  final VoidCallback onMoreTap;
  final ScrollController? scrollController;

  const _HorizontalCategoryRow({
    required this.categories,
    required this.selectedSubId,
    required this.loading,
    required this.onSelect,
    required this.onMoreTap,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && categories.isEmpty) {
      return SizedBox(
        height: 86,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          itemCount: 6,
          itemBuilder: (_, i) => _SkeletonCategoryChip(marginRight: i < 5 ? 8 : 0),
        ),
      );
    }

    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: SizedBox(
          height: 72,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建分类'),
            onPressed: onMoreTap,
          ),
        ),
      );
    }

    return SizedBox(
      height: 86,
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        itemCount: categories.length + 1, // +1 for 更多
        itemBuilder: (context, index) {
          if (index == categories.length) {
            return _MoreCategoryChip(onTap: onMoreTap);
          }
          final cat = categories[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ChildCategoryChip(
              name: cat.name,
              icon: _iconForCategory(cat.name, dbIcon: cat.icon),
              selected: selectedSubId == cat.id,
              onTap: () => onSelect(cat),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonCategoryChip extends StatelessWidget {
  final double marginRight;
  const _SkeletonCategoryChip({this.marginRight = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 64,
      height: 72,
      margin: EdgeInsets.only(right: marginRight),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 辅助信息行（账户 / 日期 / 备注）
// ═══════════════════════════════════════════════════════════════

class _InfoChipsRow extends StatelessWidget {
  final String? accountName; // null = 转账模式，不显示账户
  final bool accountHasValue;
  final DateTime date;
  final String note;
  final VoidCallback? onAccountTap;
  final VoidCallback onDateTap;
  final VoidCallback onNoteTap;

  const _InfoChipsRow({
    required this.accountName,
    required this.accountHasValue,
    required this.date,
    required this.note,
    required this.onAccountTap,
    required this.onDateTap,
    required this.onNoteTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final dateLabel = isToday ? '今天' : '${date.month}/${date.day}';
    final noteLabel = note.isEmpty
        ? '备注'
        : (note.length > 10 ? '${note.substring(0, 10)}…' : note);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // 账户（转账模式隐藏）
              if (accountName != null) ...[
                Expanded(
                  child: _InfoChip(
                    icon: Icons.account_balance_wallet_outlined,
                    label: accountName!,
                    hasValue: accountHasValue,
                    onTap: onAccountTap ?? () {},
                  ),
                ),
                _InfoDivider(),
              ],
              // 日期
              _InfoChip(
                icon: Icons.calendar_today_outlined,
                label: dateLabel,
                hasValue: !isToday,
                onTap: onDateTap,
              ),
              _InfoDivider(),
              // 备注
              Expanded(
                child: _InfoChip(
                  icon: Icons.notes_outlined,
                  label: noteLabel,
                  hasValue: note.isNotEmpty,
                  onTap: onNoteTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Theme.of(context).colorScheme.outline.withAlpha(50),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = hasValue
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight:
                      hasValue ? FontWeight.w500 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 紧凑转账选择器
// ═══════════════════════════════════════════════════════════════

class _CompactTransferBar extends StatelessWidget {
  final List<Account> accounts;
  final String? fromId;
  final String? toId;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;

  const _CompactTransferBar({
    required this.accounts,
    required this.fromId,
    required this.toId,
    required this.onFromTap,
    required this.onToTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromAcct = accounts.where((a) => a.id == fromId).firstOrNull;
    final toAcct = accounts.where((a) => a.id == toId).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: _TransferAccountTile(
                account: fromAcct,
                placeholder: '转出账户',
                onTap: onFromTap,
                theme: theme,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: theme.colorScheme.secondary,
                size: 22,
              ),
            ),
            Expanded(
              child: _TransferAccountTile(
                account: toAcct,
                placeholder: '转入账户',
                onTap: onToTap,
                theme: theme,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferAccountTile extends StatelessWidget {
  final Account? account;
  final String placeholder;
  final VoidCallback onTap;
  final ThemeData theme;

  const _TransferAccountTile({
    required this.account,
    required this.placeholder,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final hasAccount = account != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: hasAccount
              ? theme.colorScheme.secondaryContainer.withAlpha(60)
              : theme.colorScheme.surfaceContainerHighest.withAlpha(50),
          borderRadius: BorderRadius.circular(12),
          border: hasAccount
              ? Border.all(color: theme.colorScheme.secondary, width: 1.5)
              : Border.all(
                  color: theme.colorScheme.outline.withAlpha(80), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasAccount) ...[
              Icon(
                _accountTypeIcon(account!.type),
                size: 15,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                hasAccount ? account!.name : placeholder,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      hasAccount ? FontWeight.w600 : FontWeight.w400,
                  color: hasAccount
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 分类选择底部弹窗（保留原逻辑）
// ═══════════════════════════════════════════════════════════════

class _CategoryPickerSheet extends StatefulWidget {
  final List<Category> parentCategories;
  final Map<String, List<Category>> childrenByParent;
  final String? selectedSubId;
  final String recordType;
  final ValueChanged<String> onSelectChild;
  final void Function(String newCategoryId) onCategoryCreated;

  const _CategoryPickerSheet({
    required this.parentCategories,
    required this.childrenByParent,
    required this.selectedSubId,
    required this.recordType,
    required this.onSelectChild,
    required this.onCategoryCreated,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('选择分类', style: theme.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: widget.parentCategories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category_outlined,
                            size: 48,
                            color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('暂无分类，请创建',
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.parentCategories.length,
                    itemBuilder: (context, index) {
                      final parent = widget.parentCategories[index];
                      final children =
                          widget.childrenByParent[parent.id] ?? [];
                      return _CategoryGroup(
                        parentName: parent.name,
                        parentIcon: _iconForCategory(parent.name,
                            dbIcon: parent.icon),
                        children: children,
                        selectedSubId: widget.selectedSubId,
                        onSelectChild: widget.onSelectChild,
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建分类'),
                onPressed: () => _showCreateDialog(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext sheetContext) {
    showDialog(
      context: sheetContext,
      builder: (ctx) => _CreateCategoryDialog(
        recordType: widget.recordType,
        parentCategories: widget.parentCategories,
        onSelectChild: widget.onSelectChild,
        onCreated: widget.onCategoryCreated,
      ),
    );
  }
}

/// 分类弹窗内新建分类对话框
class _CreateCategoryDialog extends StatefulWidget {
  final String recordType;
  final List<Category> parentCategories;
  final ValueChanged<String> onSelectChild;
  final void Function(String newCategoryId) onCreated;

  const _CreateCategoryDialog({
    required this.recordType,
    required this.parentCategories,
    required this.onSelectChild,
    required this.onCreated,
  });

  @override
  State<_CreateCategoryDialog> createState() => _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends State<_CreateCategoryDialog> {
  String? _selectedParentId;
  bool _isNewParent = false;
  final _parentNameCtrl = TextEditingController();
  final _childNameCtrl = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _parentNameCtrl.dispose();
    _childNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建分类'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String?>(
            value: _isNewParent ? null : _selectedParentId,
            decoration: const InputDecoration(
              labelText: '所属父分类',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              ...widget.parentCategories.map((p) =>
                  DropdownMenuItem(value: p.id, child: Text(p.name))),
              const DropdownMenuItem(
                  value: null, child: Text('+ 新建一级分类')),
            ],
            onChanged: (val) {
              setState(() {
                if (val == null) {
                  _isNewParent = true;
                  _selectedParentId = null;
                } else {
                  _isNewParent = false;
                  _selectedParentId = val;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          if (_isNewParent)
            TextField(
              controller: _parentNameCtrl,
              decoration: const InputDecoration(
                labelText: '一级分类名称',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          if (_isNewParent) const SizedBox(height: 12),
          TextField(
            controller: _childNameCtrl,
            decoration: InputDecoration(
              labelText: _isNewParent ? '二级分类名称（可留空）' : '分类名称',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _doCreate,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('创建'),
        ),
      ],
    );
  }

  Future<void> _doCreate() async {
    final childName = _childNameCtrl.text.trim();
    final parentName = _parentNameCtrl.text.trim();

    if (childName.isEmpty && !_isNewParent) {
      SnackbarUtils.show(context: context, message: '请输入分类名称');
      return;
    }
    if (_isNewParent && parentName.isEmpty && childName.isEmpty) {
      SnackbarUtils.show(context: context, message: '请输入分类名称');
      return;
    }

    setState(() => _isCreating = true);

    try {
      final container = ProviderScope.containerOf(context);
      final dao = container.read(categoryDaoProvider);
      final userId = container.read(currentUserIdProvider);
      final syncQueue = container.read(syncQueueServiceProvider);
      final kind = widget.recordType;

      String? actualParentId = _isNewParent ? null : _selectedParentId;
      String? createdId;

      if (_isNewParent && parentName.isNotEmpty) {
        final parentCatId = IdGenerator.generate();
        await dao.insertCategory(CategoriesCompanion(
          id: Value(parentCatId),
          userId: Value(userId),
          name: Value(parentName),
          kind: Value(kind),
          parentId: const Value.absent(),
          icon: const Value('category'),
        ));
        await syncQueue.enqueue(
          operationType: 'insert',
          tableName: 'categories',
          recordId: parentCatId,
          payload: jsonEncode({
            'id': parentCatId,
            'name': parentName,
            'parent_id': null,
            'icon': 'category',
            'kind': kind,
            'is_archived': false,
          }),
        );
        actualParentId = parentCatId;
        if (childName.isEmpty) createdId = parentCatId;
      }

      if (childName.isNotEmpty) {
        final childCatId = IdGenerator.generate();
        await dao.insertCategory(CategoriesCompanion(
          id: Value(childCatId),
          userId: Value(userId),
          name: Value(childName),
          kind: Value(kind),
          parentId: Value.absentIfNull(actualParentId),
          icon: const Value('category'),
        ));
        await syncQueue.enqueue(
          operationType: 'insert',
          tableName: 'categories',
          recordId: childCatId,
          payload: jsonEncode({
            'id': childCatId,
            'name': childName,
            'parent_id': actualParentId,
            'icon': 'category',
            'kind': kind,
            'is_archived': false,
          }),
        );
        createdId = childCatId;
      }

      syncQueue.processQueue().catchError((_) {});

      if (!mounted) return;
      if (createdId != null) widget.onCreated(createdId);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        SnackbarUtils.show(context: context, message: '创建失败: $e');
      }
    }
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children.map((child) {
              final isSelected = selectedSubId == child.id;
              return _ChildCategoryChip(
                name: child.name,
                icon: _iconForCategory(child.name, dbIcon: child.icon),
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

// ═══════════════════════════════════════════════════════════════
// 分类芯片（横向滑动 + 弹窗内共用）
// ═══════════════════════════════════════════════════════════════

class _ChildCategoryChip extends StatefulWidget {
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
  State<_ChildCategoryChip> createState() => _ChildCategoryChipState();
}

class _ChildCategoryChipState extends State<_ChildCategoryChip>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _bounceCtrl;
  late final Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
        duration: const Duration(milliseconds: 320), vsync: this);
    _bounceAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 4),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.94), weight: 3),
      TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.0), weight: 3),
    ]).animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant _ChildCategoryChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected) {
      _bounceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedBuilder(
        animation: _bounceCtrl,
        builder: (context, child) {
          final scale = widget.selected && _bounceCtrl.isAnimating
              ? _bounceAnim.value
              : _pressed
                  ? 0.92
                  : 1.0;
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.colorScheme.primaryContainer.withAlpha(80)
                : theme.colorScheme.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(12),
            border: widget.selected
                ? Border.all(color: theme.colorScheme.primary, width: 1.8)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 22,
                color: widget.selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                widget.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: widget.selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「更多」分类芯片
class _MoreCategoryChip extends StatefulWidget {
  final VoidCallback onTap;
  const _MoreCategoryChip({required this.onTap});

  @override
  State<_MoreCategoryChip> createState() => _MoreCategoryChipState();
}

class _MoreCategoryChipState extends State<_MoreCategoryChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withAlpha(70),
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.more_horiz_rounded,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(
                '更多',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
  final String title;
  final ValueChanged<String> onSelect;

  const _AccountPickerSheet({
    required this.accounts,
    required this.selectedId,
    this.title = '选择账户',
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: accounts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('暂无可用账户',
                            style: theme.textTheme.bodyMedium),
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
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => onSelect(acct.id),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isSelected
                                  ? theme.colorScheme.primaryContainer
                                      .withAlpha(60)
                                  : theme.colorScheme.surfaceContainerHighest
                                      .withAlpha(30),
                              border: isSelected
                                  ? Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 1.8)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _accountTypeIcon(acct.type),
                                  size: 22,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    acct.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  '¥ ${acct.balance.toStringAsFixed(0)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isSelected)
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check_rounded,
                                        size: 13, color: Colors.white),
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

// ═══════════════════════════════════════════════════════════════
// 数字键盘（精致版）
// ═══════════════════════════════════════════════════════════════

class _Numpad extends StatelessWidget {
  final void Function(String) onKeyTap;
  final bool isSubmitting;
  final bool isEditMode;

  const _Numpad({
    required this.onKeyTap,
    required this.isSubmitting,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 数字行 1-9
          _NumRow(keys: const ['1', '2', '3'], onKeyTap: onKeyTap, theme: theme),
          _NumRow(keys: const ['4', '5', '6'], onKeyTap: onKeyTap, theme: theme),
          _NumRow(keys: const ['7', '8', '9'], onKeyTap: onKeyTap, theme: theme),
          // 最后一行：. / 0 / 完成
          Row(
            children: [
              _NumKey('.', onKeyTap, theme),
              _NumKey('0', onKeyTap, theme),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: FilledButton(
                      onPressed: isSubmitting ? null : () => onKeyTap('完成'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              isEditMode ? '保存' : '完成',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 清空 / 退格
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => onKeyTap('清空'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error.withAlpha(180),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('清空',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => onKeyTap('⌫'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Icon(Icons.backspace_outlined, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumRow extends StatelessWidget {
  final List<String> keys;
  final void Function(String) onKeyTap;
  final ThemeData theme;

  const _NumRow(
      {required this.keys, required this.onKeyTap, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: keys.map((k) => _NumKey(k, onKeyTap, theme)).toList(),
    );
  }
}

class _NumKey extends StatefulWidget {
  final String label;
  final void Function(String) onTap;
  final ThemeData theme;

  const _NumKey(this.label, this.onTap, this.theme);

  @override
  State<_NumKey> createState() => _NumKeyState();
}

class _NumKeyState extends State<_NumKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 52,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap(widget.label);
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 60),
              decoration: BoxDecoration(
                color: _pressed
                    ? widget.theme.colorScheme.surfaceContainerHighest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  color: _pressed
                      ? widget.theme.colorScheme.primary
                      : widget.theme.colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 辅助函数
// ─────────────────────────────────────────────

IconData _accountTypeIcon(String type) {
  switch (type) {
    case 'cash':
      return Icons.money_rounded;
    case 'bank':
      return Icons.account_balance_rounded;
    case 'credit':
      return Icons.credit_card_rounded;
    case 'loan':
      return Icons.real_estate_agent_rounded;
    case 'invest':
      return Icons.trending_up_rounded;
    default:
      return Icons.account_balance_wallet_outlined;
  }
}

IconData _iconForCategory(String name, {String? dbIcon}) {
  return getCategoryIcon(dbIcon: dbIcon, categoryName: name);
}
