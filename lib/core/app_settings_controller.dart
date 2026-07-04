import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
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

/// Preferencias globales de MatchPay: deporte, idioma, moneda y modo de UI.
class AppSettingsController extends ChangeNotifier {
  static const _keySport = 'matchpay_sport';
  static const _keySportOnboarded = 'matchpay_sport_onboarded';
  static const _keyLocale = 'matchpay_locale';
  static const localePrefsKey = _keyLocale;
  static const _keyCurrency = 'matchpay_currency';
  static const _keyUiMode = 'matchpay_ui_mode';

  SportType _sport = SportType.padel;
  Locale _locale = const Locale('es', 'CL');
  String _currencyCode = CurrencyConfig.defaultCode;
  AppUiMode _uiMode = AppUiMode.organizer;
  bool _loaded = false;
  bool _sportOnboardingComplete = false;

  SportType get sport => _sport;
  Locale get locale => _locale;
  String get currencyCode => _currencyCode;
  AppUiMode get uiMode => _uiMode;
  bool get isLoaded => _loaded;
  bool get sportOnboardingComplete => _sportOnboardingComplete;

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
    final savedLocale = prefs.getString(_keyLocale);
    if (savedLocale != null) {
      _locale = _parseLocale(savedLocale);
    } else {
      _locale = resolveDeviceLocale();
      await prefs.setString(_keyLocale, _localeTag(_locale));
    }
    _currencyCode = prefs.getString(_keyCurrency) ?? CurrencyConfig.defaultCode;
    _uiMode = AppUiMode.fromStorage(prefs.getString(_keyUiMode));
    _loaded = true;
    notifyListeners();
    await syncLocaleToProfile();
    await syncSportToProfile();
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

  /// Idioma del sistema mapeado a un locale soportado por MatchPay.
  static Locale resolveDeviceLocale([Locale? deviceLocale]) {
    final device =
        deviceLocale ?? WidgetsBinding.instance.platformDispatcher.locale;
    for (final supported in supportedLocales) {
      if (supported.languageCode == device.languageCode &&
          supported.countryCode == device.countryCode) {
        return supported;
      }
    }
    for (final supported in supportedLocales) {
      if (supported.languageCode == device.languageCode) {
        return supported;
      }
    }
    return const Locale('es', 'CL');
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
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, _localeTag(locale));
    await syncLocaleToProfile();
  }

  Future<void> setCurrency(String code) async {
    if (_currencyCode == code) return;
    _currencyCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, code);
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
}
