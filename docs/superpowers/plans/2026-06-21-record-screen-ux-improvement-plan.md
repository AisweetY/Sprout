# 记一笔页面体验优化 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 解决记一笔页面三个核心痛点：① 分类弹窗内直接新建分类 ② 自定义数字键盘智能显隐 + 侧滑先收键盘 ③ 自动记住上次选择的分类和账户。

**Architecture:** 全部改动集中在 `record_screen.dart`（+ 新增 `shared_preferences` 依赖）。自定义键盘（`_Numpad`）不是系统键盘，通过 boolean 状态控制显隐。`_CategoryPickerSheet` 从 StatelessWidget 重构为 StatefulWidget 以支持内部弹窗。

**Tech Stack:** Flutter 3.44+ / Dart 3.12+ / Drift / Riverpod / shared_preferences

## Global Constraints

- 所有 DB 写操作后必须入 sync_queue 并触发 processQueue
- 颜色通过 `Theme.of(context).colorScheme` 引用，禁止硬编码
- 分类层级约束：最多两级（parentId 空的为一级，非空为二级）
- 本次仅修改 `lib/features/record/record_screen.dart` 和 `pubspec.yaml`
- 修改表定义才需要 `dart run build_runner build`（本次不涉及）

---

## File Structure

| 文件 | 操作 | 职责 |
|---|---|---|
| `panda_ledger/pubspec.yaml` | 修改 | 新增 `shared_preferences` 依赖 |
| `panda_ledger/lib/features/record/record_screen.dart` | 修改 | 三个改动的主实施文件 |

---

### Task 1: 新增 shared_preferences 依赖

**Files:**
- Modify: `panda_ledger/pubspec.yaml`（第 30 行附近）

**Interfaces:**
- Consumes: 无
- Produces: `SharedPreferences` 全局可用

- [ ] **Step 1: 添加依赖**

在 `pubspec.yaml` 的 `dependencies` 块末尾（`share_plus` 之后）添加：

```yaml
  # 本地键值持久化（记住上次选择）
  shared_preferences: ^2.2.0
```

- [ ] **Step 2: 安装**

```bash
cd panda_ledger && flutter pub get
```

Expected: 正常下载无报错。

- [ ] **Step 3: Commit**

```bash
git add panda_ledger/pubspec.yaml panda_ledger/pubspec.lock
git commit -m "chore: add shared_preferences dependency"
```

---

### Task 2: 键盘智能显隐 + PopScope 侧滑拦截

**Files:**
- Modify: `panda_ledger/lib/features/record/record_screen.dart`

**Interfaces:**
- Consumes: 现有 `_Numpad` 组件、`_AmountDisplay` 组件
- Produces: `bool _showNumpad` 状态控制自定义键盘；`_AmountDisplay.onTap` 呼出键盘；`_showCategoryPicker` / `_showAccountPicker` 中收起键盘；`PopScope` 拦截侧滑；`_submitRecord` 成功后收起键盘

- [ ] **Step 1: 新增 `_showNumpad` 状态变量**

在 `_RecordScreenState` 的 `_isSubmitting` 下一行（约第 57 行）添加：

```dart
  bool _showNumpad = true;
```

- [ ] **Step 2: 修改 `_showCategoryPicker` — 打开弹窗时收起键盘**

找到 `_showCategoryPicker()`（约第 213 行），在 `showModalBottomSheet` 前插入 `setState(() => _showNumpad = false);`：

```dart
  void _showCategoryPicker() {
    setState(() => _showNumpad = false);
    showModalBottomSheet(
      // ... 其余不变
```

- [ ] **Step 3: 修改 `_showAccountPicker` — 打开弹窗时收起键盘**

找到 `_showAccountPicker()`（约第 239 行），同样插入：

```dart
  void _showAccountPicker() {
    setState(() => _showNumpad = false);
    showModalBottomSheet(
      // ... 其余不变
```

- [ ] **Step 4: 给 `_AmountDisplay` 添加 `onTap` 回调**

找到 `_AmountDisplay` 类（约第 813 行），修改为：

```dart
class _AmountDisplay extends StatelessWidget {
  final String amount;
  final String recordType;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _AmountDisplay({
    required this.amount,
    required this.recordType,
    required this.theme,
    this.onTap,
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

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
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
      ),
    );
  }
}
```

- [ ] **Step 5: 在 `build()` 中添加 `PopScope`、传递 `onTap`、条件渲染键盘**

