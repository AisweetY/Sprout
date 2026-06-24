import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// 应用主题入口 — 提供 [AppTheme.light] 和 [AppTheme.dark]
///
/// 所有颜色通过 [AppColors] 语义变量引用，不在此处硬编码。
/// ThemeData 仅负责 Material 组件的默认样式映射。

class AppTheme {
  AppTheme._();

  /// 亮色主题
  static ThemeData get light {
    final colors = AppColors.light();
    return _buildTheme(colors, Brightness.light);
  }

  /// 暗色主题
  static ThemeData get dark {
    final colors = AppColors.dark();
    return _buildTheme(colors, Brightness.dark);
  }

  static ThemeData _buildTheme(AppColors colors, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: AppColors.white,
      // 选中态/强调容器：浅绿底 + 深绿字（此前未设，回退到实心 accent，
      // 导致「绿底盖绿图标」等对比度问题）
      primaryContainer: colors.accentLight,
      onPrimaryContainer: colors.accentDark,
      secondary: colors.accentLight,
      onSecondary: colors.accent,
      secondaryContainer: colors.accentLight,
      onSecondaryContainer: colors.accentDark,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      // 次要文字/图标色：此前未设，回退到 onSurface（满黑），使所有本应「轻」的
      // 次要元素渲染成与主文字同等重量 → 主次不分明。映射到语义化的次要灰。
      onSurfaceVariant: colors.textSecondary,
      error: colors.danger,
      onError: AppColors.white,
      tertiary: colors.warning,
      surfaceContainerHighest: colors.surfaceVariant,
      outline: colors.border,
      outlineVariant: colors.divider,
    );

    // C1：Noto Sans SC 字体族。fontFamily 设在 ThemeData 级，所有文字自动继承；
    // Google Fonts 首次运行从网络下载后缓存到磁盘，之后离线可用。
    final notoSansSCFamily = GoogleFonts.notoSansSc().fontFamily;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      fontFamily: notoSansSCFamily,

      // C2：全局页面转场改为 Cupertino 水平滑动（iOS 风格），两平台统一
      // 替代 Android 默认的垂直淡入，视觉更连贯、更丝滑
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: colors.surfaceVariant,
      ),

      // ── Card ──
      // elevation: 0.5 + shadowColor 提供轻微深度感，border 用 colors.border（更深）替换
      // divider 以增强卡片与背景的层级区分
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        shadowColor: Colors.black.withAlpha(18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── BottomNavigationBar ──
      // indicatorColor: accentLight（极淡绿）→ accent（实心竹青）提升选中态对比度
      // 选中图标白色，未选中图标次级灰，选中标签加粗竹青
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accent,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white, size: 24);
          }
          return IconThemeData(color: colors.textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: colors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          );
        }),
      ),

      // ── Text ──
      // 金额样式使用等宽数字 (tabularFigures)，防止数字变化时水平抖动
      textTheme: TextTheme(
        displayMedium: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        headlineMedium: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        titleMedium: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        bodyMedium: TextStyle(
          color: colors.textSecondary,
        ),
        bodySmall: TextStyle(
          color: colors.textTertiary,
        ),
      ),

      // ── SegmentedButton ──
      // 竹青调统一：选中态浅绿底+深绿字，未选中态透明底+次要灰字，
      // 替代系统默认（Material 紫调 + 满色选中），与品牌一致
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return colors.accentLight;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return colors.accentDark;
            return colors.textSecondary;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return colors.accentDark;
            return colors.textSecondary;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
      ),

      // ── Divider ──
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 0.5,
        space: 0,
      ),

      // ── FloatingActionButton ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: AppColors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ── ElevatedButton ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // ── FilledButton ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // ── OutlinedButton ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // ── SnackBar ──
      // 亮色：深背景+浅文字；暗色：浅背景+深文字（Material 3 inverseSurface 标准）
      // 原来白底白SnackBar对比度几乎为0，现已修复
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF2A2D2A)
            : const Color(0xFFECEDE9),
        contentTextStyle: TextStyle(
          color: brightness == Brightness.light
              ? const Color(0xFFECEDE9)
              : const Color(0xFF1A1C1A),
        ),
        actionTextColor: colors.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
