import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_screen.dart';
import 'membership_center_screen.dart';
import 'membership_provider.dart';

/// 会员门禁
///
/// 调用方式：
/// ```dart
/// if (!await requireMembership(context, ref)) return;
/// // 有会员，继续执行后续逻辑
/// ```
///
/// 返回 true  = 当前用户有效会员，调用方可继续
/// 返回 false = 已弹提示（未登录 / 未开通），调用方应直接 return
Future<bool> requireMembership(BuildContext context, WidgetRef ref) async {
  // 1. 未登录 → 引导登录
  if (ref.read(authStateProvider) != AuthStatus.authenticated) {
    await _showLoginPrompt(context, ref);
    // 登录后再次检查
    return ref.read(membershipProvider).isActive;
  }

  // 2. 先用本地缓存快速判断
  if (ref.read(membershipProvider).isActive) return true;

  // 3. 缓存显示无会员 → 刷新一次（防止缓存过期/首次登录未刷新）
  await ref.read(membershipProvider.notifier).refresh();
  if (ref.read(membershipProvider).isActive) return true;

  // 4. 确认无会员 → 弹付费墙
  if (context.mounted) {
    await _showPaywall(context);
  }
  return false;
}

// ─────────────────────────────────────────────
// 未登录提示
// ─────────────────────────────────────────────

Future<void> _showLoginPrompt(BuildContext context, WidgetRef ref) async {
  final shouldLogin = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.workspace_premium_rounded,
          color: Theme.of(ctx).colorScheme.primary, size: 32),
      title: const Text('登录后使用 AI 功能'),
      content: const Text(
        'AI 记账与 AI 小结是会员专属功能。\n登录账号后即可开通会员。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('暂不'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('去登录'),
        ),
      ],
    ),
  );

  if (shouldLogin == true && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
    // 登录成功后刷新会员状态
    if (ref.read(authStateProvider) == AuthStatus.authenticated) {
      await ref.read(membershipProvider.notifier).refresh();
    }
  }
}

// ─────────────────────────────────────────────
// 付费墙底部弹窗
// ─────────────────────────────────────────────

Future<void> _showPaywall(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _PaywallSheet(),
  );
}

class _PaywallSheet extends StatelessWidget {
  const _PaywallSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 把手
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 图标
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(80),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 34,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '会员专属功能',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开通熊猫会员，解锁 AI 记账与 AI 小结',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // 权益两行
          _BenefitItem(
            icon: Icons.auto_awesome_rounded,
            text: 'AI 记账 — 自然语言描述，自动解析账单',
            theme: theme,
          ),
          const SizedBox(height: 8),
          _BenefitItem(
            icon: Icons.insights_rounded,
            text: 'AI 小结 — 财务洞察，私人顾问视角',
            theme: theme,
          ),
          const SizedBox(height: 24),
          // 开通按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const MembershipCenterScreen()),
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                '立即开通',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '暂不开通',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final ThemeData theme;

  const _BenefitItem({
    required this.icon,
    required this.text,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
