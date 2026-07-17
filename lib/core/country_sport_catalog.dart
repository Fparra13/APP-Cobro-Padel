import 'package:flutter/material.dart';

import 'sport_type.dart';

/// País de preferencia: solo ordena deportes destacados (no oculta el catálogo).
class MatchPayCountry {
  final String code;
  final String nameEs;
  final String nameEn;
  final String namePt;

  const MatchPayCountry({
    required this.code,
    required this.nameEs,
    required this.nameEn,
    required this.namePt,
  });

  String labelForLang(String lang) => switch (lang) {
        'en' => nameEn,
        'pt' => namePt,
        _ => nameEs,
      };
}

/// Catálogo de países + deportes destacados por afinidad local.
class CountrySportCatalog {
  CountrySportCatalog._();

  static const defaultCountryCode = 'CL';

  static const options = <MatchPayCountry>[
    MatchPayCountry(
      code: 'CL',
      nameEs: 'Chile',
      nameEn: 'Chile',
      namePt: 'Chile',
    ),
    MatchPayCountry(
      code: 'AR',
      nameEs: 'Argentina',
      nameEn: 'Argentina',
      namePt: 'Argentina',
    ),
    MatchPayCountry(
      code: 'UY',
      nameEs: 'Uruguay',
      nameEn: 'Uruguay',
      namePt: 'Uruguai',
    ),
    MatchPayCountry(
      code: 'BR',
      nameEs: 'Brasil',
      nameEn: 'Brazil',
      namePt: 'Brasil',
    ),
    MatchPayCountry(
      code: 'MX',
      nameEs: 'México',
      nameEn: 'Mexico',
      namePt: 'México',
    ),
    MatchPayCountry(
      code: 'CO',
      nameEs: 'Colombia',
      nameEn: 'Colombia',
      namePt: 'Colômbia',
    ),
    MatchPayCountry(
      code: 'PE',
      nameEs: 'Perú',
      nameEn: 'Peru',
      namePt: 'Peru',
    ),
    MatchPayCountry(
      code: 'US',
      nameEs: 'Estados Unidos',
      nameEn: 'United States',
      namePt: 'Estados Unidos',
    ),
    MatchPayCountry(
      code: 'ES',
      nameEs: 'España',
      nameEn: 'Spain',
      namePt: 'Espanha',
    ),
    MatchPayCountry(
      code: 'GB',
      nameEs: 'Reino Unido',
      nameEn: 'United Kingdom',
      namePt: 'Reino Unido',
    ),
    MatchPayCountry(
      code: 'OTHER',
      nameEs: 'Otro país',
      nameEn: 'Other country',
      namePt: 'Outro país',
    ),
  ];

  static MatchPayCountry optionFor(String? code) {
    if (code == null || code.isEmpty) {
      return options.firstWhere((c) => c.code == defaultCountryCode);
    }
    return options.firstWhere(
      (c) => c.code == code.toUpperCase(),
      orElse: () => options.firstWhere((c) => c.code == 'OTHER'),
    );
  }

  /// Idioma + moneda típicos al elegir un país en preferencias.
  /// `null` = no forzar (p. ej. «Otro país»).
  static ({Locale locale, String currencyCode})? defaultsFor(String? countryCode) {
    switch (optionFor(countryCode).code) {
      case 'CL':
        return (locale: const Locale('es', 'CL'), currencyCode: 'CLP');
      case 'AR':
        return (locale: const Locale('es', 'CL'), currencyCode: 'ARS');
      case 'UY':
        return (locale: const Locale('es', 'CL'), currencyCode: 'UYU');
      case 'BR':
        return (locale: const Locale('pt', 'BR'), currencyCode: 'BRL');
      case 'MX':
        return (locale: const Locale('es', 'CL'), currencyCode: 'MXN');
      case 'CO':
        return (locale: const Locale('es', 'CL'), currencyCode: 'COP');
      case 'PE':
        return (locale: const Locale('es', 'CL'), currencyCode: 'PEN');
      case 'US':
        return (locale: const Locale('en'), currencyCode: 'USD');
      case 'ES':
        return (locale: const Locale('es', 'CL'), currencyCode: 'EUR');
      case 'GB':
        return (locale: const Locale('en'), currencyCode: 'GBP');
      default:
        return null;
    }
  }

