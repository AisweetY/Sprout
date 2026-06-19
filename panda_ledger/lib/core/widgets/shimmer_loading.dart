import 'package:flutter/material.dart';

/// 骨架屏微光动画组件
///
/// 页面加载时替代 CircularProgressIndicator，
/// 提供内容占位 + 微光扫过动画，减少等待焦虑。
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (disableAnimations) {
      // reduced-motion: 直接显示静态占位块
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                theme.colorScheme.surfaceContainerHighest.withAlpha(60),
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value.clamp(0.0, 1.0),
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 页面级骨架屏布局
///
/// 每个页面提供与其实际内容结构一致的骨架占位，
/// 避免加载时出现 "转圈 → 突然出现" 的视觉跳跃。
class PageSkeletons {
  PageSkeletons._();

  /// 首页骨架：英雄卡片 + 储蓄条 + 双列 + 排行
  static Widget home() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 净存款卡片
          _SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 80, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 180, height: 36),
                SizedBox(height: 12),
                Row(
                  children: [
                    ShimmerBox(width: 80, height: 22),
                    SizedBox(width: 16),
                    ShimmerBox(width: 80, height: 22),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          // 储蓄目标
          _SkeletonCard(height: 72),
          SizedBox(height: 16),
          // 净资产行
          _SkeletonCard(height: 64),
          SizedBox(height: 24),
          // 钱去哪了
          ShimmerBox(width: 80, height: 16),
          SizedBox(height: 12),
          _SkeletonBar(),
          _SkeletonBar(),
          _SkeletonBar(),
          _SkeletonBar(),
          _SkeletonBar(),
        ],
      ),
    );
  }

  /// 资产页骨架
  static Widget assets() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _SkeletonCard(height: 120),
          SizedBox(height: 16),
          _SkeletonCard(height: 200),
          SizedBox(height: 24),
          ShimmerBox(width: 80, height: 16),
          SizedBox(height: 12),
          _SkeletonCard(height: 56),
          _SkeletonCard(height: 56),
          _SkeletonCard(height: 56),
        ],
      ),
    );
  }

  /// 分析页骨架
  static Widget insights() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _SkeletonCard(height: 100),
          SizedBox(height: 16),
          _SkeletonCard(height: 80),
          SizedBox(height: 24),
          ShimmerBox(width: 80, height: 16),
          SizedBox(height: 12),
          _SkeletonBar(),
          _SkeletonBar(),
          _SkeletonBar(),
        ],
      ),
    );
  }

  /// 通用列表骨架
  static Widget list({int itemCount = 5}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: List.generate(
          itemCount,
          (_) =>
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: _SkeletonCard(height: 56),
              ),
        ),
      ),
    );
  }
}

/// 骨架卡片容器
class _SkeletonCard extends StatelessWidget {
  final double? height;
  final Widget? child;

  const _SkeletonCard({this.height, this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: height,
      padding: child != null ? const EdgeInsets.all(16) : null,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(60),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

/// 骨架排行条
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ShimmerBox(width: 20, height: 14),
          SizedBox(width: 8),
          ShimmerBox(width: 48, height: 14),
          SizedBox(width: 8),
          Expanded(child: ShimmerBox(height: 12)),
          SizedBox(width: 8),
          ShimmerBox(width: 56, height: 14),
        ],
      ),
    );
  }
}
