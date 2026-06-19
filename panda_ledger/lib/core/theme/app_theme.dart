import 'package:flutter/material.dart';

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
      secondary: colors.accentLight,
      onSecondary: colors.accent,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      error: colors.danger,
      onError: AppColors.white,
      tertiary: colors.warning,
      surfaceContainerHighest: colors.surfaceVariant,
      outline: colors.border,
      outlineVariant: colors.divider,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: colors.surfaceVariant,
      ),

      // ── Card ──
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.divider, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── BottomNavigationBar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accentLight,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surface,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
