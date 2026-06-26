import 'package:flutter/material.dart';

/// 数字键盘（含完成/保存按钮 + 清空/退格）
///
/// 从 record_screen.dart 提取，自包含组件，仅需 [onKeyTap] 回调。
class Numpad extends StatelessWidget {
  final void Function(String) onKeyTap;
  final bool isSubmitting;
  final bool isEditMode;

  const Numpad({
    super.key,
    required this.onKeyTap,
    required this.isSubmitting,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NumRow(keys: const ['1', '2', '3'], onKeyTap: onKeyTap, theme: theme),
          _NumRow(keys: const ['4', '5', '6'], onKeyTap: onKeyTap, theme: theme),
          _NumRow(keys: const ['7', '8', '9'], onKeyTap: onKeyTap, theme: theme),
          Row(
            children: [
              _NumKey('.', onKeyTap, theme),
              _NumKey('0', onKeyTap, theme),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: FilledButton(
                      onPressed: isSubmitting ? null : () => onKeyTap('完成'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isEditMode ? '保存' : '完成',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => onKeyTap('清空'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error.withAlpha(180),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      '清空',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => onKeyTap('⌫'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Icon(Icons.backspace_outlined, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumRow extends StatelessWidget {
  final List<String> keys;
  final void Function(String) onKeyTap;
  final ThemeData theme;

  const _NumRow({
    required this.keys,
    required this.onKeyTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: keys.map((k) => _NumKey(k, onKeyTap, theme)).toList(),
    );
  }
}

class _NumKey extends StatelessWidget {
  final String label;
  final void Function(String) onTap;
  final ThemeData theme;

  const _NumKey(this.label, this.onTap, this.theme);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onTap(label),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
