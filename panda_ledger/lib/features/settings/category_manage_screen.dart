import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/category_icon_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/widgets/error_state_widget.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/category_dedup_service.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_queue_dao_provider.dart';
import '../auth/auth_provider.dart';

// activeCategoriesProvider / allCategoriesProvider 已替换为
// categoriesStreamProvider / allCategoriesStreamProvider（定义在 app_database_provider.dart）
// 使用 StreamProvider 实现响应式监听，数据变更时自动更新 UI

// ─────────────────────────────────────────────────────────────────────────────
// 归档处理计划（归档弹窗内使用）
// ─────────────────────────────────────────────────────────────────────────────

enum _ArchiveAction {
  delete, // 无流水 → 直接软删除
  merge,  // 有流水 + 有同名可迁移目标 → 迁移后软删除
  archive // 有流水 + 无迁移目标 → 正常归档
}

class _ArchivePlan {
  final Category category;
  final int recordCount;
  final Category? mergeTarget; // action == merge 时非 null

  const _ArchivePlan({
    required this.category,
    required this.recordCount,
    this.mergeTarget,
  });

  _ArchiveAction get action {
    if (recordCount == 0) return _ArchiveAction.delete;
    if (mergeTarget != null) return _ArchiveAction.merge;
    return _ArchiveAction.archive;
  }
}

/// 分类管理页面 — 重构版
///
/// 结构：一级标题 + 二级图标网格（和记账选分类弹窗统一视觉）
/// 支持：拖动换一级分类、编辑、归档、已归档恢复
class CategoryManageScreen extends ConsumerStatefulWidget {
  const CategoryManageScreen({super.key});

  @override
  ConsumerState<CategoryManageScreen> createState() => _CategoryManageScreenState();
}

