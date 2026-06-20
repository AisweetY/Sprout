import 'package:flutter/material.dart';

/// 分类图标工具模块
///
/// 管理分类图标字符串（DB 存储）到 Material IconData 的映射，
/// 支持 DB 优先 + 名称回退的图标解析策略，以及分类管理页的图标选择器数据。

/// DB 图标字符串 → IconData 映射
///
/// 涵盖种子数据中所有预置图标 + `_iconForCategory()` 中关键词覆盖的图标。
const Map<String, IconData> _iconMapping = {
  // 种子数据预置
  'restaurant': Icons.restaurant,
  'shopping_bag': Icons.shopping_bag,
  'directions_car': Icons.directions_car,
  'movie': Icons.movie,
  'home': Icons.home,
  'favorite': Icons.favorite,
  'more_horiz': Icons.more_horiz,
  'work': Icons.work,
  'card_giftcard': Icons.card_giftcard,
  'trending_up': Icons.trending_up,
  'payments': Icons.payments,
  // _iconForCategory 关键词覆盖（扩展）
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'phone_android': Icons.phone_android,
  'checkroom': Icons.checkroom,
  'pets': Icons.pets,
  'fitness_center': Icons.fitness_center,
  'face': Icons.face,
  'local_cafe': Icons.local_cafe,
  'format_paint': Icons.format_paint,
  'bolt': Icons.bolt,
  'shield': Icons.shield,
  'category': Icons.category,
  'folder': Icons.folder,
  // 补充常用
  'flight': Icons.flight,
  'directions_bus': Icons.directions_bus,
  'local_gas_station': Icons.local_gas_station,
  'local_grocery_store': Icons.local_grocery_store,
  'store': Icons.store,
  'laptop': Icons.laptop,
  'devices': Icons.devices,
  'child_care': Icons.child_care,
  'celebration': Icons.celebration,
  'emoji_transportation': Icons.emoji_transportation,
  'pets_outlined': Icons.pets_outlined, // available since Flutter 3.x
};

/// 预设图标列表（供分类管理页图标选择器使用）
///
/// 每个条目包含 icon 字符串（DB 存储值）、可读中文名、Material IconData。
const List<PresetIcon> presetIconList = [
  PresetIcon('restaurant', '餐饮', Icons.restaurant),
  PresetIcon('local_cafe', '饮品', Icons.local_cafe),
  PresetIcon('shopping_bag', '购物', Icons.shopping_bag),
  PresetIcon('store', '商店', Icons.store),
  PresetIcon('checkroom', '服装', Icons.checkroom),
  PresetIcon('directions_car', '交通', Icons.directions_car),
  PresetIcon('directions_bus', '公交', Icons.directions_bus),
  PresetIcon('local_gas_station', '加油', Icons.local_gas_station),
  PresetIcon('flight', '旅行', Icons.flight),
  PresetIcon('movie', '娱乐', Icons.movie),
  PresetIcon('celebration', '聚会', Icons.celebration),
  PresetIcon('home', '居住', Icons.home),
  PresetIcon('bolt', '水电', Icons.bolt),
  PresetIcon('local_hospital', '医疗', Icons.local_hospital),
  PresetIcon('fitness_center', '健身', Icons.fitness_center),
  PresetIcon('face', '美容', Icons.face),
  PresetIcon('school', '教育', Icons.school),
  PresetIcon('laptop', '数码', Icons.laptop),
  PresetIcon('phone_android', '通讯', Icons.phone_android),
  PresetIcon('pets', '宠物', Icons.pets),
  PresetIcon('child_care', '育儿', Icons.child_care),
  PresetIcon('local_grocery_store', '买菜', Icons.local_grocery_store),
  PresetIcon('format_paint', '日用', Icons.format_paint),
  PresetIcon('work', '工资', Icons.work),
  PresetIcon('payments', '收入', Icons.payments),
  PresetIcon('card_giftcard', '礼金', Icons.card_giftcard),
  PresetIcon('trending_up', '理财', Icons.trending_up),
  PresetIcon('shield', '保险', Icons.shield),
  PresetIcon('favorite', '健康', Icons.favorite),
  PresetIcon('more_horiz', '其他', Icons.more_horiz),
  PresetIcon('folder', '默认', Icons.folder),
];

