import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Configuración global de formato monetario (actualizada por [AppSettingsController]).
class MoneyFormatConfig {
  static String locale = 'es_CL';
  static String symbol = '\$';
  static bool showSymbol = true;
  static String dateLocale = 'es';
  static int decimalDigits = 0;

  static NumberFormat get numberFormat {
    if (decimalDigits <= 0) {
      return NumberFormat('#,##0', locale);
    }
    final frac = List.filled(decimalDigits, '0').join();
    return NumberFormat('#,##0.$frac', locale);
  }

  static String get decimalSeparator =>
      NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

  static String get groupSeparator =>
      NumberFormat.decimalPattern(locale).symbols.GROUP_SEP;
}

const _localeEs = 'es';

String get _activeDateLocale =>
    MoneyFormatConfig.dateLocale.isNotEmpty
        ? MoneyFormatConfig.dateLocale
        : _localeEs;

/// Monto redondeado con separador de miles; incluye símbolo si está configurado.
String formatMoney(double amount) {
  final value = roundMoney(amount);
  final formatted = MoneyFormatConfig.numberFormat.format(value);
  if (MoneyFormatConfig.showSymbol) {
    return '${MoneyFormatConfig.symbol}$formatted';
  }
  return formatted;
}

/// Texto para campos editables (vacío si el monto es 0).
String formatMoneyField(double amount) {
  if (amount == 0) return '';
  return MoneyFormatConfig.numberFormat.format(roundMoney(amount));
}

/// Parsea montos escritos con o sin separador de miles / decimales.
double parseMoney(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;

  if (MoneyFormatConfig.decimalDigits <= 0) {
    final cleaned = trimmed.replaceAll('.', '').replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  try {
    return MoneyFormatConfig.numberFormat.parse(trimmed).toDouble();
  } catch (_) {
    final dec = MoneyFormatConfig.decimalSeparator;
    final grp = MoneyFormatConfig.groupSeparator;
    var normalized = trimmed.replaceAll(grp, '');
    if (dec != '.') {
      normalized = normalized.replaceAll(dec, '.');
    }
    normalized = normalized.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(normalized) ?? 0;
  }
}

/// Redondea según los decimales de la moneda activa.
double roundMoney(double amount) {
  final digits = MoneyFormatConfig.decimalDigits;
  if (digits <= 0) return amount.roundToDouble();
  var factor = 1.0;
  for (var i = 0; i < digits; i++) {
    factor *= 10;
  }
  return (amount * factor).round() / factor;
}

/// Formatea montos mientras el usuario escribe (ej. 50000 → 50.000).
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final maxDecimals = MoneyFormatConfig.decimalDigits;
    if (maxDecimals <= 0) {
      final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isEmpty) {
        return const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );
      }
      final formatted =
          MoneyFormatConfig.numberFormat.format(int.parse(digits));
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final dec = MoneyFormatConfig.decimalSeparator;
    final cleaned = newValue.text.replaceAll(RegExp('[^0-9.,]'), '');
    if (cleaned.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Un solo separador decimal (el último . o ,).
    String intPart;
    String? fracPart;
    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    final sepAt = lastDot > lastComma ? lastDot : lastComma;
    if (sepAt >= 0) {
      intPart = cleaned.substring(0, sepAt).replaceAll(RegExp(r'[^\d]'), '');
      fracPart = cleaned.substring(sepAt + 1).replaceAll(RegExp(r'[^\d]'), '');
      if (fracPart.length > maxDecimals) {
        fracPart = fracPart.substring(0, maxDecimals);
      }
    } else {
      intPart = cleaned.replaceAll(RegExp(r'[^\d]'), '');
      fracPart = null;
    }

    if (intPart.isEmpty) intPart = '0';
    final intValue = int.tryParse(intPart) ?? 0;
    final grouped = NumberFormat('#,##0', MoneyFormatConfig.locale).format(intValue);

    final endsWithSep = sepAt >= 0 &&
        (cleaned.endsWith('.') || cleaned.endsWith(','));
    final formatted = fracPart == null && !endsWithSep
        ? grouped
        : '$grouped$dec${fracPart ?? ''}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

const moneyInputFormatters = [MoneyInputFormatter()];

String formatFecha(DateTime fecha) =>
    DateFormat('dd/MM/yyyy', _activeDateLocale).format(fecha);

/// Fecha legible (ej. "Lunes 6 de julio 2026"), sin hora.
String formatFechaLegible(DateTime fecha) {
  final locale = _activeDateLocale;
  if (locale.startsWith('en')) {
    return DateFormat('EEEE, MMMM d, y', locale).format(fecha);
  }
  if (locale.startsWith('pt')) {
    return capitalize(
      DateFormat("EEEE, d 'de' MMMM 'de' y", locale).format(fecha),
    );
  }
  return capitalize(DateFormat("EEEE d 'de' MMMM y", locale).format(fecha));
}

/// Versión compacta para listas (evita textos largos en PT: "Seg, 8 de jul 2026").
String formatFechaLegibleCorta(DateTime fecha) {
  final locale = _activeDateLocale;
  if (locale.startsWith('en')) {
    return DateFormat('EEE, MMM d, y', locale).format(fecha);
  }
  if (locale.startsWith('pt')) {
    return capitalize(
      DateFormat("EEE, d 'de' MMM y", locale).format(fecha),
    );
  }
  return capitalize(DateFormat("EEE d 'de' MMM y", locale).format(fecha));
}

String formatFechaCorta(DateTime fecha) =>
    DateFormat('dd/MM/yy', _activeDateLocale).format(fecha);

String formatHora(DateTime fecha) =>
    DateFormat('HH:mm', _activeDateLocale).format(fecha);

/// Mes abreviado en mayúsculas para bloque de fecha (ej. "JUL", "APR").
String formatMesAbrev(DateTime fecha) =>
    DateFormat('MMM', _activeDateLocale).format(fecha).toUpperCase()
        .replaceAll('.', '');

/// Día del mes como número (ej. "17").
String formatDiaNumero(DateTime fecha) =>
    DateFormat('d', _activeDateLocale).format(fecha);

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

/// Countdown legible hasta el plazo de respuesta (`tiempo_limite`).
String formatPlazoRestante(Duration remaining) {
  if (remaining <= Duration.zero) {
    return _relativeLocalePhrase(es: '0 min', en: '0 min', pt: '0 min');
  }
  if (remaining < const Duration(hours: 1)) {
    final m = remaining.inMinutes.clamp(1, 59);
    return _relativeLocalePhrase(
      es: '$m min',
      en: '$m min',
      pt: '$m min',
    );
  }
  if (remaining < const Duration(hours: 24)) {
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    if (m > 0) {
      return _relativeLocalePhrase(
        es: '$h h $m min',
        en: '${h}h ${m}m',
        pt: '$h h $m min',
      );
    }
    return _relativeLocalePhrase(
      es: '$h h',
      en: '${h}h',
      pt: '$h h',
    );
  }
  final d = remaining.inDays;
  final h = remaining.inHours % 24;
  if (h > 0) {
    return _relativeLocalePhrase(
      es: '$d d $h h',
      en: '${d}d ${h}h',
      pt: '$d d $h h',
    );
  }
  return _relativeLocalePhrase(
    es: '$d días',
    en: '$d days',
    pt: '$d dias',
  );
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
  if (saldo > 0) return 'Pendiente ${formatMoney(saldo)}';
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