修改 `build()` 方法（约第 696 行），用 `PopScope` 包裹 `Scaffold`，`_AmountDisplay` 加 `onTap`，`_Numpad` 加 `if (_showNumpad)`：

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_showNumpad,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showNumpad) {
          setState(() => _showNumpad = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isBatchMode || _isEditMode ? '编辑账单' : '记一笔'),
          actions: _isBatchMode
              ? null
              : [
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
              _AmountDisplay(
                amount: _amount,
                recordType: _recordType,
                theme: theme,
                onTap: () => setState(() => _showNumpad = true),
              ),

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

              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DateRow(date: _occurredAt, onTap: _pickDate, onToday: () => setState(() => _occurredAt = DateTime.now())),
                      const SizedBox(height: 16),

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

                      if (_recordType != 'transfer') ...[
                        _PickerField(
                          label: '选择账户',
                          selectedName: _selectedAccountName,
                          icon: Icons.account_balance_wallet_outlined,
                          onTap: _showAccountPicker,
                        ),
                        const SizedBox(height: 8),
                      ],

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

              if (_showNumpad)
                _Numpad(
                  onKeyTap: _onKeyTap,
                  isSubmitting: _isSubmitting,
                  isEditMode: _isEditMode || _isBatchMode,
                ),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 6: 修改 `_submitRecord` — 提交成功后收起键盘**

在 `_submitRecord()` 中（约第 629 行），`SnackBar` 之前添加 `_showNumpad = false`：

```dart
      HapticFeedback.lightImpact();
      if (mounted) {
        setState(() => _showNumpad = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode ? '已保存修改' : '已记录 ¥$_amount'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
```

- [ ] **Step 7: 静态分析验证**

```bash
cd panda_ledger && flutter analyze lib/features/record/record_screen.dart
```

Expected: No issues found.

- [ ] **Step 8: Commit**

```bash
git add panda_ledger/lib/features/record/record_screen.dart
git commit -m "feat: 记一笔键盘智能显隐 + 侧滑先收键盘"
```

---

### Task 3: 记住上一次选择

**Files:**
- Modify: `panda_ledger/lib/features/record/record_screen.dart`

**Interfaces:**
- Consumes: Task 1 的 `shared_preferences`；Task 2 修改后的 `_RecordScreenState`
- Produces: `_saveLastSelection()` / `_restoreLastSelection()`；修改 `_loadData()` / `_submitRecord()` / `_onTypeChanged()`

- [ ] **Step 1: 添加 `SharedPreferences` import**

在 `record_screen.dart` 文件头 import 区域添加：

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

- [ ] **Step 2: 添加存储 Key 常量**

在 `_RecordScreenState` 类中（状态变量之后）添加：

```dart
  static const _pkType = 'last_record_type';
  static const _pkCat = 'last_category_id';
  static const _pkParentCat = 'last_parent_category_id';
  static const _pkAcct = 'last_account_id';
  static const _pkToAcct = 'last_to_account_id';
```

- [ ] **Step 3: 实现 `_saveLastSelection()`**

在 `_RecordScreenState` 中添加方法（可放在 `_submitRecord` 下方）：

```dart
  Future<void> _saveLastSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pkType, _recordType);
    if (_subcategoryId != null) {
      await prefs.setString(_pkCat, _subcategoryId!);
    } else if (_categoryId != null) {
      await prefs.setString(_pkCat, _categoryId!);
    }
    if (_categoryId != null) {
      await prefs.setString(_pkParentCat, _categoryId!);
    }
    if (_accountId != null) {
      await prefs.setString(_pkAcct, _accountId!);
    }
    if (_toAccountId != null) {
      await prefs.setString(_pkToAcct, _toAccountId!);
    }
  }
```

- [ ] **Step 4: 实现 `_restoreLastSelection()`**

```dart
  /// 从 SharedPreferences 恢复上次选择的分类、账户、类型。
  /// 必须在 _allCategories 和 _accounts 加载完成后调用。
  Future<void> _restoreLastSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final lastType = prefs.getString(_pkType);
    final lastCatId = prefs.getString(_pkCat);
    final lastParentCatId = prefs.getString(_pkParentCat);
    final lastAcctId = prefs.getString(_pkAcct);
    final lastToAcctId = prefs.getString(_pkToAcct);

    bool needRefresh = false;

    // 1. 恢复类型 Tab（如果和当前默认不同）
    if (lastType != null && lastType != _recordType) {
      _recordType = lastType;
      needRefresh = true;
    }

    if (needRefresh) {
      await _refreshCategoriesAsync();
    }

    if (!mounted) return;

    // 2. 恢复分类：优先二级分类，其次一级分类兜底
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
      if (parent != null) {
        setState(() => _categoryId = lastParentCatId);
      }
    }

    // 3. 恢复账户
    if (lastAcctId != null) {
      final acct = _accounts
          .where((a) => a.id == lastAcctId && !a.isArchived)
          .firstOrNull;
      if (acct != null) {
        setState(() => _accountId = lastAcctId);
      }
    }

    // 4. 恢复转账转入账户
    if (lastToAcctId != null && _recordType == 'transfer' && lastToAcctId != _accountId) {
      final toAcct = _accounts
          .where((a) => a.id == lastToAcctId && !a.isArchived)
          .firstOrNull;
      if (toAcct != null) {
        setState(() => _toAccountId = lastToAcctId);
      }
    }
  }
```

- [ ] **Step 5: 修改 `_loadData` — 数据加载完毕后触发恢复**

找到 `_loadData()` 中账户加载的部分（约第 143-152 行），在账户加载 + 默认选中逻辑之后，调用 `_restoreLastSelection()`：

```dart
  void _loadData() {
    final categoryDao = ref.read(categoryDaoProvider);
    final accountRepo = ref.read(accountRepositoryProvider);

    categoryDao.getCategoriesByKind(_recordType).then((cats) {
      if (mounted) {
        setState(() {
          _allCategories = cats;
          _rebuildCategoryGroups();
          if ((_isEditMode || _isBatchMode) && _categoryId != null) {
            final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
            if (cat != null && cat.parentId != null) {
              _subcategoryId = _categoryId;
              _categoryId = cat.parentId;
            }
          }
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
        // 两类数据都到位后恢复上次选择
        _restoreLastSelection();
      }
    });
  }
```

- [ ] **Step 6: 修改 `_submitRecord` — 提交成功后保存选择**

在 `_submitRecord()` 成功分支末尾（`setState(() => _isSubmitting = false);` 之后）添加：

```dart
      setState(() => _isSubmitting = false);

      if (!_isBatchMode) {
        _saveLastSelection();
      }
```

- [ ] **Step 7: 修改 `_onTypeChanged` — 类型切换时保留账户**

找到 `_onTypeChanged`（约第 258 行），移除 `_accountId = null`（如果存在的话——当前代码中类型切换时不清除 `_accountId`，确认一下）并保留现有清查逻辑：

当前 `_onTypeChanged` 内容：
```dart
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
```

确认 `_accountId` 未被清除（当前代码中确实没有清除 `_accountId`），无需改动。分类由于不同 kind 体系不同，保持清除是正确的。

- [ ] **Step 8: 静态分析验证**

```bash
cd panda_ledger && flutter analyze lib/features/record/record_screen.dart
```

Expected: No issues found.

- [ ] **Step 9: Commit**

```bash
git add panda_ledger/lib/features/record/record_screen.dart
git commit -m "feat: 记一笔记住上次选择的分类、账户和类型"
```

---

### Task 4: 分类弹窗内直接新建分类

**Files:**
- Modify: `panda_ledger/lib/features/record/record_screen.dart`

**Interfaces:**
- Consumes: `categoryDaoProvider`, `currentUserIdProvider`, `syncQueueServiceProvider`, `IdGenerator.generate()`
- Produces: `_CategoryPickerSheet`（重构为 `StatefulWidget`）+ `_CreateCategoryDialog`（新组件）+ `_RecordScreenState._onCategoryCreated(String)`（新方法）

**新增 import（文件头）：**

```dart
import 'dart:convert';  // jsonEncode
import '../../data/sync/sync_queue_dao_provider.dart';  // syncQueueServiceProvider
```

- [ ] **Step 1: 修改 `_showCategoryPicker` — 传递新参数**

找到 `_showCategoryPicker` 方法（约第 213 行），修改为传入 `recordType` 和 `onCategoryCreated` 回调：

```dart
  void _showCategoryPicker() {
    setState(() => _showNumpad = false);
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
        },
        onCategoryCreated: _onCategoryCreated,
      ),
    );
  }
```

- [ ] **Step 2: 新增 `_onCategoryCreated` 方法**

在 `_RecordScreenState` 中添加（可放在 `_refreshCategories` 旁边）：

```dart
  /// 分类弹窗中新建分类后的回调：刷新分类列表并自动选中新分类
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
        // 关闭分类选择弹窗
        Navigator.of(context).pop();
      }
    });
  }
```

- [ ] **Step 3: 重构 `_CategoryPickerSheet` 为 StatefulWidget**

替换原有 `_CategoryPickerSheet`（约第 964-1036 行）：

```dart
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
            child: Text('选择分类', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.parentCategories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category_outlined, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('暂无分类，请创建', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.parentCategories.length,
                    itemBuilder: (context, index) {
                      final parent = widget.parentCategories[index];
                      final children = widget.childrenByParent[parent.id] ?? [];
                      return _CategoryGroup(
                        parentName: parent.name,
                        parentIcon: _iconForCategory(parent.name, dbIcon: parent.icon),
                        children: children,
                        selectedSubId: widget.selectedSubId,
                        onSelectChild: widget.onSelectChild,
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
```

- [ ] **Step 4: 新增 `_CreateCategoryDialog` 组件**

在 `_CategoryPickerSheetState` 之后、`_CategoryGroup` 之前插入：

```dart
/// 分类弹窗内直接新建分类的对话框
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
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('新建分类'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 父分类选择 ──
          DropdownButtonFormField<String?>(
            value: _isNewParent ? null : _selectedParentId,
            decoration: const InputDecoration(
              labelText: '所属父分类',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              ...widget.parentCategories.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name),
                  )),
              const DropdownMenuItem(
                value: null,
                child: Text('+ 新建一级分类'),
              ),
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
          // ── 新建一级分类名称（仅当选择「新建」时显示）──
          if (_isNewParent)
            TextField(
              controller: _parentNameCtrl,
              decoration: const InputDecoration(
                labelText: '一级分类名称',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          if (_isNewParent) const SizedBox(height: 12),
          // ── 子分类名称 ──
          TextField(
            controller: _childNameCtrl,
            decoration: InputDecoration(
              labelText: _isNewParent ? '二级分类名称（可留空）' : '分类名称',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('创建'),
        ),
      ],
    );
  }

  Future<void> _doCreate() async {
    final childName = _childNameCtrl.text.trim();
    final parentName = _parentNameCtrl.text.trim();

    // 验证
    if (childName.isEmpty && !_isNewParent) {
      _showSnack('请输入分类名称');
      return;
    }
    if (_isNewParent && parentName.isEmpty && childName.isEmpty) {
      _showSnack('请输入分类名称');
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
      String? createdId; // 最终需要选中的分类 ID

      // 情况 2/3：新建一级分类
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
        syncQueue.enqueue(
          operationType: 'insert',
          tableName: 'categories',
          recordId: parentCatId,
          payload: jsonEncode({
            'id': parentCatId, 'name': parentName, 'parent_id': null,
            'icon': 'category', 'kind': kind, 'is_archived': false,
          }),
        );
        actualParentId = parentCatId;
        if (childName.isEmpty) createdId = parentCatId;
      }

      // 创建子分类（或其下无父分类时直接创建）
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
        syncQueue.enqueue(
          operationType: 'insert',
          tableName: 'categories',
          recordId: childCatId,
          payload: jsonEncode({
            'id': childCatId, 'name': childName, 'parent_id': actualParentId,
            'icon': 'category', 'kind': kind, 'is_archived': false,
          }),
        );
        createdId = childCatId;
      }

      syncQueue.processQueue().catchError((_) {});

      if (!mounted) return;

      // 通知父组件刷新并自动选中
      if (createdId != null) {
        widget.onCreated(createdId);
      }

      Navigator.of(context).pop(); // 关闭创建 Dialog
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        _showSnack('创建失败: $e');
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
```

- [ ] **Step 5: 静态分析**

```bash
cd panda_ledger && flutter analyze lib/features/record/record_screen.dart
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add panda_ledger/lib/features/record/record_screen.dart
git commit -m "feat: 分类弹窗内直接新建分类"
```

---

## Verification Checklist

改完后在实机上验证：

### 改动一
- [ ] 分类弹窗底部有「+ 新建分类」按钮
- [ ] 建已有父分类下的二级分类 → 自动选中
- [ ] 建新一级 + 二级 → 自动选中二级
- [ ] 只建一级 → 自动选中一级
- [ ] 退出记账页后去分类管理能看到新增

### 改动二
- [ ] 打开页面键盘显示
- [ ] 点分类/账户选择器键盘收起
- [ ] 点金额区域键盘弹出
- [ ] 键盘打开时侧滑只收键盘不离开页面
- [ ] 键盘收起后侧滑正常返回

### 改动三
- [ ] 提交后下次打开自动选中上次的分类
- [ ] 自动选中上次的账户
- [ ] 上次分类被删除后不崩溃
- [ ] 转账模式恢复转入账户