class _CategoryManageScreenState extends ConsumerState<CategoryManageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    // StreamProvider 自动响应数据变更，无需手动 invalidate
    // 保留此方法以供兼容（调用方仍可触发不做任何操作）
  }

  // ═══════════════════════════════════════════════════════════════
  // 同步辅助
  // ═══════════════════════════════════════════════════════════════

  void _syncCategory(String catId, String operation, Map<String, dynamic> payload) {
    final syncQueue = ref.read(syncQueueServiceProvider);
    syncQueue.enqueue(
      operationType: operation,
      tableName: 'categories',
      recordId: catId,
      payload: jsonEncode(payload),
    );
    syncQueue.processQueue().catchError((_) {});
  }

  // ═══════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '支出'),
            Tab(text: '收入'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: '已归档分类',
            onPressed: () => _showArchivedList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        tooltip: '添加分类',
        child: const Icon(Icons.add),
      ),
      body: ref.watch(categoriesStreamProvider).when(
        loading: () => PageSkeletons.list(itemCount: 6),
        error: (e, _) => ErrorStateWidget(
          message: ErrorStateWidget.friendlyMessage(e),
          onRetry: () => ref.invalidate(categoriesStreamProvider),
        ),
        data: (all) => TabBarView(
          controller: _tabController,
          children: [
            _buildCategoryGrid(all.where((c) => c.kind == 'expense').toList()),
            _buildCategoryGrid(all.where((c) => c.kind == 'income').toList()),
          ],
        ),
      ),
    );
  }

  /// 构建分类网格：一级标题 + 二级图标网格
  Widget _buildCategoryGrid(List<Category> categories) {
    final theme = Theme.of(context);
    final parents = categories.where((c) => c.parentId == null).toList();

    if (parents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('暂无分类', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('点击 + 按钮添加', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: parents.expand((parent) {
        final children = categories.where((c) => c.parentId == parent.id).toList();
        return [
          _ParentGroup(
            parent: parent,
            children: children,
            onTapParent: () => _showEditDialog(parent),
            onTapChild: (child) => _showEditDialog(child),
            onAddChild: () => _showAddDialog(parentId: parent.id),
            onArchiveParent: () => _showArchiveDialog(parent),
            onArchiveChild: (child) => _showArchiveDialog(child),
            onChildDragToParent: (child, targetParent) =>
                _moveChildToParent(child, targetParent),
          ),
        ];
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 拖动换父级
  // ═══════════════════════════════════════════════════════════════

  Future<void> _moveChildToParent(Category child, Category newParent) async {
    if (child.parentId == newParent.id) return;

    final dao = ref.read(categoryDaoProvider);
    await dao.moveCategory(child.id, newParent.id);

    // 同步到 Supabase
    _syncCategory(child.id, 'update', {
      'id': child.id,
      'name': child.name,
      'parent_id': newParent.id,
      'icon': child.icon,
      'kind': child.kind,
      'is_archived': false,
    });

    _refresh();
    if (mounted) {
      SnackbarUtils.show(
        context: context,
        message: '「${child.name}」已移至「${newParent.name}」',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 已归档分类列表
  // ═══════════════════════════════════════════════════════════════

  void _showArchivedList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ArchivedCategoriesScreen(
          onRestore: (cat) async {
            final dao = ref.read(categoryDaoProvider);
            await dao.unarchiveCategory(cat.id);
            _syncCategory(cat.id, 'update', {
              'id': cat.id,
              'name': cat.name,
              'parent_id': cat.parentId,
              'icon': cat.icon,
              'kind': cat.kind,
              'is_archived': false,
            });
            _refresh();
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 添加分类弹窗
  // ═══════════════════════════════════════════════════════════════

  void _showAddDialog({String? parentId}) {
    final nameCtrl = TextEditingController();
    final kind = _tabController.index == 0 ? 'expense' : 'income';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String selectedIcon = 'folder';
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  parentId != null ? '添加二级分类' : '添加${kind == 'expense' ? '支出' : '收入'}分类',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '分类名称',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 16),
                Text('选择图标', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                _IconPicker(
                  selectedIcon: selectedIcon,
                  onIconSelected: (icon) {
                    setSheetState(() => selectedIcon = icon);
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      if (ctx.mounted) {
                        SnackbarUtils.showError(context: ctx, message: '请输入分类名称');
                      }
                      return;
                    }
                    final dao = ref.read(categoryDaoProvider);

                    // 层级约束
                    if (parentId != null) {
                      final parent = await dao.getById(parentId);
                      if (parent != null && parent.parentId != null) {
                        if (!ctx.mounted) return;
                        SnackbarUtils.show(
                          context: ctx,
                          message: '只能创建最多两级分类',
                        );
                        return;
                      }
                    }

                    // 重名校验：同层级下不允许同名
                    final isDuplicate = await dao.existsByName(name, kind, parentId: parentId);
                    if (isDuplicate) {
                      if (!ctx.mounted) return;
                      SnackbarUtils.showError(context: ctx, message: '已存在同名分类「$name」');
                      return;
                    }

                    final userId = ref.read(currentUserIdProvider);
                    final catId = IdGenerator.generate();
                    await dao.insertCategory(
                      CategoriesCompanion(
                        id: Value(catId),
                        userId: Value(userId),
                        name: Value(name),
                        kind: Value(kind),
                        parentId: Value.absentIfNull(parentId),
                        icon: Value(selectedIcon),
                      ),
                    );

                    _syncCategory(catId, 'insert', {
                      'id': catId,
                      'name': name,
                      'parent_id': parentId,
                      'icon': selectedIcon,
                      'kind': kind,
                      'is_archived': false,
                    });

                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    _refresh();
                  },
                  child: const Text('创建'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 编辑分类弹窗
  // ═══════════════════════════════════════════════════════════════

  void _showEditDialog(Category category) {
    final nameCtrl = TextEditingController(text: category.name);
    final isParent = category.parentId == null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String selectedIcon = category.icon ?? 'folder';
        String? selectedParentId = category.parentId;

        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('编辑${isParent ? '一级' : '二级'}分类',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '分类名称',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                // 二级分类：可选更换所属一级分类
                if (!isParent) ...[
                  const SizedBox(height: 12),
                  _ParentSelector(
                    kind: category.kind,
                    selectedParentId: selectedParentId,
                    excludeChildId: category.id,
                    onChanged: (pid) {
                      setSheetState(() => selectedParentId = pid);
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Text('选择图标', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                _IconPicker(
                  selectedIcon: selectedIcon,
                  onIconSelected: (icon) {
                    setSheetState(() => selectedIcon = icon);
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      if (ctx.mounted) {
                        SnackbarUtils.showError(context: ctx, message: '请输入分类名称');
                      }
                      return;
                    }
                    final dao = ref.read(categoryDaoProvider);

                    // 重名校验：排除自身，按更新后的层级位置检查
                    final parentIdToCheck = isParent ? null : selectedParentId;
                    final isDuplicate = await dao.existsByName(
                      name,
                      category.kind,
                      parentId: parentIdToCheck,
                      excludeId: category.id,
                    );
                    if (isDuplicate) {
                      if (!ctx.mounted) return;
                      SnackbarUtils.showError(context: ctx, message: '已存在同名分类「$name」');
                      return;
                    }

                    // 如果二级分类更换了父级
                    if (!isParent && selectedParentId != category.parentId) {
                      await dao.moveCategory(category.id, selectedParentId!);
                    }

                    await dao.updateCategory(
                      category.id,
                      CategoriesCompanion(
                        name: Value(name),
                        icon: Value(selectedIcon),
                        parentId: isParent
                            ? const Value.absent()
                            : Value.absentIfNull(selectedParentId),
                      ),
                    );

                    _syncCategory(category.id, 'update', {
                      'id': category.id,
                      'name': name,
                      'parent_id': isParent ? null : selectedParentId,
                      'icon': selectedIcon,
                      'kind': category.kind,
                      'is_archived': false,
                    });

                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    _refresh();
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 归档分类 — 智能判断链
  // ═══════════════════════════════════════════════════════════════

  static const _protectedCategories = {'其他', '其他收入'};

  /// 归档入口：保留分类检查 → 分发到一级/二级流程
  Future<void> _showArchiveDialog(Category category) async {
    if (_protectedCategories.contains(category.name)) {
      final dao = ref.read(categoryDaoProvider);
      final hasDuplicate = await dao.existsByName(
        category.name, category.kind, excludeId: category.id,
      );
      if (!hasDuplicate) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('无法归档'),
            content: Text('「${category.name}」是系统保留分类，不可归档。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
      if (!mounted) return;
    }

    if (category.parentId == null) {
      await _showParentArchiveFlow(category);
    } else {
      await _showChildArchiveFlow(category);
    }
  }

  /// 构建单个分类的处理计划（查流水数量 + 查迁移目标）
  Future<_ArchivePlan> _buildPlan(Category category) async {
    final dao = ref.read(categoryDaoProvider);
    final count = await dao.getRecordCount(category.id);
    final target = count > 0 ? await dao.findMergeTarget(category) : null;
    return _ArchivePlan(category: category, recordCount: count, mergeTarget: target);
  }

  // ─── 二级分类：单计划弹窗 ───────────────────────────────────────

  Future<void> _showChildArchiveFlow(Category category) async {
    final plan = await _buildPlan(category);
    if (!mounted) return;
    _showSinglePlanDialog(plan);
  }

  /// 单个计划弹窗（供二级分类使用）
  void _showSinglePlanDialog(_ArchivePlan plan) {
    final cat = plan.category;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) {
        switch (plan.action) {
          // ── 无流水：直接删除 ──
          case _ArchiveAction.delete:
            return AlertDialog(
              title: const Text('删除分类'),
              content: Text('「${cat.name}」无历史流水，是否直接删除？\n删除后不可恢复。'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _doSoftDelete(cat);
                    if (mounted) SnackbarUtils.show(context: context, message: '已删除「${cat.name}」');
                  },
                  child: const Text('删除'),
                ),
              ],
            );

          // ── 有流水 + 有迁移目标 ──
          case _ArchiveAction.merge:
            final target = plan.mergeTarget!;
            return AlertDialog(
              title: const Text('迁移并删除'),
              content: Text(
                '「${cat.name}」有 ${plan.recordCount} 条历史流水。\n'
                '发现同名分类「${target.name}」可接收，是否将流水迁移过去并删除此分类？',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _doArchive(cat);
                    if (mounted) {
                      SnackbarUtils.showUndo(
                        context: context,
                        message: '已归档「${cat.name}」',
                        onUndo: () => _undoArchive(cat),
                        afterDialogClose: true,
                      );
                    }
                  },
                  child: const Text('仅归档'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await ref.read(categoryDedupServiceProvider)
                        .mergeRecords(from: cat, into: target);
                    if (mounted) SnackbarUtils.show(context: context, message: '已迁移并删除「${cat.name}」');
                  },
                  child: const Text('迁移并删除'),
                ),
              ],
            );

          // ── 有流水 + 无迁移目标：正常归档 ──
          case _ArchiveAction.archive:
            return AlertDialog(
              title: const Text('归档分类'),
              content: Text('「${cat.name}」有 ${plan.recordCount} 条历史流水，归档后历史记录保留，新记录无法选择此分类。'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _doArchive(cat);
                    if (mounted) {
                      SnackbarUtils.showUndo(
                        context: context,
                        message: '已归档「${cat.name}」',
                        onUndo: () => _undoArchive(cat),
                        afterDialogClose: true,
                      );
                    }
                  },
                  child: const Text('归档'),
                ),
              ],
            );
        }
      },
    );
  }

  // ─── 一级分类：多计划预览弹窗 ──────────────────────────────────

  Future<void> _showParentArchiveFlow(Category category) async {
    final dao = ref.read(categoryDaoProvider);
    final children = await dao.getSubCategories(category.id);

    // 并行构建所有计划（子分类各自独立判断 + 自身）
    final allPlans = await Future.wait([
      ...children.map(_buildPlan),
      _buildPlan(category),
    ]);
    if (!mounted) return;

    final childPlans = allPlans.sublist(0, allPlans.length - 1);
    final selfPlan = allPlans.last;

    // 全部都是正常归档 → 用简洁弹窗
    if (allPlans.every((p) => p.action == _ArchiveAction.archive)) {
      _showBulkArchiveDialog(category, childPlans.map((p) => p.category).toList());
      return;
    }

    // 有删除或迁移 → 展示处理计划预览
    _showPlanPreviewDialog(selfPlan: selfPlan, childPlans: childPlans);
  }

  /// 全部正常归档时的简洁确认弹窗（原逻辑）
  void _showBulkArchiveDialog(Category parent, List<Category> children) {
    final childCount = children.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档分类'),
        content: Text(
          childCount > 0
              ? '确定要归档「${parent.name}」及其 $childCount 个子分类吗？\n归档后历史记录保留，新记录无法再选择。'
              : '确定要归档「${parent.name}」吗？\n归档后历史记录保留，新记录无法再选择。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              for (final child in children) {
                await _doArchive(child);
              }
              await _doArchive(parent);
              if (mounted) {
                SnackbarUtils.showUndo(
                  context: context,
                  message: '已归档「${parent.name}」',
                  onUndo: () async {
                    for (final child in children) { await _undoArchive(child); }
                    await _undoArchive(parent);
                  },
                  afterDialogClose: true,
                );
              }
            },
            child: const Text('归档'),
          ),
        ],
      ),
    );
  }

  /// 有删除/迁移操作时的计划预览弹窗
  void _showPlanPreviewDialog({
    required _ArchivePlan selfPlan,
    required List<_ArchivePlan> childPlans,
  }) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('归档「${selfPlan.category.name}」'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (childPlans.isNotEmpty) ...[
                Text('子分类', style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
                const SizedBox(height: 6),
                ...childPlans.map((p) => _PlanRow(plan: p, theme: theme)),
                const Divider(height: 20),
              ],
              Text('一级分类本身', style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
              const SizedBox(height: 6),
              _PlanRow(plan: selfPlan, theme: theme),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // 先执行子分类，再执行自身
              for (final plan in [...childPlans, selfPlan]) {
                await _executePlan(plan);
              }
              if (mounted) {
                SnackbarUtils.show(
                  context: context,
                  message: '已处理「${selfPlan.category.name}」及其子分类',
                );
              }
            },
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
  }

  // ─── 执行单个计划 ───────────────────────────────────────────────

  Future<void> _executePlan(_ArchivePlan plan) async {
    switch (plan.action) {
      case _ArchiveAction.delete:
        await _doSoftDelete(plan.category);
      case _ArchiveAction.merge:
        await ref.read(categoryDedupServiceProvider)
            .mergeRecords(from: plan.category, into: plan.mergeTarget!);
      case _ArchiveAction.archive:
        await _doArchive(plan.category);
    }
  }

  // ─── 基础操作 ───────────────────────────────────────────────────

  /// 软删除分类（调用 dedup service 统一入队）
  Future<void> _doSoftDelete(Category category) async {
    await ref.read(categoryDedupServiceProvider).softDeleteCategory(category);
    _refresh();
  }

  /// 归档分类并入同步队列
  Future<void> _doArchive(Category category) async {
    final dao = ref.read(categoryDaoProvider);
    await dao.archiveCategory(category.id);
    _syncCategory(category.id, 'update', {
      'id': category.id,
      'name': category.name,
      'parent_id': category.parentId,
      'icon': category.icon,
      'kind': category.kind,
      'is_archived': true,
    });
    _refresh();
  }

  /// 撤销归档
  Future<void> _undoArchive(Category category) async {
    final dao = ref.read(categoryDaoProvider);
    await dao.unarchiveCategory(category.id);
    _syncCategory(category.id, 'update', {
      'id': category.id,
      'name': category.name,
      'parent_id': category.parentId,
      'icon': category.icon,
      'kind': category.kind,
      'is_archived': false,
    });
    _refresh();
  }
}

// ═══════════════════════════════════════════════════════════════════
// 一级分类分组组件（标题 + 图标网格）
// ═══════════════════════════════════════════════════════════════════

class _ParentGroup extends StatelessWidget {
  final Category parent;
  final List<Category> children;
  final VoidCallback onTapParent;
  final void Function(Category child) onTapChild;
  final VoidCallback onAddChild;
  final VoidCallback onArchiveParent;
  final void Function(Category child) onArchiveChild;
  final void Function(Category child, Category targetParent) onChildDragToParent;

  const _ParentGroup({
    required this.parent,
    required this.children,
    required this.onTapParent,
    required this.onTapChild,
    required this.onAddChild,
    required this.onArchiveParent,
    required this.onArchiveChild,
    required this.onChildDragToParent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parentIcon = getCategoryIcon(dbIcon: parent.icon, categoryName: parent.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 一级分类标题行
          GestureDetector(
            onTap: onTapParent,
            child: Row(
              children: [
                Icon(parentIcon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  parent.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const Spacer(),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onSelected: (v) {
                    if (v == 'archive') onArchiveParent();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'archive', child: Text('归档')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 二级分类图标网格: 4 列
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...children.map((child) {
                return _DraggableChildChip(
                  child: child,
                  currentParent: parent,
                  onTap: () => onTapChild(child),
                  onArchive: () => onArchiveChild(child),
                  onDragToParent: (target) => onChildDragToParent(child, target),
                );
              }),
              // 轻量添加按钮
              _AddChildButton(onTap: onAddChild),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 可拖动的二级分类图标
// ═══════════════════════════════════════════════════════════════════

class _DraggableChildChip extends StatelessWidget {
  final Category child;
  final Category currentParent;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final void Function(Category targetParent) onDragToParent;

  const _DraggableChildChip({
    required this.child,
    required this.currentParent,
    required this.onTap,
    required this.onArchive,
    required this.onDragToParent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = getCategoryIcon(dbIcon: child.icon, categoryName: child.name);

    return LongPressDraggable<Category>(
      data: child,
      delay: const Duration(milliseconds: 300),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(
                child.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _ChildChip(child: child, onTap: () {}, onArchive: onArchive),
      ),
      child: _ChildChip(child: child, onTap: onTap, onArchive: onArchive),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 二级分类图标
// ═══════════════════════════════════════════════════════════════════

class _ChildChip extends StatelessWidget {
  final Category child;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  const _ChildChip({
    required this.child,
    required this.onTap,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = getCategoryIcon(dbIcon: child.icon, categoryName: child.name);

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) {}, // 被 LongPressDraggable 接管
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(40),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              child.name,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 轻量添加二级分类按钮
// ═══════════════════════════════════════════════════════════════════

class _AddChildButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddChildButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 24, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              '添加',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 一级分类选择器（用于编辑二级分类时更换父级）
// ═══════════════════════════════════════════════════════════════════

class _ParentSelector extends ConsumerWidget {
  final String kind;
  final String? selectedParentId;
  final String? excludeChildId;
  final void Function(String?) onChanged;

  const _ParentSelector({
    required this.kind,
    required this.selectedParentId,
    this.excludeChildId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCats = ref.watch(categoriesStreamProvider);

    return asyncCats.when(
      loading: () => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, s) => const SizedBox.shrink(),
      data: (all) {
        final parents = all.where((c) =>
            c.kind == kind && c.parentId == null && c.id != excludeChildId).toList();

        return DropdownButtonFormField<String>(
          initialValue: selectedParentId,
          decoration: const InputDecoration(
            labelText: '所属一级分类',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
          items: parents.map((p) => DropdownMenuItem(
            value: p.id,
            child: Row(
              children: [
                Icon(getCategoryIcon(dbIcon: p.icon, categoryName: p.name), size: 18),
                const SizedBox(width: 8),
                Text(p.name),
              ],
            ),
          )).toList(),
          onChanged: onChanged,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 图标选择器
// ═══════════════════════════════════════════════════════════════════

class _IconPicker extends StatelessWidget {
  final String selectedIcon;
  final void Function(String iconName) onIconSelected;

  const _IconPicker({
    required this.selectedIcon,
    required this.onIconSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: presetIconList.map((preset) {
            final isSelected = selectedIcon == preset.iconName;
            return InkWell(
              onTap: () => onIconSelected(preset.iconName),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withAlpha(60),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Tooltip(
                  message: preset.displayName,
                  child: Icon(
                    preset.iconData,
                    size: 22,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 归档计划行（处理计划预览弹窗内使用）
// ═══════════════════════════════════════════════════════════════════

class _PlanRow extends StatelessWidget {
  final _ArchivePlan plan;
  final ThemeData theme;

  const _PlanRow({required this.plan, required this.theme});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (plan.action) {
      _ArchiveAction.delete => (
          Icons.delete_outline,
          theme.colorScheme.error,
          '无流水，将删除',
        ),
      _ArchiveAction.merge => (
          Icons.swap_horiz,
          theme.colorScheme.primary,
          '${plan.recordCount} 条流水 → 迁入「${plan.mergeTarget!.name}」后删除',
        ),
      _ArchiveAction.archive => (
          Icons.archive_outlined,
          theme.colorScheme.onSurfaceVariant,
          '${plan.recordCount} 条流水，将归档保留',
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: '${plan.category.name}  ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: label, style: TextStyle(color: color)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 已归档分类列表页面
// ═══════════════════════════════════════════════════════════════════

class _ArchivedCategoriesScreen extends ConsumerStatefulWidget {
  final void Function(Category category) onRestore;

  const _ArchivedCategoriesScreen({required this.onRestore});

  @override
  ConsumerState<_ArchivedCategoriesScreen> createState() =>
      _ArchivedCategoriesScreenState();
}

class _ArchivedCategoriesScreenState
    extends ConsumerState<_ArchivedCategoriesScreen> {
  /// 一键清理：
  ///   - 无流水 → 直接软删除
  ///   - 有流水 + 找到同名活跃迁移目标 → 迁移流水后软删除
  ///   - 有流水 + 无迁移目标 → 跳过（只能手动恢复）
  Future<void> _cleanupEmpty(List<Category> archived) async {
    final dao = ref.read(categoryDaoProvider);
    final dedup = ref.read(categoryDedupServiceProvider);
    var deleted = 0;
    var merged = 0;

    for (final cat in archived) {
      final n = await dao.getRecordCount(cat.id);
      if (n == 0) {
        await dedup.softDeleteCategory(cat);
        deleted++;
      } else {
        final target = await dao.findMergeTarget(cat);
        if (target != null) {
          await dedup.mergeRecords(from: cat, into: target);
          merged++;
        }
      }
    }

    if (mounted) {
      final parts = <String>[];
      if (deleted > 0) parts.add('删除 $deleted 个无流水分类');
      if (merged > 0) parts.add('迁移合并 $merged 个分类');
      SnackbarUtils.show(
        context: context,
        message: parts.isNotEmpty ? '已${parts.join('，')}' : '没有可清理的归档分类',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncCats = ref.watch(allCategoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('已归档分类'),
        actions: [
          asyncCats.maybeWhen(
            data: (all) {
              final archived = all.where((c) => c.isArchived).toList();
              if (archived.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.cleaning_services_outlined),
                tooltip: '清理无流水归档分类',
                onPressed: () => _cleanupEmpty(archived),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: asyncCats.when(
        loading: () => PageSkeletons.list(itemCount: 4),
        error: (e, _) => ErrorStateWidget(
          message: ErrorStateWidget.friendlyMessage(e),
          onRetry: () => ref.invalidate(allCategoriesStreamProvider),
        ),
        data: (all) {
          final archived = all.where((c) => c.isArchived).toList();

          if (archived.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.archive_outlined, size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('没有已归档的分类', style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }

          final expense = archived.where((c) => c.kind == 'expense').toList();
          final income = archived.where((c) => c.kind == 'income').toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (expense.isNotEmpty) ...[
                _ArchivedSectionHeader(title: '支出', theme: theme),
                ...expense.map((c) => _ArchivedCategoryTile(
                      category: c,
                      onRestore: () => widget.onRestore(c),
                    )),
              ],
              if (income.isNotEmpty) ...[
                _ArchivedSectionHeader(title: '收入', theme: theme),
                ...income.map((c) => _ArchivedCategoryTile(
                      category: c,
                      onRestore: () => widget.onRestore(c),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ArchivedSectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;
  const _ArchivedSectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(title, style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 已归档分类 Tile — 异步检测流水数量和可迁移目标
// ═══════════════════════════════════════════════════════════════════

class _ArchivedCategoryTile extends ConsumerStatefulWidget {
  final Category category;
  final VoidCallback onRestore;

  const _ArchivedCategoryTile({
    required this.category,
    required this.onRestore,
  });

  @override
  ConsumerState<_ArchivedCategoryTile> createState() =>
      _ArchivedCategoryTileState();
}

class _ArchivedCategoryTileState extends ConsumerState<_ArchivedCategoryTile> {
  late Future<({int count, Category? target})> _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = _loadStatus();
  }

  Future<({int count, Category? target})> _loadStatus() async {
    final dao = ref.read(categoryDaoProvider);
    final count = await dao.getRecordCount(widget.category.id);
    final target = count > 0 ? await dao.findMergeTarget(widget.category) : null;
    return (count: count, target: target);
  }

  Future<void> _doMerge(Category target) async {
    await ref.read(categoryDedupServiceProvider)
        .mergeRecords(from: widget.category, into: target);
    if (mounted) {
      SnackbarUtils.show(
        context: context,
        message: '已迁移并删除「${widget.category.name}」',
      );
    }
  }

  Future<void> _doDelete() async {
    await ref.read(categoryDedupServiceProvider).softDeleteCategory(widget.category);
    if (mounted) {
      SnackbarUtils.show(context: context, message: '已删除「${widget.category.name}」');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = widget.category;
    final icon = getCategoryIcon(dbIcon: cat.icon, categoryName: cat.name);
    final isParent = cat.parentId == null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: FutureBuilder(
        future: _statusFuture,
        builder: (context, snapshot) {
          // 操作按钮区：加载中时只显示「恢复」
          final trailing = !snapshot.hasData
              ? FilledButton.tonalIcon(
                  onPressed: widget.onRestore,
                  icon: const Icon(Icons.unarchive, size: 16),
                  label: const Text('恢复'),
                )
              : _buildTrailing(theme, snapshot.data!);

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
            title: Text(cat.name),
            subtitle: Text(
              isParent ? '一级分类' : '二级分类',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
            ),
            trailing: trailing,
          );
        },
      ),
    );
  }

  Widget _buildTrailing(ThemeData theme, ({int count, Category? target}) status) {
    // 无流水 → 可删除
    if (status.count == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: widget.onRestore,
            icon: const Icon(Icons.unarchive, size: 16),
            label: const Text('恢复'),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            tooltip: '无流水，直接删除',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除分类'),
                content: Text('「${widget.category.name}」无历史流水，是否删除？'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _doDelete();
                    },
                    child: const Text('删除'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 有流水 + 有迁移目标 → 可迁移并删除
    if (status.target != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: widget.onRestore,
            icon: const Icon(Icons.unarchive, size: 16),
            label: const Text('恢复'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('迁移'),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('迁移并删除'),
                content: Text(
                  '「${widget.category.name}」有 ${status.count} 条流水。\n'
                  '将迁移到「${status.target!.name}」并删除此归档分类，是否确认？',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                  FilledButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _doMerge(status.target!);
                    },
                    child: const Text('确认'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 有流水 + 无迁移目标 → 只能恢复
    return FilledButton.tonalIcon(
      onPressed: widget.onRestore,
      icon: const Icon(Icons.unarchive, size: 16),
      label: const Text('恢复'),
    );
  }
}
