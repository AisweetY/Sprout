import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/text_recognition/models/parsed_transaction.dart';
import '../../core/services/text_recognition/text_recognition_provider.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/repository/account_repository.dart';

/// AI 文字识别记账入口
///
/// 打开一个底部输入框，用户打字描述消费，
/// 调用本地规则引擎 + AI 服务进行解析，
/// 展示确认卡片供用户核对后写入。
class AiRecognitionSheet extends ConsumerStatefulWidget {
  const AiRecognitionSheet({super.key});

  @override
  ConsumerState<AiRecognitionSheet> createState() => _AiRecognitionSheetState();
}

class _AiRecognitionSheetState extends ConsumerState<AiRecognitionSheet> {
  final _inputCtrl = TextEditingController();
  bool _isParsing = false;
  ParsedTransaction? _result;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;

    setState(() => _isParsing = true);

    // 获取当前分类和账户列表
    final categories = ref.read(categoryDaoProvider);
    final accounts = ref.read(accountRepositoryProvider);

    final cats = await categories.getActiveCategories();
    final accts = await accounts.getActiveAccounts();

    final catMap = <String, String>{for (final c in cats) c.name: c.id};
    final acctMap = <String, String>{for (final a in accts) a.name: a.id};

    // 调用识别服务
    final service = ref.read(textRecognitionProvider);
    final result = await service.parse(
      userInput: input,
      existingCategories: catMap,
      existingAccounts: acctMap,
    );

    if (mounted) {
      setState(() {
        _isParsing = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖拽指示器
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // 标题
              Text('AI 智能记账', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('用一句话描述这笔消费', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),

              // 输入框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _inputCtrl,
                  autofocus: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '例如：午饭花了50，用支付宝',
                    suffixIcon: IconButton(
                      icon: _isParsing
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      onPressed: _isParsing ? null : _parse,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  onSubmitted: (_) => _parse(),
                ),
              ),

              const SizedBox(height: 16),

              // 解析结果 / 确认卡片
              Expanded(
                child: _result != null
                    ? _ConfirmationCard(
                        result: _result!,
                        onConfirm: () {
                          Navigator.of(context).pop(_result);
                        },
                        onDismiss: () {
                          setState(() => _result = null);
                        },
                      )
                    : Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 18,
                                color: theme.colorScheme.outline),
                            const SizedBox(width: 6),
                            Text('输入描述后点击解析',
                                style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 确认卡片 — 展示 AI 解析结果，每个字段可修改
class _ConfirmationCard extends StatefulWidget {
  final ParsedTransaction result;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _ConfirmationCard({
    required this.result,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  State<_ConfirmationCard> createState() => _ConfirmationCardState();
}

class _ConfirmationCardState extends State<_ConfirmationCard> {
  late String _note;
  late String _type;

  @override
  void initState() {
    super.initState();
    _note = widget.result.note ?? '';
    _type = widget.result.type ?? 'expense';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.result;

    return ListView(
      controller: ScrollController(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // 置信度指示
        Row(
          children: [
            Icon(
              r.confidence >= 0.8
                  ? Icons.check_circle
                  : r.confidence >= 0.5
                      ? Icons.help_outline
                      : Icons.warning_amber_outlined,
              size: 18,
              color: r.confidence >= 0.8
                  ? theme.colorScheme.primary
                  : r.confidence >= 0.5
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text('识别置信度: ${(r.confidence * 100).toInt()}%',
                style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 16),

        // 金额（只读，确认正确性）
        _FieldRow(
          label: '金额',
          value: r.amount != null ? '¥ ${r.amount!.toStringAsFixed(2)}' : '未识别',
          isVerified: r.amount != null,
        ),
        const SizedBox(height: 12),

        // 类型
        Row(
          children: [
            SizedBox(width: 64, child: Text('类型', style: TextStyle(color: theme.colorScheme.outline))),
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('支出')),
                  ButtonSegment(value: 'income', label: Text('收入')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 分类
        _FieldRow(
          label: '分类',
          value: r.categoryName ?? '未识别',
          isVerified: r.categoryId != null,
        ),
        if (r.matchType == MatchType.suggestNew && r.newCategorySuggestion != null) ...[
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.primaryContainer.withAlpha(80),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('建议新增分类「${r.newCategorySuggestion}」',
                        style: theme.textTheme.bodyMedium),
                  ),
                  TextButton(
                    onPressed: () {
                      // TODO: 创建新分类并选中
                    },
                    child: const Text('采纳'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),

        // 账户
        _FieldRow(
          label: '账户',
          value: r.accountHint ?? '默认账户',
          isVerified: r.accountId != null,
        ),
        const SizedBox(height: 12),

        // 备注
        TextField(
          controller: TextEditingController(text: _note),
          decoration: const InputDecoration(
            labelText: '备注',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
          onChanged: (v) => _note = v,
        ),
        const SizedBox(height: 12),

        // 日期
        _FieldRow(
          label: '日期',
          value: r.occurredAt != null
              ? '${r.occurredAt!.month}/${r.occurredAt!.day}'
              : '今天',
          isVerified: true,
        ),
        const SizedBox(height: 24),

        // 操作按钮
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onDismiss,
                child: const Text('重新输入'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: widget.onConfirm,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 18),
                    SizedBox(width: 4),
                    Text('确认记账'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isVerified;

  const _FieldRow({
    required this.label,
    required this.value,
    required this.isVerified,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: TextStyle(color: theme.colorScheme.outline))),
        Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
        Icon(
          isVerified ? Icons.check_circle_outline : Icons.edit_outlined,
          size: 18,
          color: isVerified ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
      ],
    );
  }
}
