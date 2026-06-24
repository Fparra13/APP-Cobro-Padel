import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

const _localeEs = 'es';

final _numberFormat = NumberFormat('#,##0', 'es_CL');

/// Monto redondeado con separador de miles, sin símbolo de peso.
String formatMoney(double amount) =>
    _numberFormat.format(amount.round());

/// Texto para campos editables (vacío si el monto es 0).
String formatMoneyField(double amount) {
  if (amount == 0) return '';
  return formatMoney(amount);
}

/// Parsea montos escritos con o sin separador de miles (es_CL).
double parseMoney(String text) {
  if (text.trim().isEmpty) return 0;
  final cleaned = text.replaceAll('.', '').replaceAll(',', '').trim();
  return double.tryParse(cleaned) ?? 0;
}

int roundMoney(double amount) => amount.round();

/// Formatea montos mientras el usuario escribe (ej. 50000 → 50.000).
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = _numberFormat.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

const moneyInputFormatters = [MoneyInputFormatter()];

String formatFecha(DateTime fecha) =>
    DateFormat('dd/MM/yyyy', _localeEs).format(fecha);

String formatFechaCorta(DateTime fecha) =>
    DateFormat('dd/MM/yy', _localeEs).format(fecha);

String formatHora(DateTime fecha) =>
    DateFormat('HH:mm', _localeEs).format(fecha);

String formatFechaHora(DateTime fecha) =>
    DateFormat('dd/MM/yyyy HH:mm', _localeEs).format(fecha);

String formatDiaCorto(DateTime fecha) =>
    DateFormat('EEE d/M · HH:mm', _localeEs).format(fecha);

String formatDiaCompleto(DateTime fecha) =>
    DateFormat('EEEE d MMM · HH:mm', _localeEs).format(fecha);

String formatDiaMensaje(DateTime fecha) =>
    capitalize(DateFormat('EEEE d/M', _localeEs).format(fecha));

String formatFechaArchivo(DateTime fecha) =>
    DateFormat('yyyy-MM-dd', _localeEs).format(fecha);

String formatMesDiaHora(DateTime fecha) =>
    DateFormat('dd/MM · HH:mm', _localeEs).format(fecha);

String capitalize(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}

/// Saludo corto para WhatsApp (ej. "Francisco Parra" → "F. P.").
String formatNombreSaludo(String nombre) {
  final partes = nombre
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (partes.isEmpty) return nombre;
  if (partes.length == 1) return partes.first;

  String inicial(String parte) {
    final limpia = parte.replaceAll('.', '').trim();
    return limpia.isEmpty ? '' : limpia[0].toUpperCase();
  }

  return '${inicial(partes.first)}. ${inicial(partes.last)}.';
}

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
