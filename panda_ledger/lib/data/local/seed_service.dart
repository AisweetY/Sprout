import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils/id_generator.dart';
import 'app_database_provider.dart';
import 'database.dart';

/// 种子数据服务
///
/// 首次启动时自动创建预置分类。
final seedServiceProvider = Provider<SeedService>((ref) {
  return SeedService(db: ref.watch(appDatabaseProvider));
});

class SeedService {
  final AppDatabase db;

  SeedService({required this.db});

  /// 检查是否需要初始化种子数据
  Future<bool> needsSeeding() async {
    final rows = await db.select(db.categories).get();
    return rows.isEmpty;
  }

  /// 执行种子数据初始化
  Future<void> seed({required String userId}) async {
    // 创建支出分类
    for (final name in DefaultCategories.expenseNames) {
      final icon = DefaultCategories.expenseIcons[name] ?? 'more_horiz';
      await _createCategory(userId, name, 'expense', icon, null);

      // 创建二级分类
      final subs = DefaultCategories.subcategories[name];
      if (subs != null) {
        final parentId = await _getCategoryId(userId, name, 'expense');
        if (parentId != null) {
          for (final subName in subs) {
            await _createCategory(userId, subName, 'expense', icon, parentId);
          }
        }
      }
    }

    // 创建收入分类
    for (final name in DefaultCategories.incomeNames) {
      final icon = DefaultCategories.incomeIcons[name] ?? 'more_horiz';
      await _createCategory(userId, name, 'income', icon, null);
    }
  }

  Future<void> _createCategory(
    String userId,
    String name,
    String kind,
    String icon,
    String? parentId,
  ) async {
    final id = IdGenerator.generate();
    await db.into(db.categories).insert(
      CategoriesCompanion(
        id: Value(id),
        userId: Value(userId),
        name: Value(name),
        kind: Value(kind),
        icon: Value(icon),
        parentId: Value.absentIfNull(parentId),
      ),
    );
  }

  Future<String?> _getCategoryId(String userId, String name, String kind) async {
    final result = await (db.select(db.categories)
          ..where((t) => t.name.equals(name) & t.kind.equals(kind) & t.parentId.isNull()))
        .getSingleOrNull();
    return result?.id;
  }
}
