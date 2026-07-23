import 'package:shared_preferences/shared_preferences.dart';

import '../models/datos_pago_organizador.dart';

class PreferencesService {
  static const _keyTitular = 'titular_nombre';
  static const _keyBanco = 'banco_nombre';
  static const _keyCuenta = 'cuenta_numero';
  static const _keyRut = 'titular_rut';
  static const _keyPagoDetalle = 'pago_detalle';
  static const _keyPagoNota = 'pago_nota';
  static const _keyUltimoRecinto = 'ultimo_recinto';
  static const _keyRecordatorioActivo = 'recordatorio_activo';
  static const _keyRecordatorioDias = 'recordatorio_dias';
  static const _keyRecordatorioHora = 'recordatorio_hora';
  static const _keyRecordatorioMinuto = 'recordatorio_minuto';
  static const _keyRecordatorioUltimaFecha = 'recordatorio_ultima_fecha';
  static const _keyRecordatorioMigrated = 'recordatorio_cobro_migrated_v1';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<String> get titularNombre async =>
      (await _prefs).getString(_keyTitular) ?? '';

  /// @deprecated Preferir [datosPago].
  Future<String> get bancoNombre async =>
      (await _prefs).getString(_keyBanco) ?? '';

  /// @deprecated Preferir [datosPago].
  Future<String> get cuentaNumero async =>
      (await _prefs).getString(_keyCuenta) ?? '';

  /// @deprecated Preferir [datosPago].
  Future<String> get titularRut async =>
      (await _prefs).getString(_keyRut) ?? '';

  /// Instrucciones de pago (con migración automática desde banco/cuenta/RUT).
  Future<DatosPagoOrganizador> get datosPago async {
    final prefs = await _prefs;
    final titular = prefs.getString(_keyTitular) ?? '';
    var detalle = (prefs.getString(_keyPagoDetalle) ?? '').trim();
    if (detalle.isEmpty) {
      detalle = DatosPagoOrganizador.detalleDesdeLegacy(
        banco: prefs.getString(_keyBanco) ?? '',
        cuenta: prefs.getString(_keyCuenta) ?? '',
        rut: prefs.getString(_keyRut) ?? '',
      );
    }
    final nota = prefs.getString(_keyPagoNota) ?? '';
    return DatosPagoOrganizador(
      titular: titular,
      detalle: detalle,
      nota: nota,
    );
  }

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

  Future<bool> get recordatorioMigrated async =>
      (await _prefs).getBool(_keyRecordatorioMigrated) ?? false;

  Future<void> markRecordatorioMigrated() async {
    final prefs = await _prefs;
    await prefs.setBool(_keyRecordatorioMigrated, true);
  }

  Future<void> clearRecordatorioLocal() async {
    final prefs = await _prefs;
    await prefs.remove(_keyRecordatorioActivo);
    await prefs.remove(_keyRecordatorioDias);
    await prefs.remove(_keyRecordatorioHora);
    await prefs.remove(_keyRecordatorioMinuto);
    await prefs.remove(_keyRecordatorioUltimaFecha);
  }

  Future<void> saveDatosPago({
    required String titular,
    required String detalle,
    required String nota,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_keyTitular, titular.trim());
    await prefs.setString(_keyPagoDetalle, detalle.trim());
    await prefs.setString(_keyPagoNota, nota.trim());
  }

  /// @deprecated Usar [saveDatosPago].
  Future<void> saveDatosBancarios({
    required String titular,
    required String banco,
    required String cuenta,
    required String rut,
  }) async {
    await saveDatosPago(
      titular: titular,
      detalle: DatosPagoOrganizador.detalleDesdeLegacy(
        banco: banco,
        cuenta: cuenta,
        rut: rut,
      ),
      nota: '',
    );
  }
}
