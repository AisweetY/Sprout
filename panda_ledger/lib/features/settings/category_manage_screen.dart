import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/id_generator.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../auth/auth_provider.dart';

/// 活跃分类列表 Provider — 自动响应数据变化
final activeCategoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(categoryDaoProvider).getActiveCategories();
});

/// 分类管理页面
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
    ref.invalidate(activeCategoriesProvider);
  }

  void _showUndoSnackBar(String message, Future<void> Function() onUndo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: onUndo,
        ),
      ),
    );
  }

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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        icon: const Icon(Icons.add),
        label: const Text('添加分类'),
      ),
      body: ref.watch(activeCategoriesProvider).when(
        loading: () => PageSkeletons.list(itemCount: 6),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (all) => TabBarView(
          controller: _tabController,
          children: [
            _buildList(all.where((c) => c.kind == 'expense').toList()),
            _buildList(all.where((c) => c.kind == 'income').toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Category> categories) {
    final parents = categories.where((c) => c.parentId == null).toList();

    if (parents.isEmpty) {
      return Center(
        child: Text('暂无分类', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: parents.expand((parent) {
        final children = categories.where((c) => c.parentId == parent.id).toList();
        return [
          _CategoryTile(
            category: parent,
            isParent: true,
            onTap: () => _showEditDialog(parent),
            onAddChild: () => _showAddDialog(parentId: parent.id),
            onArchive: () => _showArchiveDialog(parent),
          ),
          ...children.map((child) => _CategoryTile(
                category: child,
                isParent: false,
                onTap: () => _showEditDialog(child),
                onArchive: () => _showArchiveDialog(child),
              )),
        ];
      }).toList(),
    );
  }

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
        return Padding(
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
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final dao = ref.read(categoryDaoProvider);

                  // 层级约束：二级分类的父级必须是一级分类（不能再有父级）
                  if (parentId != null) {
                    final parent = await dao.getById(parentId);
                    if (parent != null && parent.parentId != null) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('只能创建最多两级分类'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                  }

                  final userId = ref.read(currentUserIdProvider);
                  await dao.insertCategory(
                    CategoriesCompanion(
                      id: Value(IdGenerator.generate()),
                      userId: Value(userId),
                      name: Value(name),
                      kind: Value(kind),
                      parentId: Value.absentIfNull(parentId),
                      icon: const Value('folder'),
                    ),
                  );
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  _refresh();
                },
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(Category category) {
    final nameCtrl = TextEditingController(text: category.name);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('编辑分类', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '分类名称',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        final dao = ref.read(categoryDaoProvider);
                        await dao.updateCategory(
                          category.id,
                          CategoriesCompanion(name: Value(name)),
                        );
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        _refresh();
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showArchiveDialog(Category category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档分类'),
        content: Text('确定要归档「${category.name}」吗？\n归档后历史记录保留，新记录无法再选择此分类。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final dao = ref.read(categoryDaoProvider);
              await dao.archiveCategory(category.id);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              _refresh();
              _showUndoSnackBar(
                '已归档「${category.name}」',
                () async {
                  await dao.unarchiveCategory(category.id);
                  _refresh();
                },
              );
            },
            child: const Text('归档'),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final Category category;
  final bool isParent;
  final VoidCallback onTap;
  final VoidCallback? onAddChild;
  final VoidCallback onArchive;

  const _CategoryTile({
    required this.category,
    required this.isParent,
    required this.onTap,
    this.onAddChild,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.only(
        left: isParent ? 16 : 56, right: 16, top: 2, bottom: 2,
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          isParent ? Icons.folder : Icons.label_outline,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        title: Text(category.name),
        dense: !isParent,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isParent && onAddChild != null)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: onAddChild,
                tooltip: '添加二级分类',
              ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'archive') onArchive();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'archive', child: Text('归档')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
