import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Configuración global de formato monetario (actualizada por [AppSettingsController]).
class MoneyFormatConfig {
  static String locale = 'es_CL';
  static String symbol = '\$';
  static bool showSymbol = true;
  static String dateLocale = 'es';

  static NumberFormat get numberFormat => NumberFormat('#,##0', locale);
}

const _localeEs = 'es';

String get _activeDateLocale =>
    MoneyFormatConfig.dateLocale.isNotEmpty
        ? MoneyFormatConfig.dateLocale
        : _localeEs;

/// Monto redondeado con separador de miles; incluye símbolo si está configurado.
String formatMoney(double amount) {
  final formatted = MoneyFormatConfig.numberFormat.format(amount.round());
  if (MoneyFormatConfig.showSymbol) {
    return '${MoneyFormatConfig.symbol}$formatted';
  }
  return formatted;
}

/// Texto para campos editables (vacío si el monto es 0).
String formatMoneyField(double amount) {
  if (amount == 0) return '';
  return MoneyFormatConfig.numberFormat.format(amount.round());
}

/// Parsea montos escritos con o sin separador de miles.
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

    final formatted = MoneyFormatConfig.numberFormat.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

const moneyInputFormatters = [MoneyInputFormatter()];

String formatFecha(DateTime fecha) =>
    DateFormat('dd/MM/yyyy', _activeDateLocale).format(fecha);

String formatFechaCorta(DateTime fecha) =>
    DateFormat('dd/MM/yy', _activeDateLocale).format(fecha);

String formatHora(DateTime fecha) =>
    DateFormat('HH:mm', _activeDateLocale).format(fecha);

String formatFechaHora(DateTime fecha) =>
    DateFormat('dd/MM/yyyy HH:mm', _activeDateLocale).format(fecha);

String formatDiaCorto(DateTime fecha) =>
    DateFormat('EEE d/M · HH:mm', _activeDateLocale).format(fecha);

String formatDiaCompleto(DateTime fecha) =>
    DateFormat('EEEE d MMM · HH:mm', _activeDateLocale).format(fecha);

String formatDiaMensaje(DateTime fecha) =>
    capitalize(DateFormat('EEEE d/M', _activeDateLocale).format(fecha));

String formatFechaArchivo(DateTime fecha) =>
    DateFormat('yyyy-MM-dd', _activeDateLocale).format(fecha);

String formatMesDiaHora(DateTime fecha) =>
    DateFormat('dd/MM · HH:mm', _activeDateLocale).format(fecha);

String capitalize(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}

/// Normaliza número para wa.me (solo dígitos, prefijo país si falta).
String? normalizeWhatsAppDigits(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.contains('@')) return null;

  var digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) digits = digits.substring(1);
  // Chile móvil: 9 dígitos empezando en 9 → +56
  if (digits.length == 9 && digits.startsWith('9')) {
    digits = '56$digits';
  }
  if (digits.length < 10) return null;
  return digits;
}

/// Formato legible para mostrar en ficha (ej. +56 9 1234 5678).
String formatWhatsAppDisplay(String? stored) {
  final digits = normalizeWhatsAppDigits(stored);
  if (digits == null) return stored?.trim() ?? '';
  if (digits.startsWith('569') && digits.length == 11) {
    return '+56 ${digits.substring(2, 3)} '
        '${digits.substring(3, 7)} ${digits.substring(7)}';
  }
  return '+$digits';
}

bool esMismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _relativeLocalePhrase({
  required String es,
  required String en,
  required String pt,
}) {
  final locale = _activeDateLocale;
  if (locale.startsWith('pt')) return pt;
  if (locale.startsWith('en')) return en;
  return es;
}

/// Tiempo transcurrido desde [fecha] (ej. "Hace 10 min", "Ayer").
String formatTiempoRelativo(DateTime fecha) {
  final now = DateTime.now();
  final diff = now.difference(fecha);
  if (diff.isNegative) return formatEnCuanto(fecha);
  if (diff.inMinutes < 1) {
    return _relativeLocalePhrase(es: 'Ahora', en: 'Just now', pt: 'Agora');
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return _relativeLocalePhrase(
      es: 'Hace $m min',
      en: '$m min ago',
      pt: 'Há $m min',
    );
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return _relativeLocalePhrase(
      es: 'Hace $h h',
      en: '$h h ago',
      pt: 'Há $h h',
    );
  }
  if (diff.inDays == 1) {
    return _relativeLocalePhrase(es: 'Ayer', en: 'Yesterday', pt: 'Ontem');
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return _relativeLocalePhrase(
      es: 'Hace $d días',
      en: '$d days ago',
      pt: 'Há $d dias',
    );
  }
  return formatDiaCorto(fecha);
}

/// Tiempo hasta [fecha] (ej. "3 horas", "mañana").
String formatEnCuanto(DateTime fecha) {
  final now = DateTime.now();
  final diff = fecha.difference(now);
  if (diff.isNegative) return formatTiempoRelativo(fecha);
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes.clamp(1, 59);
    return _relativeLocalePhrase(
      es: '$m minutos',
      en: '$m minutes',
      pt: '$m minutos',
    );
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return _relativeLocalePhrase(
      es: '$h horas',
      en: '$h hours',
      pt: '$h horas',
    );
  }
  if (diff.inDays == 1) {
    return _relativeLocalePhrase(es: 'mañana', en: 'tomorrow', pt: 'amanhã');
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return _relativeLocalePhrase(
      es: '$d días',
      en: '$d days',
      pt: '$d dias',
    );
  }
  return formatDiaCorto(fecha);
}

/// Saludo corto para mensajes (ej. "Francisco Parra" → "F. P.").
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
