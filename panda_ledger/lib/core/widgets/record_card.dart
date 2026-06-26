import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/category_icon_utils.dart';

/// 统一流水卡片组件
///
/// 布局：
///   支出/收入：[图标]  [分类名（大）/ 账户名（小）]    [±¥金额]
///   转 账：    [↔图标] [账户A → 账户B]               [¥金额]
///
/// 点击进入编辑页；左滑删除（可选）。
class RecordCard extends StatefulWidget {
  final String id;
  final String type; // 'expense' / 'income' / 'transfer'
  final double amount;
  final String categoryName;
  final String? categoryIcon;
  final String accountName;
  /// 转账时的目标账户名，传入后卡片呈现 "A → B" 格式
  final String? toAccountName;
  final String? note;
  final VoidCallback onTap;
  /// null = 不显示左滑删除
  final Future<bool> Function()? onDelete;
  final Widget? leading;
  final String syncStatus;
  final DateTime? occurredAt;

  const RecordCard({
    super.key,
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryName,
    this.categoryIcon,
    required this.accountName,
    this.toAccountName,
    this.note,
    required this.onTap,
    this.onDelete,
    this.leading,
    this.syncStatus = 'synced',
    this.occurredAt,
  });

  @override
  State<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<RecordCard> {
  bool _pressed = false;
  bool _dismissThresholdReached = false;

  bool get _showDate {
    if (widget.occurredAt == null) return false;
    final now = DateTime.now();
    return widget.occurredAt!.year != now.year ||
        widget.occurredAt!.month != now.month ||
        widget.occurredAt!.day != now.day;
  }

  String get _dateLabel {
    if (widget.occurredAt == null) return '';
    final now = DateTime.now();
    final d = widget.occurredAt!;
    if (d.year != now.year) return '${d.year}/${d.month}/${d.day}';
    return '${d.month}月${d.day}日';
  }

  /// 金额格式化：整数去掉小数点
  String _formatAmount(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTransfer = widget.type == 'transfer';
    final isExpense = widget.type == 'expense';

    // 转账使用 onSurface（高对比中性色）
    // secondary = accentLight（极浅绿），用于文字/金额时在浅色/深色模式下均几乎不可见
    final color = isExpense
        ? theme.colorScheme.error
        : widget.type == 'income'
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;

    final catIcon = isTransfer
        ? Icons.swap_horiz_rounded
        : getCategoryIcon(
            dbIcon: widget.categoryIcon, categoryName: widget.categoryName);

    // 金额前缀（转账无前缀，支出 -，收入 +）
    final amountPrefix = isTransfer ? '' : (widget.type == 'income' ? '+' : '-');

    // 转账主文字：A → B；否则分类名
    final mainLabel = isTransfer
        ? (widget.toAccountName != null
            ? '${widget.accountName}  →  ${widget.toAccountName}'
            : widget.accountName)
        : widget.categoryName;

    final card = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (h) => setState(() => _pressed = h),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.leading != null) ...[
                      widget.leading!,
                      const SizedBox(width: 8),
                    ],

                    // ── 图标 ──
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(catIcon, size: 20, color: color),
                    ),
                    const SizedBox(width: 10),

                    // ── 文字区（两行：主文字 + 次文字）──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 主文字（分类名 or 转账方向）
                          Text(
                            mainLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                              height: 1.25,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // 次文字：账户名（非转账）
                          if (!isTransfer) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    widget.accountName,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // ── 同步状态 ──
                    if (widget.syncStatus != 'synced')
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          widget.syncStatus == 'conflict'
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_upload_outlined,
                          size: 14,
                          color: widget.syncStatus == 'conflict'
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant.withAlpha(120),
                        ),
                      ),

                    // ── 金额（大字、高对比）──
                    Text(
                      '$amountPrefix¥ ${_formatAmount(widget.amount)}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: -0.4,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),

                // ── 第二行：备注 + 日期标签 ──
                if ((widget.note != null && widget.note!.isNotEmpty) || _showDate) ...[
                  const SizedBox(height: 5),
                  Padding(
                    padding: EdgeInsets.only(
                      left: (widget.leading != null ? 28 : 0) + 46,
                    ),
                    child: Row(
                      children: [
                        if (_showDate) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _dateLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (widget.note != null && widget.note!.isNotEmpty)
                            const SizedBox(width: 6),
                        ],
                        if (widget.note != null && widget.note!.isNotEmpty)
                          Expanded(
                            child: Text(
                              widget.note!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.onDelete != null) {
      return Dismissible(
        key: Key(widget.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          HapticFeedback.heavyImpact();
          return await widget.onDelete!();
        },
        onUpdate: (details) {
          final over = details.progress > 0.5;
          if (over != _dismissThresholdReached) {
            setState(() => _dismissThresholdReached = over);
            if (over) HapticFeedback.selectionClick();
          }
        },
        dismissThresholds: const {DismissDirection.endToStart: 0.5},
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: _dismissThresholdReached
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _dismissThresholdReached ? Icons.check : Icons.delete_outline,
            color: Colors.white,
          ),
        ),
        child: card,
      );
    }

    return card;
  }
}
