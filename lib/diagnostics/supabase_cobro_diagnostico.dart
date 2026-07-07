import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../core/supabase_parse.dart';
import '../domain/cobro_diagnostico.dart';

/// Diagnóstico SSOT leyendo directamente tablas de Supabase (sin repos de negocio).
class SupabaseCobroDiagnostico {
  SupabaseCobroDiagnostico._();

  static const _pageSize = 1000;

  /// Analiza cobros en Supabase. Solo lectura.
  ///
  /// Usa [client] si se provee; si no, crea uno con
  /// `SUPABASE_SERVICE_ROLE_KEY` (dart-define) para auditar sin RLS parcial.
  /// Sin service role ni sesión organizador, el reporte puede quedar incompleto.
  static Future<CobroDiagnosticoReporte> analizar({
    SupabaseClient? client,
    String? serviceRoleKey,
  }) async {
    final c = client ?? _resolverClient(serviceRoleKey: serviceRoleKey);

    final detalleRows = await _cargarPaginado(
      c,
      tabla: 'detalles_partido',
      select:
          'id, partido_id, jugador_id, asistio, total, monto_pagado, pagado, '
          'profiles(nombre)',
    );
    final historialRows = await _cargarPaginado(
      c,
      tabla: 'saldos_historicos',
      select:
          'id, jugador_id, partido_id, saldo_anterior, cargo_partido, abono, '
          'saldo_nuevo, fecha, concepto, profiles(nombre)',
    );

    final idsReferenciados = <String>{
      for (final row in detalleRows)
        SupabaseParse.asString(row['jugador_id']),
      for (final row in historialRows)
        SupabaseParse.asString(row['jugador_id']),
    }..removeWhere((id) => id.isEmpty);

    final jugadorRows = await _cargarPerfiles(c, idsReferenciados);

    return analizarFilas(
      detalleRows: detalleRows,
      historialRows: historialRows,
      jugadorRows: jugadorRows,
    );
  }

  /// Ejecuta el motor de diagnóstico sobre filas crudas de Supabase (tests).
  static CobroDiagnosticoReporte analizarFilas({
    required List<Map<String, dynamic>> detalleRows,
    required List<Map<String, dynamic>> historialRows,
    required List<Map<String, dynamic>> jugadorRows,
  }) {
    return CobroDiagnostico.analizar(
      detalles: detalleRows.map(_detalleFromRow).toList(),
      historial: historialRows.map(_historialFromRow).toList(),
      jugadores: jugadorRows.map(_jugadorFromRow).toList(),
    );
  }

  static SupabaseClient _resolverClient({String? serviceRoleKey}) {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase no está configurado (URL / anon key vacíos)');
    }

    final roleKey = serviceRoleKey ??
        const String.fromEnvironment(
          'SUPABASE_SERVICE_ROLE_KEY',
          defaultValue: '',
        );

    if (roleKey.isNotEmpty) {
      return SupabaseClient(SupabaseConfig.supabaseUrl, roleKey);
    }

    throw StateError(
      'Diagnóstico remoto requiere SUPABASE_SERVICE_ROLE_KEY '
      '(dart-define) o un SupabaseClient autenticado pasado explícitamente',
    );
  }

  static Future<List<Map<String, dynamic>>> _cargarPaginado(
    SupabaseClient client, {
    required String tabla,
    required String select,
  }) async {
    var offset = 0;
    final out = <Map<String, dynamic>>[];

    while (true) {
      final page = await client
          .from(tabla)
          .select(select)
          .range(offset, offset + _pageSize - 1);

      final list = (page as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      out.addAll(list);
      if (list.length < _pageSize) break;
      offset += _pageSize;
    }

    return out;
  }

  static Future<List<Map<String, dynamic>>> _cargarPerfiles(
    SupabaseClient client,
    Set<String> idsReferenciados,
  ) async {
    final rows = await _cargarPaginado(
      client,
      tabla: 'profiles',
      select: 'id, nombre, saldo_acumulado, activo',
    );

    final porId = <String, Map<String, dynamic>>{
      for (final row in rows)
        SupabaseParse.asString(row['id']): Map<String, dynamic>.from(row),
    };

    for (final id in idsReferenciados) {
      porId.putIfAbsent(
        id,
        () => {
          'id': id,
          'nombre': null,
          'saldo_acumulado': 0,
        },
      );
    }

    return porId.values.toList();
  }

  static DiagnosticoDetalleInput _detalleFromRow(Map<String, dynamic> row) {
    return DiagnosticoDetalleInput(
      detalleId: SupabaseParse.toInt(row['id']),
      partidoId: SupabaseParse.toInt(row['partido_id']),
      jugadorId: SupabaseParse.asString(row['jugador_id']),
      jugadorNombre: SupabaseParse.nombrePerfilEmbed(row['profiles']),
      asistio: SupabaseParse.toBool(row['asistio']),
      total: SupabaseParse.toDouble(row['total']),
      montoPagado: SupabaseParse.toDouble(row['monto_pagado']),
      pagado: SupabaseParse.toBool(row['pagado'], fallback: false),
    );
  }

  static DiagnosticoHistorialInput _historialFromRow(Map<String, dynamic> row) {
    return DiagnosticoHistorialInput(
      historialId: SupabaseParse.toInt(row['id']),
      jugadorId: SupabaseParse.asString(row['jugador_id']),
      jugadorNombre: SupabaseParse.nombrePerfilEmbed(row['profiles']),
      partidoId: row['partido_id'] == null
          ? null
          : SupabaseParse.toInt(row['partido_id']),
      saldoAnterior: SupabaseParse.toDouble(row['saldo_anterior']),
      cargoPartido: SupabaseParse.toDouble(row['cargo_partido']),
      abono: SupabaseParse.toDouble(row['abono']),
      saldoNuevo: SupabaseParse.toDouble(row['saldo_nuevo']),
      fecha: SupabaseParse.toDateTime(row['fecha']),
      concepto: SupabaseParse.asString(row['concepto'], fallback: 'Movimiento'),
    );
  }

  static DiagnosticoJugadorInput _jugadorFromRow(Map<String, dynamic> row) {
    return DiagnosticoJugadorInput(
      jugadorId: SupabaseParse.asString(row['id']),
      nombre: SupabaseParse.toStringOrNull(row['nombre']),
      saldoAcumulado: SupabaseParse.toDouble(row['saldo_acumulado']),
    );
  }
}
