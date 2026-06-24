import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新手引导步骤配置
class _OnboardingStep {
  final String title;
  final String subtitle;
  final Rect Function(Size screenSize) targetRect;
  final Alignment tooltipAlignment;

  const _OnboardingStep({
    required this.title,
    required this.subtitle,
    required this.targetRect,
    this.tooltipAlignment = Alignment.bottomCenter,
  });
}

/// 新手引导半透明遮罩叠加层
///
/// 3 步引导：记一笔 → 净存款 → 分析趋势
/// 使用 Spotlight 风格：暗色遮罩 + 圆形高亮 + 气泡提示
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key});

  /// SharedPreferences 存储键
  static const doneKey = 'onboarding_done';

  /// 是否已完成引导
  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(doneKey) ?? false;
  }

  /// 标记引导完成
  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(doneKey, true);
  }

  /// 重置引导（设置页入口）
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(doneKey);
  }

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late AnimationController _animCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      _animCtrl.reverse().then((_) {
        setState(() => _step++);
        _animCtrl.forward();
      });
    } else {
      _finish();
    }
  }

  void _finish() async {
    await OnboardingOverlay.markDone();
    if (mounted) Navigator.of(context).pop();
  }

  // 步骤定义 — 基于屏幕百分比的定位
  List<_OnboardingStep> get _steps => [
        _OnboardingStep(
          title: '从这里开始',
          subtitle: '点击 + 按钮，记下你的第一笔账',
          targetRect: (size) => Rect.fromCenter(
            center: Offset(size.width / 2, size.height - 36),
            width: 56,
            height: 56,
          ),
          tooltipAlignment: Alignment.topCenter,
        ),
        _OnboardingStep(
          title: '财务健康度',
          subtitle: '每次记账后，这里会展示你的净存款和储蓄进度',
          targetRect: (size) => Rect.fromLTWH(
            16,
            kToolbarHeight + MediaQuery.of(context).padding.top + 16,
            size.width - 32,
            130,
          ),
          tooltipAlignment: Alignment.bottomCenter,
        ),
        _OnboardingStep(
          title: '消费洞察',
          subtitle: '在「分析」里发现消费趋势，AI 帮你读懂每一笔花销',
          targetRect: (size) => Rect.fromCenter(
            center: Offset(size.width * 7 / 8, size.height - 36),
            width: 72,
            height: 48,
          ),
          tooltipAlignment: Alignment.topCenter,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final screenSize = MediaQuery.of(context).size;
    final targetRect = step.targetRect(screenSize);
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          // 点击空白区域进入下一步
          onTap: _next,
          child: CustomPaint(
            painter: _SpotlightPainter(
              spotlightRect: targetRect,
              radius: 12,
            ),
            child: Stack(
              children: [
                // 气泡提示
                _BubbleTooltip(
                  targetRect: targetRect,
                  alignment: step.tooltipAlignment,
                  title: step.title,
                  subtitle: step.subtitle,
                  currentStep: _step,
                  totalSteps: _steps.length,
                  onNext: _next,
                  onSkip: _finish,
                  accentColor: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 暗色遮罩 + 圆形高亮的 Painter
class _SpotlightPainter extends CustomPainter {
  final Rect spotlightRect;
  final double radius;

  _SpotlightPainter({
    required this.spotlightRect,
    this.radius = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          spotlightRect.inflate(8), // 略微放大高亮区域
          Radius.circular(radius + 4),
        ),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      spotlightRect != oldDelegate.spotlightRect;
}

/// 气泡提示组件
class _BubbleTooltip extends StatelessWidget {
  final Rect targetRect;
  final Alignment alignment;
  final String title;
  final String subtitle;
  final int currentStep;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final Color accentColor;

  const _BubbleTooltip({
    required this.targetRect,
    required this.alignment,
    required this.title,
    required this.subtitle,
    required this.currentStep,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTop = alignment == Alignment.bottomCenter;
    final isBottom = alignment == Alignment.topCenter;

    // 计算气泡位置
    double top;
    if (isTop) {
      // 气泡在高亮区域上方
      top = targetRect.top - 160;
      if (top < 40) top = 40;
    } else if (isBottom) {
      // 气泡在高亮区域下方
      top = targetRect.bottom + 20;
      if (top > screenSize.height - 240) top = screenSize.height - 260;
    } else {
      top = targetRect.bottom + 20;
    }

    final leftX = targetRect.center.dx.clamp(180.0, screenSize.width - 28);

    return Positioned(
      top: top,
      left: null,
      right: null,
      child: Transform.translate(
        offset: Offset(leftX - 160, 0),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(40),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 步骤指示器
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totalSteps, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == currentStep ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == currentStep
                          ? accentColor
                          : accentColor.withAlpha(60),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),

              // 标题
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // 说明
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(179),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 按钮行
              Row(
                children: [
                  // 跳过
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('跳过'),
                  ),
                  const Spacer(),

                  // 下一步 / 完成
                  FilledButton(
                    onPressed: onNext,
                    child: Text(
                      currentStep < totalSteps - 1 ? '下一步' : '开始使用',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
