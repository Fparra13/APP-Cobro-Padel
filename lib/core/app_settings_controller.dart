import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import 'country_sport_catalog.dart';
import 'currency_config.dart';
import 'sport_theme.dart';
import 'sport_type.dart';

/// Vista activa en la app (no cambia el rol de pago en Supabase).
enum AppUiMode {
  organizer,
  player;

  static AppUiMode fromStorage(String? value) {
    if (value == 'player') return AppUiMode.player;
    return AppUiMode.organizer;
  }

  String get storageValue => name;
}

/// Preferencias globales de Kloovi: deporte, idioma, moneda y modo de UI.
class AppSettingsController extends ChangeNotifier {
  static const _keySport = 'matchpay_sport';
  static const _keySportOnboarded = 'matchpay_sport_onboarded';
  static const _keyIntroOnboarded = 'matchpay_intro_onboarded';
  static const _keyLocale = 'matchpay_locale';
  static const localePrefsKey = _keyLocale;
  static const _keyCurrency = 'matchpay_currency';
  static const _keyCountry = 'matchpay_country';
  static const _keyUiMode = 'matchpay_ui_mode';

  SportType _sport = SportType.padel;
  Locale _locale = const Locale('en');
  String _currencyCode = CurrencyConfig.defaultCode;
  String _countryCode = CountrySportCatalog.defaultCountryCode;
  AppUiMode _uiMode = AppUiMode.organizer;
  bool _loaded = false;
  bool _sportOnboardingComplete = false;
  bool _introOnboardingComplete = false;

  SportType get sport => _sport;
  Locale get locale => _locale;
  String get currencyCode => _currencyCode;
  String get countryCode => _countryCode;
  MatchPayCountry get country => CountrySportCatalog.optionFor(_countryCode);
  List<SportType> get featuredSports =>
      CountrySportCatalog.featuredFor(_countryCode);
  AppUiMode get uiMode => _uiMode;
  bool get isLoaded => _loaded;
  bool get sportOnboardingComplete => _sportOnboardingComplete;
  bool get introOnboardingComplete => _introOnboardingComplete;

  /// Shell a mostrar: organizadores pueden alternar; jugadores solo ven modo jugador.
  bool get showOrganizerShell {
    if (!AuthService.instance.isOrganizer) return false;
    return _uiMode == AppUiMode.organizer;
  }

  CurrencyOption get currency => CurrencyConfig.optionFor(_currencyCode);

  ThemeData get theme => SportThemeConfig.themeFor(_sport);

