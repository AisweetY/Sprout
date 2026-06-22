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
class RecordCard extends StatelessWidget {
  final String id;
  final String type; // 'expense' / 'income' / 'transfer'
  final double amount;
  final String categoryName;
  final String? categoryIcon; // DB 中 icon 字段值
  final String accountName;
  final String? note;
  final VoidCallback onTap;
  final VoidCallback? onDelete; // null = 不显示左滑删除
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

  /// 判断 occurredAt 是否与今天不同（年月日任意一项不同），用于决定是否显示日期标签
  bool get _showDate {
    if (occurredAt == null) return false;
    final now = DateTime.now();
    return occurredAt!.year != now.year ||
        occurredAt!.month != now.month ||
        occurredAt!.day != now.day;
  }

  /// 格式化日期为 M月d日 或 yyyy年M月d日（跨年时加年份）
  String get _dateLabel {
    if (occurredAt == null) return '';
    final now = DateTime.now();
    final d = occurredAt!;
    if (d.year != now.year) {
      return '${d.year}年${d.month}月${d.day}日';
    }
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = type == 'expense';
    final prefix = type == 'income'
        ? '+'
        : type == 'transfer'
            ? '↔ '
            : '-';
    final color = isExpense
        ? theme.colorScheme.error
        : type == 'income'
            ? theme.colorScheme.primary
            : theme.colorScheme.secondary;

    final catIcon =
        getCategoryIcon(dbIcon: categoryIcon, categoryName: categoryName);

    final row = Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 前置 widget（拖拽手柄等）
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 8),
                  ],

                  // 分类图标
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
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
                            categoryName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 分隔符
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                            accountName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
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
                  if (syncStatus != 'synced')
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        syncStatus == 'conflict'
                            ? Icons.cloud_off
                            : Icons.cloud_upload,
                        size: 14,
                        color: syncStatus == 'conflict'
                            ? theme.colorScheme.error
                            : theme.colorScheme.outline,
                      ),
                    ),

                  // 金额
                  Text(
                    '$prefix¥ ${amount.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),

              // 第二行：备注 + 日期标签（两者均可选，至少有一个才显示该行）
              if ((note != null && note!.isNotEmpty) || _showDate) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.only(
                    left: (leading != null ? 28 : 0) + 42,
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
                        if (note != null && note!.isNotEmpty)
                          const SizedBox(width: 6),
                      ],
                      // 备注
                      if (note != null && note!.isNotEmpty)
                        Expanded(
                          child: Text(
                            note!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
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
    );

    // 左滑删除
    if (onDelete != null) {
      return Dismissible(
        key: Key(id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onDelete!.call();
          return false; // 由调用方处理删除（含二次确认）
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.error,
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
