import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/currency_config.dart';
import 'package:matchpay/utils/formatters.dart';

void main() {
  tearDown(() {
    MoneyFormatConfig.locale = 'es_CL';
    MoneyFormatConfig.symbol = '\$';
    MoneyFormatConfig.decimalDigits = 0;
    MoneyFormatConfig.showSymbol = true;
  });

  test('CLP → BRL cambia símbolo a R\$ y usa decimales', () {
    final clp = CurrencyConfig.optionFor('CLP');
    MoneyFormatConfig.locale = clp.locale;
    MoneyFormatConfig.symbol = clp.symbol;
    MoneyFormatConfig.decimalDigits = clp.decimalDigits;
    expect(formatMoney(1500), r'$1.500');

    final brl = CurrencyConfig.optionFor('BRL');
    MoneyFormatConfig.locale = brl.locale;
    MoneyFormatConfig.symbol = brl.symbol;
    MoneyFormatConfig.decimalDigits = brl.decimalDigits;
    expect(MoneyFormatConfig.symbol, r'R$');
    expect(formatMoney(1500), contains(r'R$'));
    expect(formatMoney(1500), isNot(equals(r'$1.500')));
  });

  test('ARS MXN COP tienen símbolo distinto a CLP', () {
    expect(CurrencyConfig.optionFor('ARS').symbol, r'AR$');
    expect(CurrencyConfig.optionFor('MXN').symbol, r'MX$');
    expect(CurrencyConfig.optionFor('COP').symbol, r'COL$');
    expect(CurrencyConfig.optionFor('CLP').symbol, r'$');

    final ars = CurrencyConfig.optionFor('ARS');
    MoneyFormatConfig.locale = ars.locale;
    MoneyFormatConfig.symbol = ars.symbol;
    MoneyFormatConfig.decimalDigits = ars.decimalDigits;
    expect(formatMoney(1500), startsWith(r'AR$'));
  });
}