  SportThemePalette get palette => SportThemeConfig.paletteFor(_sport);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hadSportSaved = prefs.containsKey(_keySport);
    _sport = SportType.fromDb(prefs.getString(_keySport));
    _sportOnboardingComplete =
        prefs.getBool(_keySportOnboarded) ?? hadSportSaved;
    _introOnboardingComplete =
        prefs.getBool(_keyIntroOnboarded) ?? _sportOnboardingComplete;
    final savedLocale = prefs.getString(_keyLocale);
    if (savedLocale != null) {
      _locale = normalizePickerLocale(_parseLocale(savedLocale));
    } else {
      _locale = normalizePickerLocale(
        resolveDeviceLocale(
          deviceLocales: WidgetsBinding.instance.platformDispatcher.locales,
        ),
      );
      await prefs.setString(_keyLocale, _localeTag(_locale));
    }
    final hadCurrencySaved = prefs.containsKey(_keyCurrency);
    if (hadCurrencySaved) {
      _currencyCode = prefs.getString(_keyCurrency)!;
    } else {
      _currencyCode = resolveCurrencyForLocale(_locale);
      await prefs.setString(_keyCurrency, _currencyCode);
    }
    final hadCountrySaved = prefs.containsKey(_keyCountry);
    if (hadCountrySaved) {
      _countryCode = CountrySportCatalog.optionFor(prefs.getString(_keyCountry)).code;
    } else {
      _countryCode = CountrySportCatalog.resolveFromLocale(
        _locale,
        currencyCode: _currencyCode,
      );
      await prefs.setString(_keyCountry, _countryCode);
    }
    _uiMode = AppUiMode.fromStorage(prefs.getString(_keyUiMode));
    _loaded = true;
    notifyListeners();
    await syncLocaleToProfile();
    await syncSportToProfile();
  }

  /// Alinea el modo de UI con el rol real del perfil (solo organizadores alternan).
  Future<void> syncUiModeWithRole({required bool isOrganizer}) async {
    if (isOrganizer) return;
    if (_uiMode == AppUiMode.player) return;
    _uiMode = AppUiMode.player;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUiMode, AppUiMode.player.storageValue);
  }

  /// Cambia entre vista organizador y jugador (solo si el perfil es organizador).
  Future<void> setUiMode(AppUiMode mode) async {
    if (!AuthService.instance.isOrganizer) {
      _uiMode = AppUiMode.player;
      notifyListeners();
      return;
    }
    if (_uiMode == mode) return;
    _uiMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUiMode, mode.storageValue);
  }

  /// Idioma del sistema mapeado a un locale soportado por Kloovi.
  ///
  /// En el primer arranque (sin preferencia guardada) usa la lista de idiomas
  /// del dispositivo (`platformDispatcher.locales`), igual que el onboarding.
  static Locale resolveDeviceLocale({
    Locale? deviceLocale,
    Iterable<Locale>? deviceLocales,
  }) {
    final candidates = <Locale>[
      ?deviceLocale,
      ...?deviceLocales,
    ];
    if (candidates.isEmpty) {
      candidates.add(WidgetsBinding.instance.platformDispatcher.locale);
    }
    for (final device in candidates) {
      for (final supported in supportedLocales) {
        if (supported.languageCode == device.languageCode &&
            supported.countryCode != null &&
            supported.countryCode == device.countryCode) {
          return supported;
        }
      }
    }
    for (final device in candidates) {
      for (final supported in supportedLocales) {
        if (supported.languageCode == device.languageCode) {
          return supported;
        }
      }
    }
    return const Locale('en');
  }

  /// Moneda inicial según región del dispositivo (solo primer arranque).
  static String resolveCurrencyForLocale(Locale locale) {
    switch (locale.countryCode?.toUpperCase()) {
      case 'CL':
        return 'CLP';
      case 'AR':
        return 'ARS';
      case 'MX':
        return 'MXN';
      case 'CO':
        return 'COP';
      case 'PE':
        return 'PEN';
      case 'UY':
        return 'UYU';
      case 'BR':
        return 'BRL';
      case 'US':
        return 'USD';
      case 'GB':
        return 'GBP';
      case 'ES':
      case 'FR':
      case 'DE':
      case 'IT':
        return 'EUR';
    }
    switch (locale.languageCode) {
      case 'pt':
        return 'BRL';
      case 'en':
        return 'USD';
      case 'es':
        return 'USD';
      default:
        return CurrencyConfig.defaultCode;
    }
  }

  static Future<String> readLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString(_keyLocale);
    if (tag != null && tag.isNotEmpty) {
      return tag.split('_').first;
    }
    return resolveDeviceLocale().languageCode;
  }

  /// Persiste el idioma activo en Supabase para push localizados al destinatario.
  Future<void> syncLocaleToProfile() async {
    if (!SupabaseConfig.isConfigured || !AuthService.instance.isLoggedIn) {
      return;
    }
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return;
    try {
      await SupabaseHelpers.client.from('profiles').update({
        'preferred_locale': _locale.languageCode,
      }).eq('id', uid);
    } catch (_) {}
  }

  /// Marca la intro de valor como vista (paso 1 del onboarding).
  Future<void> completeIntroOnboarding() async {
    if (_introOnboardingComplete) return;
    _introOnboardingComplete = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIntroOnboarded, true);
  }

  /// Completa intro y deporte por defecto (sin pantalla de deporte).
  Future<void> completeIntroAndDefaultSport({
    SportType sport = SportType.general,
  }) async {
    if (!_introOnboardingComplete) {
      _introOnboardingComplete = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIntroOnboarded, true);
    }
    if (!_sportOnboardingComplete) {
      _sport = sport;
      _sportOnboardingComplete = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySport, sport.dbValue);
      await prefs.setBool(_keySportOnboarded, true);
    }
    notifyListeners();
  }

  /// Vuelve al paso 1 del onboarding (idioma + valor).
  Future<void> revertIntroOnboarding() async {
    if (!_introOnboardingComplete || _sportOnboardingComplete) return;
    _introOnboardingComplete = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIntroOnboarded, false);
  }

  /// Guarda el deporte elegido en el onboarding inicial (obligatorio).
  Future<void> completeSportOnboarding(SportType sport) async {
    _sport = sport;
    _sportOnboardingComplete = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySport, sport.dbValue);
    await prefs.setBool(_keySportOnboarded, true);
  }

  Future<void> setSport(SportType sport) async {
    if (_sport == sport) return;
    _sport = sport;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySport, sport.dbValue);
    if (!_sportOnboardingComplete) {
      _sportOnboardingComplete = true;
      await prefs.setBool(_keySportOnboarded, true);
    }
    await syncSportToProfile();
    // Home / historial / mis cobros recargan (tema + datos visibles).
    if (AppRepositories.isReady) {
      AppRepositories.notifyDataChanged();
    }
  }

  Future<void> syncSportToProfile() async {
    if (!SupabaseConfig.isConfigured || !AuthService.instance.isLoggedIn) {
      return;
    }
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return;
    try {
      await SupabaseHelpers.client.from('profiles').update({
        'preferred_sport': _sport.dbValue,
      }).eq('id', uid);
    } catch (_) {}
  }

  Future<void> setLocale(Locale locale) async {
    final next = normalizePickerLocale(locale);
    if (_locale.languageCode == next.languageCode &&
        _locale.countryCode == next.countryCode) {
      return;
    }
    _locale = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, _localeTag(next));
    await syncLocaleToProfile();
  }

  Future<void> setCurrency(String code) async {
    if (_currencyCode == code) return;
    _currencyCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, code);
  }

  Future<void> setCountry(String code) async {
    final normalized = CountrySportCatalog.optionFor(code).code;
    if (_countryCode == normalized) return;
    _countryCode = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCountry, normalized);
  }

  /// Tema temporal para un partido con deporte distinto al global.
  ThemeData themeForSport(SportType? sport) {
    if (sport == null || sport == _sport) return theme;
    return SportThemeConfig.themeFor(sport);
  }

  static Locale _parseLocale(String tag) {
    final parts = tag.split('_');
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return Locale(parts[0]);
  }

  static String _localeTag(Locale locale) {
    if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
      return '${locale.languageCode}_${locale.countryCode}';
    }
    return locale.languageCode;
  }

  static const supportedLocales = [
    Locale('es', 'CL'),
    Locale('es'),
    Locale('en'),
    Locale('pt', 'BR'),
    Locale('pt'),
  ];

  /// Opciones visibles en onboarding y ajustes (es / en / pt).
  static const pickerLocales = [
    Locale('es', 'CL'),
    Locale('en'),
    Locale('pt', 'BR'),
  ];

  static Locale normalizePickerLocale(Locale locale) {
    for (final supported in pickerLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return const Locale('en');
  }
}