  /// Infere país desde locale / moneda (primer arranque).
  static String resolveFromLocale(Locale locale, {String? currencyCode}) {
    final country = locale.countryCode?.toUpperCase();
    if (country != null && options.any((c) => c.code == country)) {
      return country;
    }
    switch (currencyCode?.toUpperCase()) {
      case 'CLP':
        return 'CL';
      case 'ARS':
        return 'AR';
      case 'UYU':
        return 'UY';
      case 'BRL':
        return 'BR';
      case 'MXN':
        return 'MX';
      case 'COP':
        return 'CO';
      case 'PEN':
        return 'PE';
      case 'USD':
        return 'US';
      case 'EUR':
        return 'ES';
      case 'GBP':
        return 'GB';
    }
    switch (locale.languageCode) {
      case 'pt':
        return 'BR';
      case 'en':
        return 'US';
      case 'es':
        return 'CL';
      default:
        return defaultCountryCode;
    }
  }

  /// Destacados por país. El resto del catálogo sigue en «Ver más».
  static List<SportType> featuredFor(String? countryCode) {
    final code = optionFor(countryCode).code;
    return List<SportType>.unmodifiable(
      _featuredByCountry[code] ?? _defaultFeatured,
    );
  }

  static const _defaultFeatured = <SportType>[
    SportType.football,
    SportType.padel,
    SportType.tennis,
    SportType.beachTennis,
    SportType.pickleball,
    SportType.futevolei,
    SportType.running,
    SportType.basketball,
    SportType.other,
  ];

  static const _featuredByCountry = <String, List<SportType>>{
    'CL': [
      SportType.padel,
      SportType.football,
      SportType.tennis,
      SportType.running,
      SportType.basketball,
      SportType.beachTennis,
      SportType.pickleball,
      SportType.other,
    ],
    'AR': [
      SportType.padel,
      SportType.football,
      SportType.tennis,
      SportType.running,
      SportType.basketball,
      SportType.beachTennis,
      SportType.pickleball,
      SportType.other,
    ],
    'UY': [
      SportType.football,
      SportType.padel,
      SportType.beachTennis,
      SportType.tennis,
      SportType.basketball,
      SportType.running,
      SportType.pickleball,
      SportType.other,
    ],
    'BR': [
      SportType.football,
      SportType.futevolei,
      SportType.beachTennis,
      SportType.pickleball,
      SportType.volleyball,
      SportType.padel,
      SportType.tennis,
      SportType.other,
    ],
    'MX': [
      SportType.football,
      SportType.padel,
      SportType.basketball,
      SportType.tennis,
      SportType.pickleball,
      SportType.running,
      SportType.beachTennis,
      SportType.other,
    ],
    'CO': [
      SportType.football,
      SportType.padel,
      SportType.running,
      SportType.basketball,
      SportType.tennis,
      SportType.pickleball,
      SportType.other,
    ],
    'PE': [
      SportType.football,
      SportType.padel,
      SportType.volleyball,
      SportType.tennis,
      SportType.running,
      SportType.beachTennis,
      SportType.other,
    ],
    'US': [
      SportType.pickleball,
      SportType.tennis,
      SportType.basketball,
      SportType.padel,
      SportType.football,
      SportType.running,
      SportType.beachTennis,
      SportType.other,
    ],
    'ES': [
      SportType.padel,
      SportType.football,
      SportType.tennis,
      SportType.basketball,
      SportType.running,
      SportType.pickleball,
      SportType.beachTennis,
      SportType.other,
    ],
    'GB': [
      SportType.football,
      SportType.tennis,
      SportType.running,
      SportType.padel,
      SportType.basketball,
      SportType.pickleball,
      SportType.other,
    ],
    'OTHER': _defaultFeatured,
  };
}
