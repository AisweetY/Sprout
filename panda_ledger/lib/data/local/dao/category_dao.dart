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
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.kind),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .get();
  }

  /// 按类型获取分类
  Future<List<Category>> getCategoriesByKind(String kind) {
    return (select(db.categories)
          ..where((t) => t.kind.equals(kind) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取一级分类（parent_id 为空）
  Future<List<Category>> getParentCategories(String kind) {
    return (select(db.categories)
          ..where((t) => t.kind.equals(kind) & t.parentId.isNull() & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取某分类的子分类
  Future<List<Category>> getSubCategories(String parentId) {
    return (select(db.categories)
          ..where((t) => t.parentId.equals(parentId) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// 获取单个分类
  Future<Category?> getById(String id) {
    return (select(db.categories)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 按名称查找分类
  Future<Category?> getByName(String name, String kind) {
    return (select(db.categories)
          ..where((t) => t.name.equals(name) & t.kind.equals(kind)))
        .getSingleOrNull();
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

  /// 监听所有活跃分类（Riverpod watch）
  Selectable<Category> watchActiveCategories() {
    return (select(db.categories)
      ..where((t) => t.isArchived.equals(false))
      ..orderBy([
        (t) => OrderingTerm.asc(t.kind),
        (t) => OrderingTerm.asc(t.sortOrder),
      ]));
  }
}
