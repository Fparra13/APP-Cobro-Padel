import '../core/supabase_helpers.dart';
import '../models/cobro_recordatorio_prefs.dart';

/// Preferencias y alta de schedules de recordatorios automáticos de cobro.
class CobroRecordatorioPrefsRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<CobroRecordatorioPrefs> getPrefs() {
    return SupabaseHelpers.guard('Preferencias recordatorio cobro', () async {
      final raw = await _client.rpc('get_organizador_recordatorio_prefs');
      if (raw is! Map) return CobroRecordatorioPrefs.defaults;

      final map = Map<String, dynamic>.from(raw);
      final prefs = CobroRecordatorioPrefs.fromJson(map);
      final rawFreq = (map['frecuencia_dias'] as num?)?.toInt();
      final rawPrimer = (map['dias_primer'] as num?)?.toInt();
      final exists = map['exists'] as bool? ?? true;

      // Persist legacy UI values (p. ej. 15 → 7) without changing worker logic.
      if (exists &&
          ((rawFreq != null && rawFreq != prefs.frecuenciaDias) ||
              (rawPrimer != null && rawPrimer != prefs.diasPrimer))) {
        return upsertPrefs(prefs);
      }
      return prefs;
    });
  }

  Future<CobroRecordatorioPrefs> upsertPrefs(CobroRecordatorioPrefs prefs) {
    return SupabaseHelpers.write('Guardar preferencias recordatorio cobro',
        () async {
      final raw = await _client.rpc(
        'upsert_organizador_recordatorio_prefs',
        params: {
          'p_activo': prefs.activo,
          'p_dias_primer': prefs.diasPrimer,
          'p_frecuencia_dias': prefs.frecuenciaDias,
          'p_hora_local': prefs.horaLocalSql,
          'p_timezone': prefs.timezone,
        },
      );
      if (raw is Map) {
        return CobroRecordatorioPrefs.fromJson(
          Map<String, dynamic>.from(raw),
        ).copyWith(exists: true);
      }
      return prefs.copyWith(exists: true);
    });
  }

  Future<GenerarRecordatoriosPartidoResult> generarParaPartido({
    required int partidoId,
    required bool generar,
  }) {
    return SupabaseHelpers.write('Generar recordatorios partido', () async {
      final raw = await _client.rpc(
        'generar_recordatorios_partido',
        params: {
          'p_partido_id': partidoId,
          'p_generar': generar,
        },
      );
      if (raw is Map) {
        return GenerarRecordatoriosPartidoResult.fromJson(
          Map<String, dynamic>.from(raw),
        );
      }
      return GenerarRecordatoriosPartidoResult(
        ok: false,
        generar: generar,
        creados: 0,
        omitidos: 0,
        prefsActivo: false,
        mensaje: 'Respuesta inválida',
      );
    });
  }
}
