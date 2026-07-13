/// Monedas soportadas por Kloovi.
class CurrencyOption {
  final String code;
  final String symbol;
  final String nameEs;
  final String locale;
  /// Decimales ISO prácticos (0 = entero, tip. CLP/COP).
  final int decimalDigits;

  const CurrencyOption({
    required this.code,
    required this.symbol,
    required this.nameEs,
    required this.locale,
    this.decimalDigits = 2,
  });
}

class CurrencyConfig {
  CurrencyConfig._();

  static const defaultCode = 'USD';

  static const options = <CurrencyOption>[
    CurrencyOption(
      code: 'CLP',
      symbol: '\$',
      nameEs: 'Peso chileno',
      locale: 'es_CL',
      decimalDigits: 0,
    ),
    CurrencyOption(
      code: 'ARS',
      symbol: '\$',
      nameEs: 'Peso argentino',
      locale: 'es_AR',
      decimalDigits: 2,
    ),
    CurrencyOption(
      code: 'MXN',
      symbol: '\$',
      nameEs: 'Peso mexicano',
      locale: 'es_MX',
      decimalDigits: 2,
    ),
    CurrencyOption(
      code: 'COP',
      symbol: '\$',
      nameEs: 'Peso colombiano',
      locale: 'es_CO',
      decimalDigits: 0,
    ),
    CurrencyOption(
      code: 'PEN',
      symbol: 'S/',
      nameEs: 'Sol peruano',
      locale: 'es_PE',
      decimalDigits: 2,
    ),
    CurrencyOption(
      code: 'UYU',
      symbol: '\$U',
      nameEs: 'Peso uruguayo',
      locale: 'es_UY',
      decimalDigits: 2,
    ),
    CurrencyOption(
      code: 'BRL',
      symbol: 'R\$',
      nameEs: 'Real brasileño',
      locale: 'pt_BR',
      decimalDigits: 2,
    ),
    CurrencyOption(
      code: 'USD',
      symbol: 'US\$',
      nameEs: 'Dólar estadounidense',
      locale: 'en_US',
      decimalDigits: 2,
    ),
    CurrencyOption(
      code: 'EUR',
      symbol: '€',
      nameEs: 'Euro',
      locale: 'es_ES',
      decimalDigits: 2,
    ),
    CurrencyOption(
      code: 'GBP',
      symbol: '£',
      nameEs: 'Libra esterlina',
      locale: 'en_GB',
      decimalDigits: 2,
    ),
  ];

  static CurrencyOption optionFor(String? code) {
    if (code == null || code.isEmpty) return options.first;
    return options.firstWhere(
      (c) => c.code == code,
      orElse: () => options.first,
    );
  }
}
