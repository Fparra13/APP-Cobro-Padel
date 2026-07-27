import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/country_sport_catalog.dart';
import 'package:matchpay/core/sport_type.dart';

void main() {
  test('BR prioriza fútbol y mezcla inclusiva', () {
    final featured = CountrySportCatalog.featuredFor('BR');
    expect(featured.take(6).toList(), [
      SportType.football,
      SportType.padel,
      SportType.yoga,
      SportType.trekking,
      SportType.running,
      SportType.cycling,
    ]);
  });

  test('US incluye yoga y trekking en destacados', () {
    final featured = CountrySportCatalog.featuredFor('US');
    expect(featured, contains(SportType.yoga));
    expect(featured, contains(SportType.trekking));
    expect(featured.first, SportType.padel);
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

  test('defaultsFor país aplica idioma y moneda típicos', () {
    final br = CountrySportCatalog.defaultsFor('BR');
    expect(br?.locale.languageCode, 'pt');
    expect(br?.currencyCode, 'BRL');

    final cl = CountrySportCatalog.defaultsFor('CL');
    expect(cl?.locale.languageCode, 'es');
    expect(cl?.currencyCode, 'CLP');

    final us = CountrySportCatalog.defaultsFor('US');
    expect(us?.locale.languageCode, 'en');
    expect(us?.currencyCode, 'USD');

    final ca = CountrySportCatalog.defaultsFor('CA');
    expect(ca?.locale.languageCode, 'en');
    expect(ca?.currencyCode, 'CAD');

    expect(CountrySportCatalog.defaultsFor('OTHER'), isNull);
  });

  test('no oculta deportes: catálogo completo sigue disponible', () {
    final featured = CountrySportCatalog.featuredFor('BR').toSet();
    expect(SportType.values.length, greaterThan(featured.length));
  });
}
