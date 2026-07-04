import 'package:flutter/material.dart';

import '../constants/expense_icon.dart';
import '../utils/formatters.dart';

/// Gasto compartido editable: icono + texto libre + monto + participantes.
class SharedExpenseEntry {
  final String id;
  final TextEditingController labelCtrl;
  final TextEditingController montoCtrl;
  ExpenseIconKey iconKey;
  final Set<String> participantes;
  String? comprobantePath;

  SharedExpenseEntry({
    required this.id,
    String label = '',
    String monto = '',
    this.iconKey = ExpenseIconKey.general,
    Set<String>? participantes,
    this.comprobantePath,
  })  : labelCtrl = TextEditingController(text: label),
        montoCtrl = TextEditingController(text: monto),
        participantes = participantes ?? {};

  String get label => labelCtrl.text.trim();

  double get monto => parseMoney(montoCtrl.text);

  bool get tieneDatos => label.isNotEmpty || monto > 0;

  void dispose() {
    labelCtrl.dispose();
    montoCtrl.dispose();
  }

  SharedExpenseEntry copyForEdit() => SharedExpenseEntry(
        id: id,
        label: label,
        monto: formatMoneyField(monto),
        iconKey: iconKey,
        participantes: Set.from(participantes),
        comprobantePath: comprobantePath,
      );
}
