/// Monedas soportadas por MatchPay.
class CurrencyOption {
  final String code;
  final String symbol;
  final String nameEs;
  final String locale;

  const CurrencyOption({
    required this.code,
    required this.symbol,
    required this.nameEs,
    required this.locale,
  });
}

class CurrencyConfig {
  CurrencyConfig._();

  static const defaultCode = 'CLP';

  static const options = <CurrencyOption>[
    CurrencyOption(
      code: 'CLP',
      symbol: '\$',
      nameEs: 'Peso chileno',
      locale: 'es_CL',
    ),
    CurrencyOption(
      code: 'ARS',
      symbol: '\$',
      nameEs: 'Peso argentino',
      locale: 'es_AR',
    ),
    CurrencyOption(
      code: 'MXN',
      symbol: '\$',
      nameEs: 'Peso mexicano',
      locale: 'es_MX',
    ),
    CurrencyOption(
      code: 'COP',
      symbol: '\$',
      nameEs: 'Peso colombiano',
      locale: 'es_CO',
    ),
    CurrencyOption(
      code: 'PEN',
      symbol: 'S/',
      nameEs: 'Sol peruano',
      locale: 'es_PE',
    ),
    CurrencyOption(
      code: 'BRL',
      symbol: 'R\$',
      nameEs: 'Real brasileño',
      locale: 'pt_BR',
    ),
    CurrencyOption(
      code: 'USD',
      symbol: 'US\$',
      nameEs: 'Dólar estadounidense',
      locale: 'en_US',
    ),
    CurrencyOption(
      code: 'EUR',
      symbol: '€',
      nameEs: 'Euro',
      locale: 'es_ES',
    ),
    CurrencyOption(
      code: 'GBP',
      symbol: '£',
      nameEs: 'Libra esterlina',
      locale: 'en_GB',
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
