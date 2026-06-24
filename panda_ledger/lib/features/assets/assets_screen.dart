import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/accessibility_utils.dart';
import '../../core/widgets/error_state_widget.dart';
import '../../core/widgets/shimmer_loading.dart';
import 'assets_provider.dart';
import 'net_worth_chart.dart';

/// 资产页 — 核心问题：「我现在总共有多少钱/欠多少钱」
class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  TimeDimension _dimension = TimeDimension.month;
  DateTime? _customStart;
  DateTime? _customEnd;

  AssetsTimeParams _buildParams() => AssetsTimeParams(
        dimension: _dimension,
        customStart: _customStart,
        customEnd: _customEnd,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = _buildParams();
    final asyncData = ref.watch(assetsDataProvider(params));

    return Scaffold(
      appBar: AppBar(title: const Text('资产')),
      body: Column(
        children: [
          // ── 时间维度选择器 ──
          _DimensionSelector(
            selected: _dimension,
            onChanged: (d) => setState(() {
              _dimension = d;
              if (d != TimeDimension.custom) {
                _customStart = null;
                _customEnd = null;
              }
            }),
          ),
          // 自定义日期范围选择
          if (_dimension == TimeDimension.custom)
            _CustomDateRange(
              start: _customStart,
              end: _customEnd,
              onChanged: (s, e) => setState(() {
                _customStart = s;
                _customEnd = e;
              }),
            ),

          // ── 内容区 ──
          Expanded(
            child: asyncData.when(
              skipLoadingOnReload: true,   // 重新加载时保留旧数据，不闪骨架屏
              loading: () => PageSkeletons.assets(),
              error: (e, _) => ErrorStateWidget(
                message: ErrorStateWidget.friendlyMessage(e),
                onRetry: () => ref.invalidate(assetsDataProvider(_buildParams())),
              ),
              data: (data) => _buildContent(context, ref, data, theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, AssetsData data, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        final params = _buildParams();
        ref.invalidate(assetsDataProvider(params));
        await ref.read(assetsDataProvider(params).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── 总资产卡片 ──
          _TotalAssetCard(data: data, theme: theme),
          const SizedBox(height: 16),

          // ── 净资产趋势曲线 ──
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NetWorthChart(
              data: data.snapshots,
              initialPointsToShow: _initialPointsToShow(),
            ),
          ),
          const SizedBox(height: 24),

          // ── 账户列表（按类型分组）──
          if (data.accountGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('还没有账户', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('在设置中创建账户，开始管理资产',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            )
          else
            ..._buildAccountGroups(data, theme),
        ],
      ),
    );
  }

  int _initialPointsToShow() {
    switch (_dimension) {
      case TimeDimension.day:
        return 7;
      case TimeDimension.week:
        return 4;
      case TimeDimension.month:
        return 6;
      case TimeDimension.year:
        return 3;
      case TimeDimension.custom:
        return 6;
    }
  }

  List<Widget> _buildAccountGroups(AssetsData data, ThemeData theme) {
    final groupOrder = ['cash', 'bank', 'credit', 'loan', 'invest', 'other'];

    return groupOrder
        .where((type) => data.accountGroups.containsKey(type))
        .expand((type) {
      final accounts = data.accountGroups[type]!;
      final total = accounts.fold<double>(0, (sum, a) => sum + a.balance);

      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Row(
            children: [
              Icon(AccountTypeConfig.icon(type),
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(AccountTypeConfig.label(type),
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              Text('¥ ${total.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        ...accounts.map((a) => Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: a.isLiability
                      ? theme.colorScheme.error.withAlpha(20)
                      : theme.colorScheme.primary.withAlpha(20),
                  child: Text(
                    a.name.characters.first,
                    style: TextStyle(
                      color: a.isLiability
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(a.name),
                trailing: Text(
                  a.isLiability
                      ? '(-¥ ${a.balance.toStringAsFixed(2)})'
                      : '¥ ${a.balance.toStringAsFixed(2)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: a.isLiability ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            )),
        const SizedBox(height: 8),
      ];
    }).toList();
  }
}

/// 时间维度选择器（固定等宽，无跳动）
class _DimensionSelector extends StatelessWidget {
  final TimeDimension selected;
  final ValueChanged<TimeDimension> onChanged;

  const _DimensionSelector({required this.selected, required this.onChanged});

  static const _items = [
    (TimeDimension.day, '日'),
    (TimeDimension.month, '月'),
    (TimeDimension.year, '年'),
    (TimeDimension.custom, '自定义'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: _items.map((item) {
          final isSelected = selected == item.$1;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: item.$1 == TimeDimension.day ? 0 : 4),
              child: SizedBox(
                height: 36,
                child: Material(
                  color: isSelected
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onChanged(item.$1),
                    child: Center(
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 自定义日期范围选择
class _CustomDateRange extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime start, DateTime end) onChanged;

  const _CustomDateRange({
    required this.start,
    required this.end,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: start ?? DateTime.now().subtract(const Duration(days: 30)),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onChanged(picked, end ?? DateTime.now());
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                start != null
                    ? '${start!.year}/${start!.month.toString().padLeft(2, '0')}/${start!.day.toString().padLeft(2, '0')}'
                    : '开始日期',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('→', style: theme.textTheme.titleMedium),
          ),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: end ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onChanged(start ?? picked.subtract(const Duration(days: 30)), picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                end != null
                    ? '${end!.year}/${end!.month.toString().padLeft(2, '0')}/${end!.day.toString().padLeft(2, '0')}'
                    : '结束日期',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 总资产卡片 — 数字滚动动画
class _TotalAssetCard extends StatelessWidget {
  final AssetsData data;
  final ThemeData theme;
  const _TotalAssetCard({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'netWorthHero',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('净资产', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: data.netWorth),
              duration: AccessibilityUtils.motionDuration(
                  context, const Duration(milliseconds: 800)),
              curve: Curves.easeOut,
              builder: (context, value, _) {
                return Text(
                  '¥ ${value.toStringAsFixed(2)}',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.5,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatColumn(
                  label: '总资产',
                  value: '¥ ${data.totalAssets.toStringAsFixed(0)}',
                  theme: theme,
                ),
                const SizedBox(width: 32),
                _StatColumn(
                  label: '总负债',
                  value: '-¥ ${data.totalLiabilities.toStringAsFixed(0)}',
                  theme: theme,
                  color: data.totalLiabilities > 0
                      ? theme.colorScheme.error
                      : null,
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

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final Color? color;
  const _StatColumn(
      {required this.label,
      required this.value,
      required this.theme,
      this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            )),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
