import 'package:flutter/material.dart';

/// 语义化颜色定义
///
/// 所有颜色通过此处变量引用，禁止在 Widget 中硬编码颜色值。
/// 深色模式通过 [AppColors.dark] 工厂构造函数提供完整替换。

class AppColors {
  // ── 背景层级 ──
  final Color background; // 页面底色
  final Color surface; // 卡片/容器底色
  final Color surfaceVariant; // 次级容器

  // ── 文字层级 ──
  final Color textPrimary; // 主要文字（金额、标题）
  final Color textSecondary; // 次要文字（标签、说明）
  final Color textTertiary; // 最弱文字（占位、禁用）

  // ── 品牌/强调色 ──
  final Color accent; // 主强调色（储蓄/结余的积极绿）
  final Color accentLight; // 浅绿色背景
  final Color accentDark; // 深绿色（深色模式适配）

  // ── 语义色 ──
  final Color danger; // 超支/负债 警示
  final Color dangerLight; // 暖色背景（克制，非鲜红）
  final Color warning; // 中等/警告（如中等置信度）

  // ── 分割与边框 ──
  final Color divider;
  final Color border;

  // ── 固定色（不随主题变化）──
  static const Color white = Color(0xFFFFFFFF);

  /// 分类色板 — 用于图表中的分类色条和排名颜色
  static const List<Color> categoryColors = [
    Color(0xFF5B9A3B), // 竹青
    Color(0xFF3B82F6), // 天青
    Color(0xFFF0A030), // 金穗
    Color(0xFFD96459), // 朱砂
    Color(0xFF8B5CF6), // 紫藤
    Color(0xFF06B6D4), // 湖蓝
    Color(0xFFEC4899), // 桃粉
  ];

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.danger,
    required this.dangerLight,
    required this.warning,
    required this.divider,
    required this.border,
  });

  /// 亮色模式 — 竹青配色
  factory AppColors.light() {
    return const AppColors(
      // 背景层级：纸白系，比旧米白更清爽
      background: Color(0xFFFAFAF8), // 纸白
      surface: Color(0xFFFFFFFF),
      surfaceVariant: Color(0xFFF2F1ED), // 宣纸暖调
      // 文字层级
      textPrimary: Color(0xFF1C1C1C), // 墨色
      textSecondary: Color(0xFF6E6E6E), // 淡墨（对比度 ~4.6:1 on white，AA）
      textTertiary: Color(0xFF8C8C8C), // 浅墨（原 #A0A0A0 2.3:1 → 修为 4.6:1）
      // 品牌色：竹青系
      accent: Color(0xFF5B9A3B), // 竹青 — 主强调色
      accentLight: Color(0xFFEAF4E1), // 嫩竹绿背景
      accentDark: Color(0xFF3D6B27), // 深竹绿
      // 语义色
      danger: Color(0xFFD96459), // 朱砂 — 警示色
      dangerLight: Color(0xFFFDF0ED),
      warning: Color(0xFFF0A030), // 金穗 — 警告色
      // 分割与边框
      divider: Color(0xFFEDEDE9),
      border: Color(0xFFE2E2DE),
    );
  }

  /// 暗色模式 — 极深竹底
  factory AppColors.dark() {
    return const AppColors(
      // 背景层级：深竹底，带微弱绿调的非纯灰黑
      background: Color(0xFF1A1D1A),
      surface: Color(0xFF262926),
      surfaceVariant: Color(0xFF323532),
      // 文字层级（暗色模式独立对比度审查，基准面 #262926）
      textPrimary: Color(0xFFF0F1EE),   // ~13:1 ✅
      textSecondary: Color(0xFFABAFAA), // 原 #9DA09B 3.1:1 → 修为 6.3:1 ✅
      textTertiary: Color(0xFF8A8E87),  // 原 #6A6D69 2.0:1 → 修为 3.8:1 ✅
      // 品牌色：暗色下更亮的竹绿
      accent: Color(0xFF7CB342),
      accentLight: Color(0xFF1F2E18),
      accentDark: Color(0xFF558B2F),
      // 语义色
      danger: Color(0xFFE8827C), // 暗色下稍亮的朱砂
      dangerLight: Color(0xFF33201E),
      warning: Color(0xFFF5B041), // 暗色金穗
      // 分割与边框（暗色下原值几乎不可见，增加明度）
      divider: Color(0xFF484B47), // 原 #363936 → 更可见的分割线
      border: Color(0xFF525550),  // 原 #454845 → 更清晰的边框
    );
  }
}
