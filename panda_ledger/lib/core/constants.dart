/// 应用全局常量
library;

class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = '熊猫记账';

  /// 默认货币
  static const String defaultCurrency = 'CNY';

  /// 账期起始日（固定每月1日）
  static const int billingCycleStartDay = 1;

  /// 补记最大天数（30天）
  static const int maxBackdateDays = 30;

  /// 分页大小（流水列表）
  static const int pageSize = 50;

  // ── 动效时长（毫秒）──
  static const int animDurationFast = 150;
  static const int animDurationNormal = 300;
  static const int animDurationSlow = 600;

  // ── 触控 ──
  /// 最小点击热区（dp），iOS 44 / Android 48
  static const double minTouchTarget = 48;

  /// 触控元素最小间距
  static const double touchSpacing = 8;

  // ── 间距体系（4dp 步进）──
  /// xs: 紧凑间距（标签与图标、Chip 内边距）
  static const double spacingXs = 4;

  /// sm: 组件内间距（同级元素之间）
  static const double spacingSm = 8;

  /// md: 页面水平 padding / 卡片内 padding
  static const double spacingMd = 16;

  /// lg: 卡片间间距 / 区块间距
  static const double spacingLg = 24;

  /// xl: 大区块间距
  static const double spacingXl = 32;

  /// 2xl: 页面顶部/底部留白
  static const double spacing2xl = 48;

  // ── 圆角 ──
  /// 小圆角（标签、Chip、进度条）
  static const double radiusSm = 8;

  /// 中圆角（卡片、按钮、输入框）
  static const double radiusMd = 12;

  /// 大圆角（Hero 卡片、BottomSheet）
  static const double radiusLg = 16;

  /// 特大圆角（弹窗、Logo 容器）
  static const double radiusXl = 20;

  // ── 反馈 ──
  /// SnackBar 显示时长（秒）
  static const int snackBarDuration = 2;

  /// Undo SnackBar 显示时长（秒），比普通更长
  static const int undoSnackBarDuration = 4;
}

/// 预设默认分类
class DefaultCategories {
  DefaultCategories._();

  /// 支出分类名称列表
  static const List<String> expenseNames = [
    '餐饮', '购物', '交通', '娱乐', '居住', '健康', '其他'
  ];

  /// 支出分类图标
  static const Map<String, String> expenseIcons = {
    '餐饮': 'restaurant',
    '购物': 'shopping_bag',
    '交通': 'directions_car',
    '娱乐': 'movie',
    '居住': 'home',
    '健康': 'favorite',
    '其他': 'more_horiz',
  };

  /// 收入分类名称列表
  static const List<String> incomeNames = [
    '工资', '奖金', '投资收益', '其他收入'
  ];

  /// 收入分类图标
  static const Map<String, String> incomeIcons = {
    '工资': 'work',
    '奖金': 'card_giftcard',
    '投资收益': 'trending_up',
    '其他收入': 'more_horiz',
  };

  /// 二级分类预置（一级分类 → 子分类列表）
  static const Map<String, List<String>> subcategories = {
    '餐饮': ['工作餐', '外卖', '请客', '买菜'],
    '购物': ['日用品', '服装', '数码', '家居'],
    '交通': ['地铁', '打车', '加油', '停车'],
    '娱乐': ['电影', '游戏', '旅行', '运动'],
    '居住': ['房租', '水电', '物业', '维修'],
    '健康': ['看病', '药品', '健身', '体检'],
  };
}
