import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/categories_table.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(super.db);

  /// 获取所有未归档分类
  Future<List<Category>> getActiveCategories() {
    return (select(db.categories)
          ..where((t) => t.isArchived.equals(false) & t.deleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.kind),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .get();
  }

  /// 获取所有未删除分类（含已归档）
  Future<List<Category>> getAllCategories() {
    return (select(db.categories)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.kind),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .get();
  }

  /// 按类型获取分类
  Future<List<Category>> getCategoriesByKind(String kind) {
    return (select(db.categories)
          ..where((t) => t.kind.equals(kind) & t.isArchived.equals(false) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取一级分类（parent_id 为空）
  Future<List<Category>> getParentCategories(String kind) {
    return (select(db.categories)
          ..where((t) => t.kind.equals(kind) & t.parentId.isNull() & t.isArchived.equals(false) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取某分类的子分类
  Future<List<Category>> getSubCategories(String parentId) {
    return (select(db.categories)
          ..where((t) => t.parentId.equals(parentId) & t.isArchived.equals(false) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取单个分类
  Future<Category?> getById(String id) {
    return (select(db.categories)..where((t) => t.id.equals(id) & t.deleted.equals(false))).getSingleOrNull();
  }

  /// 按名称查找分类
  ///
  /// 使用 LIMIT 1 + get() 替代 getSingleOrNull()，避免多行数据时抛出
  /// "Bad state: Too many elements" 错误（可能由同步竞态或重复创建导致）。
  Future<Category?> getByName(String name, String kind) async {
    final rows = await (select(db.categories)
          ..where((t) => t.name.equals(name) & t.kind.equals(kind) & t.deleted.equals(false))
          ..limit(1))
        .get();
    return rows.isNotEmpty ? rows.first : null;
  }

  /// 检查同层级是否存在同名未删除分类（用于重名校验）
  ///
  /// - [parentId] 为 null 时检查一级分类；非 null 时检查对应父级下的二级分类
  /// - [excludeId] 编辑时传入当前分类 ID，以排除自身
  Future<bool> existsByName(
    String name,
    String kind, {
    String? parentId,
    String? excludeId,
  }) async {
    final rows = await (select(db.categories)
          ..where((t) {
            var expr = t.name.equals(name) &
                t.kind.equals(kind) &
                t.deleted.equals(false) &
                t.isArchived.equals(false);
            if (parentId == null) {
              expr = expr & t.parentId.isNull();
            } else {
              expr = expr & t.parentId.equals(parentId);
            }
            if (excludeId != null) {
              expr = expr & t.id.equals(excludeId).not();
            }
            return expr;
          })
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// 插入分类
  Future<void> insertCategory(Insertable<Category> category) {
    return into(db.categories).insert(category);
  }

  /// 更新分类
  Future<bool> updateCategory(String id, CategoriesCompanion data) {
    return (update(db.categories)..where((t) => t.id.equals(id)))
        .write(data)
        .then((v) => v > 0);
  }

  /// 归档分类
  Future<void> archiveCategory(String id) {
    return (update(db.categories)..where((t) => t.id.equals(id))).write(
      const CategoriesCompanion(isArchived: Value(true)),
    );
  }

  /// 取消归档分类
  Future<void> unarchiveCategory(String id) {
    return (update(db.categories)..where((t) => t.id.equals(id))).write(
      const CategoriesCompanion(isArchived: Value(false)),
    );
  }

  /// 查分类下的未删除流水数量
  Future<int> getRecordCount(String categoryId) async {
    final rows = await db.customSelect(
      'SELECT COUNT(*) as cnt FROM records WHERE category_id = ? AND deleted = 0',
      variables: [Variable.withString(categoryId)],
      readsFrom: {db.records},
    ).get();
    return rows.first.read<int>('cnt');
  }

  /// 查找可迁移的目标分类（归档/清理时使用）
  ///
  /// 一级分类：同 kind+name 的其他活跃（未归档、未删除）一级分类
  /// 二级分类：父级同名 + 自身同名 的其他活跃二级分类
  ///   （即「一级名称和二级名称同时匹配」才算可迁移）
  Future<Category?> findMergeTarget(Category category) async {
    if (category.parentId == null) {
      // 一级分类：找同名活跃一级分类
      final rows = await (select(db.categories)
            ..where((t) =>
                t.name.equals(category.name) &
                t.kind.equals(category.kind) &
                t.parentId.isNull() &
                t.isArchived.equals(false) &
                t.deleted.equals(false) &
                t.id.equals(category.id).not())
            ..limit(1))
          .get();
      return rows.isNotEmpty ? rows.first : null;
    } else {
      // 二级分类 — 两步查找：
      //
      // 步骤 1：优先在同一父级下找同名活跃子分类。
      //   场景：用户归档了「交通 → 公交」后，又在同一个「交通」下新建了「公交」。
      //   此时没有第二个「交通」，只找"其他同名父级"会遗漏。
      final inSameParent = await (select(db.categories)
            ..where((t) =>
                t.name.equals(category.name) &
                t.parentId.equals(category.parentId!) &
                t.isArchived.equals(false) &
                t.deleted.equals(false) &
                t.id.equals(category.id).not())
            ..limit(1))
          .get();
      if (inSameParent.isNotEmpty) return inSameParent.first;

      // 步骤 2：再找「父级同名 + 自身同名」——即存在另一个同名一级分类，
      //   且那个一级分类下有同名子分类（历史重复一级分类的情况）。
      final parent = await getById(category.parentId!);
      if (parent == null) return null;

      final sameNameParents = await (select(db.categories)
            ..where((t) =>
                t.name.equals(parent.name) &
                t.kind.equals(category.kind) &
                t.parentId.isNull() &
                t.isArchived.equals(false) &
                t.deleted.equals(false) &
                t.id.equals(parent.id).not()))
          .get();

      for (final sameParent in sameNameParents) {
        final targets = await (select(db.categories)
              ..where((t) =>
                  t.name.equals(category.name) &
                  t.parentId.equals(sameParent.id) &
                  t.isArchived.equals(false) &
                  t.deleted.equals(false))
              ..limit(1))
            .get();
        if (targets.isNotEmpty) return targets.first;
      }
      return null;
    }
  }

  /// 软删除分类
  Future<void> softDeleteCategory(String id) {
    return (update(db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 移动分类到新父级（更换所属一级分类）
  Future<void> moveCategory(String childId, String newParentId) {
    return (update(db.categories)..where((t) => t.id.equals(childId))).write(
      CategoriesCompanion(
        parentId: Value(newParentId),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// 监听所有活跃分类（Riverpod watch）
  Selectable<Category> watchActiveCategories() {
    return (select(db.categories)
      ..where((t) => t.isArchived.equals(false) & t.deleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm.asc(t.kind),
        (t) => OrderingTerm.asc(t.sortOrder),
      ]));
  }

  /// 监听所有分类（含已归档，用于 Riverpod watch）
  Selectable<Category> watchAllCategories() {
    return (select(db.categories)
      ..where((t) => t.deleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm.asc(t.kind),
        (t) => OrderingTerm.asc(t.sortOrder),
      ]));
  }
}
