import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'membership_models.dart';
import 'membership_provider.dart';

/// 会员中心页
class MembershipCenterScreen extends ConsumerStatefulWidget {
  const MembershipCenterScreen({super.key});

  @override
  ConsumerState<MembershipCenterScreen> createState() =>
      _MembershipCenterScreenState();
}

class _MembershipCenterScreenState extends ConsumerState<MembershipCenterScreen> {
  @override
  void initState() {
    super.initState();
    // 进页面时立即拉取最新会员状态，确保数据不来自过期缓存
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(membershipProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(membershipProvider);
    final skusAsync = ref.watch(membershipSkusProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('会员中心'),
        actions: [
          // 刷新按钮（手动重新加载）
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新状态',
            onPressed: () => ref.read(membershipProvider.notifier).refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(membershipProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // ── 1. 状态卡 ──
            _StatusCard(state: state, theme: theme),
            const SizedBox(height: 20),

            // ── 2. 权益列表 ──
            _BenefitList(theme: theme),
            const SizedBox(height: 20),

            // ── 3. SKU 卡片 ──
            skusAsync.when(
              data: (skus) => skus.isEmpty
                  ? const SizedBox.shrink()
                  : _SkuSection(skus: skus, theme: theme),
              loading: () => const _SkuSkeleton(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // ── 4. 兑换码入口 ──
            _RedeemButton(theme: theme),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 状态卡
// ═══════════════════════════════════════════════════════════════

class _StatusCard extends StatelessWidget {
  final MembershipState state;
  final ThemeData theme;

  const _StatusCard({required this.state, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isActive = state.isActive;
    final info = state.info;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withAlpha(200),
                ]
              : [
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.surfaceContainerHighest.withAlpha(180),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // 图标
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withAlpha(40)
                  : theme.colorScheme.outline.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 30,
              color: isActive ? Colors.white : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          // 文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? info!.planLabel : '熊猫会员',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isActive ? info!.expiryLabel : '开通后解锁全部 AI 功能',
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive
                        ? Colors.white.withAlpha(200)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 状态 badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withAlpha(40)
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isActive ? '生效中' : '未开通',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 权益列表
// ═══════════════════════════════════════════════════════════════

class _BenefitList extends StatelessWidget {
  final ThemeData theme;
  const _BenefitList({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '会员专属权益',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          _BenefitRow(
            icon: Icons.auto_awesome_rounded,
            title: 'AI 记账',
            desc: '语音/文字描述账单，AI 自动解析金额、分类、时间',
            theme: theme,
          ),
          const SizedBox(height: 10),
          _BenefitRow(
            icon: Icons.insights_rounded,
            title: 'AI 小结',
            desc: '每周/月财务小结，洞察消费趋势，私人财富顾问视角',
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final ThemeData theme;

  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withAlpha(80),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SKU 选择区
// ═══════════════════════════════════════════════════════════════

class _SkuSection extends ConsumerStatefulWidget {
  final List<MembershipSku> skus;
  final ThemeData theme;

  const _SkuSection({required this.skus, required this.theme});

  @override
  ConsumerState<_SkuSection> createState() => _SkuSectionState();
}

class _SkuSectionState extends ConsumerState<_SkuSection> {
  late String _selectedSkuCode;

  @override
  void initState() {
    super.initState();
    // 默认选中第一个（通常是月度或推荐项）
    _selectedSkuCode = widget.skus.first.skuCode;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择套餐',
          style: widget.theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: widget.theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...widget.skus.map((sku) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SkuCard(
                sku: sku,
                selected: sku.skuCode == _selectedSkuCode,
                theme: widget.theme,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedSkuCode = sku.skuCode);
                },
              ),
            )),
      ],
    );
  }
}

class _SkuCard extends StatelessWidget {
  final MembershipSku sku;
  final bool selected;
  final ThemeData theme;
  final VoidCallback onTap;

  const _SkuCard({
    required this.sku,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withAlpha(60)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withAlpha(60),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 选中圆圈
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline.withAlpha(120),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // 标题 + 描述
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        sku.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (sku.badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sku.badge!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sku.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 价格
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  sku.priceLabel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                if (sku.originalPriceLabel != null)
                  Text(
                    sku.originalPriceLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  sku.durationLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkuSkeleton extends StatelessWidget {
  const _SkuSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: List.generate(
        3,
        (i) => Container(
          height: 72,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 兑换码入口
// ═══════════════════════════════════════════════════════════════

class _RedeemButton extends ConsumerWidget {
  final ThemeData theme;
  const _RedeemButton({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.card_giftcard_rounded, size: 18),
          label: const Text('兑换码'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _showRedeemSheet(context, ref),
        ),
        const SizedBox(height: 8),
        Text(
          '有兑换码？点击输入后即可开通会员',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showRedeemSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RedeemSheet(onSuccess: () {
        ref.read(membershipProvider.notifier).refresh();
      }),
    );
  }
}

// ─────────────────────────────────────────────
// 兑换码输入底部弹窗
// ─────────────────────────────────────────────

class _RedeemSheet extends StatefulWidget {
  final VoidCallback onSuccess;
  const _RedeemSheet({required this.onSuccess});

  @override
  State<_RedeemSheet> createState() => _RedeemSheetState();
}

class _RedeemSheetState extends State<_RedeemSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部把手
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('输入兑换码', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'PANDA-XXXX-XXXX',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                errorText: _error,
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _error = null);
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('立即兑换',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = '请输入兑换码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'redeem-code',
        body: {'code': code},
      );

      if (!mounted) return;

      final data = res.data;
      final dynamic errorField = data is Map ? data['error'] : null;

      if (errorField != null) {
        setState(() {
          _loading = false;
          _error = _errorMessage(errorField.toString());
        });
        return;
      }

      // 成功：先拿引用，再 pop（pop 后 context.mounted = false，但 messenger 仍有效）
      final messenger = ScaffoldMessenger.of(context);
      if (mounted) Navigator.of(context).pop();
      widget.onSuccess();

      messenger.showSnackBar(
        const SnackBar(
          content: Text('🎉 兑换成功，已开通会员！'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '网络异常，请稍后重试';
        });
      }
    }
  }

  String _errorMessage(String code) {
    switch (code) {
      case 'CODE_INVALID':
        return '兑换码无效、已使用或已过期';
      case 'UNAUTHORIZED':
        return '请先登录后再兑换';
      default:
        return '兑换失败，请稍后重试';
    }
  }
}