/// 预设图标条目
class PresetIcon {
  final String iconName; // DB 存储值
  final String displayName; // 中文名
  final IconData iconData;

  const PresetIcon(this.iconName, this.displayName, this.iconData);
}

/// 将 DB 中的 icon 字符串转为 IconData
///
/// 找不到映射时返回 null（调用方应回退到名称匹配）。
IconData? iconFromDbValue(String? iconStr) {
  if (iconStr == null || iconStr.isEmpty) return null;
  return _iconMapping[iconStr];
}

/// 根据分类名称关键词推导图标（回退策略）
///
/// 当 DB 中没有 icon 字段时，用名称做中文关键词匹配。
IconData iconFromCategoryName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('餐') || lower.contains('食') || lower.contains('饭')) {
    return Icons.restaurant;
  }
  if (lower.contains('饮') || lower.contains('茶') || lower.contains('咖啡')) {
    return Icons.local_cafe;
  }
  if (lower.contains('交通') || lower.contains('行') || lower.contains('车')) {
    return Icons.directions_car;
  }
  if (lower.contains('购物') || lower.contains('买')) return Icons.shopping_bag;
  if (lower.contains('娱乐') || lower.contains('玩')) return Icons.movie;
  if (lower.contains('医') || lower.contains('药') || lower.contains('健康')) {
    return Icons.local_hospital;
  }
  if (lower.contains('住') || lower.contains('房') || lower.contains('租')) {
    return Icons.home;
  }
  if (lower.contains('教育') || lower.contains('学') || lower.contains('书')) {
    return Icons.school;
  }
  if (lower.contains('通讯') || lower.contains('手机') || lower.contains('话费')) {
    return Icons.phone_android;
  }
  if (lower.contains('衣') || lower.contains('服') || lower.contains('鞋')) {
    return Icons.checkroom;
  }
  if (lower.contains('工资') || lower.contains('薪')) return Icons.payments;
  if (lower.contains('理财') || lower.contains('投资') || lower.contains('股票')) {
    return Icons.trending_up;
  }
  if (lower.contains('红包') || lower.contains('礼金')) return Icons.card_giftcard;
  if (lower.contains('宠物') || lower.contains('猫') || lower.contains('狗')) {
    return Icons.pets;
  }
  if (lower.contains('运动') || lower.contains('健身')) return Icons.fitness_center;
  if (lower.contains('美') || lower.contains('发') || lower.contains('容')) {
    return Icons.face;
  }
  if (lower.contains('零食') || lower.contains('水') || lower.contains('饮')) {
    return Icons.local_cafe;
  }
  if (lower.contains('日用') || lower.contains('生活')) return Icons.format_paint;
  if (lower.contains('水电') || lower.contains('燃') || lower.contains('物业')) {
    return Icons.bolt;
  }
  if (lower.contains('保险')) return Icons.shield;
  if (lower.contains('加油') || lower.contains('汽油') || lower.contains('充电')) {
    return Icons.local_gas_station;
  }
  if (lower.contains('旅行') || lower.contains('旅游') || lower.contains('机票')) {
    return Icons.flight;
  }
  if (lower.contains('数码') || lower.contains('电子') || lower.contains('电脑')) {
    return Icons.laptop;
  }
  if (lower.contains('买菜') || lower.contains('超市')) return Icons.local_grocery_store;
  if (lower.contains('聚会') || lower.contains('聚')) return Icons.celebration;
  return Icons.category;
}

/// 获取分类图标的统一入口
///
/// 优先使用 DB 中存储的 icon 字符串，找不到时回退到名称关键词推导。
/// 始终返回有效的 IconData（不会返回 null）。
IconData getCategoryIcon({String? dbIcon, required String categoryName}) {
  final fromDb = iconFromDbValue(dbIcon);
  if (fromDb != null) return fromDb;
  return iconFromCategoryName(categoryName);
}
