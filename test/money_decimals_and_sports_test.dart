import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/country_sport_catalog.dart';
import 'package:matchpay/core/currency_config.dart';
import 'package:matchpay/core/sport_type.dart';
import 'package:matchpay/utils/formatters.dart';

void main() {
  tearDown(() {
    MoneyFormatConfig.locale = 'es_CL';
    MoneyFormatConfig.symbol = '\$';
    MoneyFormatConfig.decimalDigits = 0;
    MoneyFormatConfig.showSymbol = true;
  });

  void applyCurrency(String code) {
    final c = CurrencyConfig.optionFor(code);
    MoneyFormatConfig.locale = c.locale;
    MoneyFormatConfig.symbol = c.symbol;
    MoneyFormatConfig.decimalDigits = c.decimalDigits;
  }

  test('CLP sigue en enteros', () {
    applyCurrency('CLP');
    expect(roundMoney(10.6), 11);
    expect(formatMoney(10500), r'$10.500');
    expect(parseMoney('10.500'), 10500);
  });

  test('USD muestra y redondea 2 decimales', () {
    applyCurrency('USD');
    expect(CurrencyConfig.optionFor('USD').decimalDigits, 2);
    expect(roundMoney(10.456), 10.46);
    expect(roundMoney(10.454), 10.45);
    expect(formatMoney(10.5), contains('10.50'));
    expect(parseMoney('1,234.56'), 1234.56);
  });

  test('BRL usa coma decimal', () {
    applyCurrency('BRL');
    expect(roundMoney(12.349), 12.35);
    expect(parseMoney('1.234,56'), 1234.56);
    expect(formatMoney(1234.5), contains('1.234,50'));
  });

  test('UYU está en el catálogo', () {
    final uyu = CurrencyConfig.optionFor('UYU');
    expect(uyu.code, 'UYU');
    expect(uyu.decimalDigits, 2);
  });

  test('deportes BR trendy en catálogo y featured BR', () {
    expect(SportType.fromDb('beach_tennis'), SportType.beachTennis);
    expect(SportType.fromDb('pickleball'), SportType.pickleball);
    expect(SportType.fromDb('futevolei'), SportType.futevolei);
    final br = CountrySportCatalog.featuredFor('BR');
    expect(br, contains(SportType.beachTennis));
    expect(br, contains(SportType.pickleball));
    expect(br, contains(SportType.futevolei));
    expect(SportType.beachTennis.labelForLang('pt'), 'Beach tennis');
    expect(SportType.futevolei.labelForLang('pt'), 'Futevôlei');
    expect(SportType.futevolei.labelForLang('en'), 'Footvolley');
  });
}
