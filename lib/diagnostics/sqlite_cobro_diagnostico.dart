import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../domain/cobro_diagnostico.dart';

/// Carga datos locales (SQLite) y ejecuta diagnóstico SSOT sin tocar repos de negocio.
class SqliteCobroDiagnostico {
  SqliteCobroDiagnostico._();

  static Future<CobroDiagnosticoReporte> analizarBaseLocal({
    Database? database,
  }) async {
    final db = database ?? await DatabaseHelper.instance.database;

    final detalleRows = await db.rawQuery('''
      SELECT dp.id, dp.partido_id, dp.jugador_id, dp.asistio,
             dp.total, dp.monto_pagado, dp.pagado, j.nombre AS nombre_jugador
      FROM detalles_partido dp
      LEFT JOIN jugadores j ON j.id = dp.jugador_id
      ORDER BY dp.partido_id, dp.jugador_id
    ''');

    final historialRows = await db.rawQuery('''
      SELECT sh.id, sh.jugador_id, sh.partido_id, sh.saldo_anterior,
             sh.cargo_partido, sh.abono, sh.saldo_nuevo, sh.fecha, sh.concepto,
             j.nombre AS nombre_jugador
      FROM saldos_historicos sh
      LEFT JOIN jugadores j ON j.id = sh.jugador_id
      ORDER BY sh.jugador_id, sh.fecha, sh.id
    ''');

    final jugadorRows = await db.query(
      'jugadores',
      columns: ['id', 'nombre', 'saldo_acumulado'],
    );

    return CobroDiagnostico.analizar(
      detalles: detalleRows.map(_detalleFromRow).toList(),
      historial: historialRows.map(_historialFromRow).toList(),
      jugadores: jugadorRows.map(_jugadorFromRow).toList(),
    );
  }

  static DiagnosticoDetalleInput _detalleFromRow(Map<String, Object?> row) {
    return DiagnosticoDetalleInput(
      detalleId: row['id'] as int?,
      partidoId: row['partido_id'] as int,
      jugadorId: '${row['jugador_id']}',
      jugadorNombre: row['nombre_jugador'] as String?,
      asistio: (row['asistio'] as int? ?? 1) == 1,
      total: (row['total'] as num?)?.toDouble() ?? 0,
      montoPagado: (row['monto_pagado'] as num?)?.toDouble() ?? 0,
      pagado: (row['pagado'] as int? ?? 0) == 1,
    );
  }

  static DiagnosticoHistorialInput _historialFromRow(Map<String, Object?> row) {
    return DiagnosticoHistorialInput(
      historialId: row['id'] as int?,
      jugadorId: '${row['jugador_id']}',
      jugadorNombre: row['nombre_jugador'] as String?,
      partidoId: row['partido_id'] as int?,
      saldoAnterior: (row['saldo_anterior'] as num).toDouble(),
      cargoPartido: (row['cargo_partido'] as num?)?.toDouble() ?? 0,
      abono: (row['abono'] as num?)?.toDouble() ?? 0,
      saldoNuevo: (row['saldo_nuevo'] as num).toDouble(),
      fecha: DateTime.parse(row['fecha'] as String),
      concepto: row['concepto'] as String? ?? '',
    );
  }

  static DiagnosticoJugadorInput _jugadorFromRow(Map<String, Object?> row) {
    return DiagnosticoJugadorInput(
      jugadorId: '${row['id']}',
      nombre: row['nombre'] as String?,
      saldoAcumulado: (row['saldo_acumulado'] as num?)?.toDouble() ?? 0,
    );
  }
}
