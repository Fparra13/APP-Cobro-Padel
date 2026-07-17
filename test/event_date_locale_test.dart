import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchpay/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es', null);
    await initializeDateFormatting('en', null);
    await initializeDateFormatting('pt', null);
    await initializeDateFormatting('pt_BR', null);
  });

  test('formatMesAbrev respeta es / en / pt', () {
    final fecha = DateTime(2026, 7, 17);

    MoneyFormatConfig.dateLocale = 'es';
    expect(formatMesAbrev(fecha), 'JUL');
    expect(formatDiaNumero(fecha), '17');

    MoneyFormatConfig.dateLocale = 'en';
    expect(formatMesAbrev(fecha), 'JUL');
    expect(formatDiaNumero(fecha), '17');

    MoneyFormatConfig.dateLocale = 'pt';
    expect(formatMesAbrev(fecha), 'JUL');
    expect(formatDiaNumero(fecha), '17');

    MoneyFormatConfig.dateLocale = 'pt_BR';
    expect(formatMesAbrev(fecha), 'JUL');
  });

  test('formatMesAbrev en meses distintos por idioma', () {
    final mayo = DateTime(2026, 5, 5);

    MoneyFormatConfig.dateLocale = 'es';
    expect(formatMesAbrev(mayo), 'MAY');

    MoneyFormatConfig.dateLocale = 'en';
    expect(formatMesAbrev(mayo), 'MAY');

    MoneyFormatConfig.dateLocale = 'pt_BR';
    expect(formatMesAbrev(mayo), 'MAI');
  });
}
