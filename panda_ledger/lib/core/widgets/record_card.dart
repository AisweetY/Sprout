import 'package:flutter/material.dart';

import '../utils/category_icon_utils.dart';

/// 统一流水卡片组件
///
/// 供首页、历史流水、一口气记账等所有流水展示场景复用。
/// 布局规范：
///   [leading?] [分类图标 32x32]  [分类名 · 账户名]         [金额]  [sync?]
///                               [备注文字（若有，可选）]
///
/// 点击统一进入编辑页（RecordScreen），可选左滑删除。
/// B5：转换为 StatefulWidget，添加按压缩放微动效（0.97 scale on press）。
class RecordCard extends StatefulWidget {
  final String id;
  final String type; // 'expense' / 'income' / 'transfer'
  final double amount;
  final String categoryName;
  final String? categoryIcon; // DB 中 icon 字段值
  final String accountName;
  final String? note;
  final VoidCallback onTap;
  /// 左滑删除回调：返回 true 表示确认删除（卡片滑走），false 表示取消（卡片弹回）。
  /// null = 不显示左滑删除手势。
  final Future<bool> Function()? onDelete;
  final Widget? leading; // 可选前置 widget（如拖拽手柄）
  final String syncStatus; // 'pending' / 'synced' / 'conflict'
  /// 可选：记账日期。非 null 且不是今天时，在备注行旁边显示日期提示
  final DateTime? occurredAt;

  const RecordCard({
    super.key,
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryName,
    this.categoryIcon,
    required this.accountName,
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

  /// 判断 occurredAt 是否与今天不同（年月日任意一项不同），用于决定是否显示日期标签
  bool get _showDate {
    if (widget.occurredAt == null) return false;
    final now = DateTime.now();
    return widget.occurredAt!.year != now.year ||
        widget.occurredAt!.month != now.month ||
        widget.occurredAt!.day != now.day;
  }

  /// 格式化日期为 M月d日 或 yyyy年M月d日（跨年时加年份）
  String get _dateLabel {
    if (widget.occurredAt == null) return '';
    final now = DateTime.now();
    final d = widget.occurredAt!;
    if (d.year != now.year) {
      return '${d.year}年${d.month}月${d.day}日';
    }
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = widget.type == 'expense';
    final prefix = widget.type == 'income'
        ? '+'
        : widget.type == 'transfer'
            ? '↔ '
            : '-';
    final color = isExpense
        ? theme.colorScheme.error
        : widget.type == 'income'
            ? theme.colorScheme.primary
            : theme.colorScheme.secondary;

    final catIcon = getCategoryIcon(
        dbIcon: widget.categoryIcon, categoryName: widget.categoryName);

    // B5: AnimatedScale 包裹整个 Card，按下时轻微缩放提供质感反馈
    final row = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (highlighted) =>
              setState(() => _pressed = highlighted),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 前置 widget（拖拽手柄等）
                    if (widget.leading != null) ...[
                      widget.leading!,
                      const SizedBox(width: 8),
                    ],

                    // 分类图标
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withAlpha(24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(catIcon, size: 18, color: color),
                    ),
                    const SizedBox(width: 10),

                    // 分类名 + 账户名（同一行，视觉区分）
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.categoryName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 分隔符
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '·',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.account_balance_wallet,
                            size: 13,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              widget.accountName,
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

                    const SizedBox(width: 8),

                    // 同步状态指示（仅非 synced 状态显示）
                    if (widget.syncStatus != 'synced')
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          widget.syncStatus == 'conflict'
                              ? Icons.cloud_off
                              : Icons.cloud_upload,
                          size: 16,
                          color: widget.syncStatus == 'conflict'
                              ? theme.colorScheme.error
                              : theme.colorScheme.outline,
                        ),
                      ),

                    // 金额
                    Text(
                      '$prefix¥ ${widget.amount.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),

                // 第二行：备注 + 日期标签（两者均可选，至少有一个才显示该行）
                if ((widget.note != null && widget.note!.isNotEmpty) ||
                    _showDate) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: EdgeInsets.only(
                      left: (widget.leading != null ? 28 : 0) + 42,
                    ),
                    child: Row(
                      children: [
                        // 日期标签（非今天才显示）
                        if (_showDate) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer
                                  .withAlpha(160),
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
                        // 备注
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

    // 左滑删除
    if (widget.onDelete != null) {
      return Dismissible(
        key: Key(widget.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async => await widget.onDelete!(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: row,
      );
    }

    return row;
  }
}
