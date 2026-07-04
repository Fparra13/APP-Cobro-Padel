import 'package:flutter/material.dart';

import '../constants/expense_icon.dart';

/// Selector de icono para gastos compartidos.
class ExpenseIconPicker extends StatelessWidget {
  final ExpenseIconKey selected;
  final ValueChanged<ExpenseIconKey> onSelected;
  final List<ExpenseIconKey> options;

  const ExpenseIconPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.options = const [
      ExpenseIconKey.meat,
      ExpenseIconKey.drink,
      ExpenseIconKey.ball,
      ExpenseIconKey.general,
    ],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: options.map((key) {
        final isSelected = key == selected;
        final color = key.colorFor(theme);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => onSelected(key),
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
                child: Icon(key.icon, color: color, size: 22),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
