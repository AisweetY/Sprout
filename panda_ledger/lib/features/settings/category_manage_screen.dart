import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/category_icon_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_queue_dao_provider.dart';
import '../auth/auth_provider.dart';

// activeCategoriesProvider / allCategoriesProvider 已替换为
// categoriesStreamProvider / allCategoriesStreamProvider（定义在 app_database_provider.dart）
// 使用 StreamProvider 实现响应式监听，数据变更时自动更新 UI

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
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _showAddDialog(),
        tooltip: '添加分类',
        child: const Icon(Icons.add),
      ),
      body: ref.watch(categoriesStreamProvider).when(
        loading: () => PageSkeletons.list(itemCount: 6),
        error: (e, _) => Center(child: Text('加载失败：$e')),
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
                    if (name.isEmpty) return;
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
                    if (name.isEmpty) return;
                    final dao = ref.read(categoryDaoProvider);

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
  // 归档分类弹窗
  // ═══════════════════════════════════════════════════════════════

  static const _protectedCategories = {'其他', '其他收入'};

  void _showArchiveDialog(Category category) {
    if (_protectedCategories.contains(category.name)) {
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

    final isParent = category.parentId == null;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档分类'),
        content: Text(
          isParent
              ? '确定要归档「${category.name}」及其所有子分类吗？\n归档后历史记录保留，新记录无法再选择此分类。'
              : '确定要归档「${category.name}」吗？\n归档后历史记录保留，新记录无法再选择此分类。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final dao = ref.read(categoryDaoProvider);
              await dao.archiveCategory(category.id);

              // 如果是一级分类，同时归档其所有子分类
              if (isParent) {
                final children = await dao.getSubCategories(category.id);
                for (final child in children) {
                  await dao.archiveCategory(child.id);
                  _syncCategory(child.id, 'update', {
                    'id': child.id,
                    'name': child.name,
                    'parent_id': child.parentId,
                    'icon': child.icon,
                    'kind': child.kind,
                    'is_archived': true,
                  });
                }
              }

              _syncCategory(category.id, 'update', {
                'id': category.id,
                'name': category.name,
                'parent_id': category.parentId,
                'icon': category.icon,
                'kind': category.kind,
                'is_archived': true,
              });

              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              _refresh();
              if (mounted) {
                SnackbarUtils.showUndo(
                  context: context,
                  message: '已归档「${category.name}」',
                  onUndo: () async {
                    await dao.unarchiveCategory(category.id);
                    if (isParent) {
                      final children = await dao.getSubCategories(category.id);
                      for (final child in children) {
                        await dao.unarchiveCategory(child.id);
                        _syncCategory(child.id, 'update', {
                          'id': child.id,
                          'name': child.name,
                          'parent_id': child.parentId,
                          'icon': child.icon,
                          'kind': child.kind,
                          'is_archived': false,
                        });
                      }
                    }
                    _syncCategory(category.id, 'update', {
                      'id': category.id,
                      'name': category.name,
                      'parent_id': category.parentId,
                      'icon': category.icon,
                      'kind': category.kind,
                      'is_archived': false,
                    });
                    _refresh();
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
                Icon(Icons.edit_outlined, size: 14, color: theme.colorScheme.outline),
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
            Icon(Icons.add, size: 24, color: theme.colorScheme.outline),
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
// 已归档分类列表页面
// ═══════════════════════════════════════════════════════════════════

class _ArchivedCategoriesScreen extends ConsumerWidget {
  final void Function(Category category) onRestore;

  const _ArchivedCategoriesScreen({required this.onRestore});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncCats = ref.watch(allCategoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('已归档分类')),
      body: asyncCats.when(
        loading: () => PageSkeletons.list(itemCount: 4),
        error: (e, _) => Center(child: Text('加载失败：$e')),
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

          // 按 kind 分组
          final expense = archived.where((c) => c.kind == 'expense').toList();
          final income = archived.where((c) => c.kind == 'income').toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (expense.isNotEmpty) ...[
                _ArchivedSectionHeader(title: '支出', theme: theme),
                ...expense.map((c) => _ArchivedCategoryTile(
                      category: c,
                      onRestore: () => onRestore(c),
                    )),
              ],
              if (income.isNotEmpty) ...[
                _ArchivedSectionHeader(title: '收入', theme: theme),
                ...income.map((c) => _ArchivedCategoryTile(
                      category: c,
                      onRestore: () => onRestore(c),
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

class _ArchivedCategoryTile extends StatelessWidget {
  final Category category;
  final VoidCallback onRestore;

  const _ArchivedCategoryTile({
    required this.category,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = getCategoryIcon(dbIcon: category.icon, categoryName: category.name);
    final isParent = category.parentId == null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(icon, size: 18, color: theme.colorScheme.outline),
        ),
        title: Text(category.name),
        subtitle: Text(isParent ? '一级分类' : '二级分类',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 12)),
        trailing: FilledButton.tonalIcon(
          onPressed: onRestore,
          icon: const Icon(Icons.unarchive, size: 16),
          label: const Text('恢复'),
        ),
      ),
    );
  }
}
