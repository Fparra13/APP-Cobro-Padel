import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/widgets/kloovi_brand.dart';

void main() {
  test('splashForLanguage elige el asset del idioma activo', () {
    expect(
      KlooviBrandAssets.splashForLanguage('es'),
      KlooviBrandAssets.splashEs,
    );
    expect(
      KlooviBrandAssets.splashForLanguage('en'),
      KlooviBrandAssets.splashEn,
    );
    expect(
      KlooviBrandAssets.splashForLanguage('pt'),
      KlooviBrandAssets.splashPt,
    );
    expect(
      KlooviBrandAssets.splashForLocale(const Locale('es', 'CL')),
      KlooviBrandAssets.splashEs,
    );
    expect(
      KlooviBrandAssets.splashForLocale(const Locale('pt', 'BR')),
      KlooviBrandAssets.splashPt,
    );
  });
}
