import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const _keyTitular = 'titular_nombre';
  static const _keyBanco = 'banco_nombre';
  static const _keyCuenta = 'cuenta_numero';
  static const _keyRut = 'titular_rut';
  static const _keyUltimoRecinto = 'ultimo_recinto';
  static const _keyRecordatorioActivo = 'recordatorio_activo';
  static const _keyRecordatorioDias = 'recordatorio_dias';
  static const _keyRecordatorioHora = 'recordatorio_hora';
  static const _keyRecordatorioMinuto = 'recordatorio_minuto';
  static const _keyRecordatorioUltimaFecha = 'recordatorio_ultima_fecha';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<String> get titularNombre async =>
      (await _prefs).getString(_keyTitular) ?? '';

  Future<String> get bancoNombre async =>
      (await _prefs).getString(_keyBanco) ?? '';

  Future<String> get cuentaNumero async =>
      (await _prefs).getString(_keyCuenta) ?? '';

  Future<String> get titularRut async =>
      (await _prefs).getString(_keyRut) ?? '';

  Future<String> get ultimoRecinto async =>
      (await _prefs).getString(_keyUltimoRecinto) ?? '';

  Future<void> saveUltimoRecinto(String recinto) async {
    final prefs = await _prefs;
    await prefs.setString(_keyUltimoRecinto, recinto);
  }

  Future<bool> get recordatorioActivo async =>
      (await _prefs).getBool(_keyRecordatorioActivo) ?? false;

  Future<int> get recordatorioDias async =>
      (await _prefs).getInt(_keyRecordatorioDias) ?? 3;

  Future<int> get recordatorioHora async =>
      (await _prefs).getInt(_keyRecordatorioHora) ?? 10;

  Future<int> get recordatorioMinuto async =>
      (await _prefs).getInt(_keyRecordatorioMinuto) ?? 0;

  Future<String> get recordatorioUltimaFecha async =>
      (await _prefs).getString(_keyRecordatorioUltimaFecha) ?? '';

  Future<void> saveRecordatorio({
    required bool activo,
    required int dias,
    required int hora,
    required int minuto,
  }) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyRecordatorioActivo, activo);
    await prefs.setInt(_keyRecordatorioDias, dias);
    await prefs.setInt(_keyRecordatorioHora, hora);
    await prefs.setInt(_keyRecordatorioMinuto, minuto);
  }

  Future<void> saveRecordatorioUltimaFecha(String fechaIso) async {
    final prefs = await _prefs;
    await prefs.setString(_keyRecordatorioUltimaFecha, fechaIso);
  }

  Future<void> saveDatosBancarios({
    required String titular,
    required String banco,
    required String cuenta,
    required String rut,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_keyTitular, titular);
    await prefs.setString(_keyBanco, banco);
    await prefs.setString(_keyCuenta, cuenta);
    await prefs.setString(_keyRut, rut);
  }
}
