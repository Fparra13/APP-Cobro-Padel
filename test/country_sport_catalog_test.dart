import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/country_sport_catalog.dart';
import 'package:matchpay/core/sport_type.dart';

void main() {
  test('BR prioriza futevôlei, beach tennis y pickleball', () {
    final featured = CountrySportCatalog.featuredFor('BR');
    expect(featured.take(4).toList(), [
      SportType.football,
      SportType.futevolei,
      SportType.beachTennis,
      SportType.pickleball,
    ]);
  });

  test('US prioriza pickleball', () {
    expect(CountrySportCatalog.featuredFor('US').first, SportType.pickleball);
  });

  test('CL prioriza pádel', () {
    expect(CountrySportCatalog.featuredFor('CL').first, SportType.padel);
  });

  test('país desconocido cae en OTHER sin romper', () {
    expect(CountrySportCatalog.optionFor('ZZ').code, 'OTHER');
    expect(CountrySportCatalog.featuredFor('ZZ'), isNotEmpty);
  });

  test('infiere país desde locale/moneda', () {
    expect(
      CountrySportCatalog.resolveFromLocale(const Locale('pt', 'BR')),
      'BR',
    );
    expect(
      CountrySportCatalog.resolveFromLocale(
        const Locale('es'),
        currencyCode: 'UYU',
      ),
      'UY',
    );
    expect(
      CountrySportCatalog.resolveFromLocale(const Locale('en', 'US')),
      'US',
    );
  });

  test('no oculta deportes: catálogo completo sigue disponible', () {
    final featured = CountrySportCatalog.featuredFor('BR').toSet();
    expect(SportType.values.length, greaterThan(featured.length));
  });
}
