import 'package:flutter/material.dart';

/// 字体层级定义
///
/// 金额数字：较大字号 + 适中字重 + 等宽数字（避免对齐抖动）
/// 文字标签：次要灰色
/// 建立清晰的视觉主次

class AppTypography {
  /// 等宽数字特性 — 确保金额数字宽度一致、列表对齐
  static const _tabularFigures = FontFeature.tabularFigures();

  // ── 金额展示 ──
  /// 首页大字金额（净存款）
  static TextStyle amountLarge(BuildContext context) {
    return Theme.of(context).textTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: -0.5,
          fontFeatures: [_tabularFigures],
        ) ??
        const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        );
  }

  /// 中等金额（卡片内）
  static TextStyle amountMedium(BuildContext context) {
    return Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w500,
          fontFeatures: [_tabularFigures],
        ) ??
        const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        );
  }

  /// 小金额（列表内）
  static TextStyle amountSmall(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
          fontFeatures: [_tabularFigures],
        ) ??
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        );
  }

  // ── 标签与正文 ──
  static TextStyle label(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
        ) ??
        const TextStyle(fontSize: 14);
  }

  static TextStyle caption(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
        ) ??
        const TextStyle(fontSize: 12);
  }

  // ── 数字键盘 ──
  static TextStyle numpadKey(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w400,
          fontFeatures: [_tabularFigures],
        ) ??
        const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          fontFeatures: [FontFeature.tabularFigures()],
        );
  }
}
