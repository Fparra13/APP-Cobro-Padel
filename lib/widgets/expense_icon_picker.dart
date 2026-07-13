import 'package:flutter/material.dart';

import '../constants/expense_icon.dart';

/// Selector de icono para gastos compartidos.
class ExpenseIconPicker extends StatelessWidget {
  final ExpenseIconKey selected;
  final ValueChanged<ExpenseIconKey>? onSelected;
  final List<ExpenseIconKey> options;

  const ExpenseIconPicker({
    super.key,
    required this.selected,
    this.onSelected,
    this.options = const [
      ExpenseIconKey.court,
      ExpenseIconKey.meat,
      ExpenseIconKey.drink,
      ExpenseIconKey.ball,
      ExpenseIconKey.general,
    ],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onSelected != null;
    return Row(
      children: options.map((key) {
        final isSelected = key == selected;
        final color = key.colorFor(theme);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: isSelected
                ? color.withValues(alpha: enabled ? 0.15 : 0.08)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: enabled ? () => onSelected!(key) : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? color : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Icon(
                  key.icon,
                  color: enabled ? color : color.withValues(alpha: 0.55),
                  size: 22,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
