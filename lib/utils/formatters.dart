import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _numberFormat = NumberFormat('#,##0', 'es_CL');

/// Monto redondeado con separador de miles, sin símbolo de peso.
String formatMoney(double amount) =>
    _numberFormat.format(amount.round());

int roundMoney(double amount) => amount.round();

/// Etiqueta legible del saldo acumulado del jugador.
String etiquetaSaldo(double saldo) {
  if (saldo > 0) return 'Debe ${formatMoney(saldo)}';
  if (saldo < 0) return 'Saldo a favor: ${formatMoney(-saldo)}';
  return 'Al día';
}

/// Color semántico según el saldo (deuda / al día / a favor).
Color colorSaldo(double saldo) {
  if (saldo > 0) return const Color(0xFFC62828);
  if (saldo < 0) return const Color(0xFF1565C0);
  return const Color(0xFF2E7D32);
}

bool tieneDeuda(double saldo) => saldo > 0;

bool tieneSaldoAFavor(double saldo) => saldo < 0;
