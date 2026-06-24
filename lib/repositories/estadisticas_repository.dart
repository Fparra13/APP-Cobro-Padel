import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/estadisticas_jugador.dart';
import '../repositories/partido_repository.dart';

class EstadisticasRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final PartidoRepository _partidoRepo = PartidoRepository();

  Future<List<EstadisticasJugador>> getAll() async {
    await _partidoRepo.repararDetallesInconsistentes();

    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        j.id AS jugador_id,
        j.nombre,
        j.foto_path,
        j.saldo_acumulado,
        COUNT(DISTINCT dp.id) AS partidos_jugados,
        SUM(CASE
          WHEN dp.pagado = 1 AND dp.fecha_pago IS NOT NULL
            AND date(dp.fecha_pago) <= date(p.fecha, '+1 day')
          THEN 1 ELSE 0
        END) AS pagos_al_dia,
        SUM(CASE
          WHEN dp.pagado = 1 AND dp.fecha_pago IS NOT NULL
            AND date(dp.fecha_pago) > date(p.fecha, '+1 day')
          THEN 1 ELSE 0
        END) AS pagos_tardios,
        SUM(CASE WHEN dp.pagado = 0 THEN 1 ELSE 0 END) AS partidos_impagos,
        COALESCE(SUM(dp.total), 0) AS total_gastado,
        (
          SELECT COUNT(*)
          FROM convocatoria_jugadores cj
          WHERE cj.jugador_id = j.id
            AND cj.estado_confirmacion = 'confirmado'
        ) AS convocatorias_confirmadas,
        (
          SELECT COUNT(*)
          FROM detalles_partido dp2
          JOIN partidos p2 ON p2.id = dp2.partido_id
          WHERE dp2.jugador_id = j.id
            AND dp2.asistio = 1
            AND date(p2.fecha) >= date('now', '-90 days')
        ) AS partidos_90d
      FROM jugadores j
      LEFT JOIN detalles_partido dp ON dp.jugador_id = j.id AND dp.asistio = 1
      LEFT JOIN partidos p ON p.id = dp.partido_id
      GROUP BY j.id
      ORDER BY j.nombre COLLATE NOCASE ASC
    ''');

    final stats = <EstadisticasJugador>[];
    for (final row in rows) {
      final jugadorId = row['jugador_id'] as int;
      final promedio = await _promedioDiasPago(db, jugadorId);

      stats.add(EstadisticasJugador(
        jugadorId: jugadorId,
        nombre: row['nombre'] as String,
        fotoPath: row['foto_path'] as String?,
        partidosJugados: row['partidos_jugados'] as int? ?? 0,
        pagosAlDia: row['pagos_al_dia'] as int? ?? 0,
        pagosTardios: row['pagos_tardios'] as int? ?? 0,
        partidosImpagos: row['partidos_impagos'] as int? ?? 0,
        promedioDiasPago: promedio,
        totalGastado: (row['total_gastado'] as num?)?.toDouble() ?? 0,
        saldoActual: (row['saldo_acumulado'] as num?)?.toDouble() ?? 0,
        convocatoriasConfirmadas: row['convocatorias_confirmadas'] as int? ?? 0,
        partidosUltimos90Dias: row['partidos_90d'] as int? ?? 0,
      ));
    }
    return stats;
  }

  Future<double> _promedioDiasPago(Database db, int jugadorId) async {
    final rows = await db.rawQuery('''
      SELECT
        julianday(COALESCE(dp.fecha_pago, p.fecha)) - julianday(p.fecha) AS dias
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ? AND dp.asistio = 1 AND dp.pagado = 1
    ''', [jugadorId]);

    if (rows.isEmpty) return 0;
    final total = rows.fold<double>(
      0,
      (s, r) => s + ((r['dias'] as num?)?.toDouble() ?? 0),
    );
    return total / rows.length;
  }

  List<EstadisticasJugador> masParticipacion(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.partidosJugados > 0).toList()
      ..sort((a, b) => b.partidosJugados.compareTo(a.partidosJugados));
    return copy;
  }

  List<EstadisticasJugador> mejoresPagadores(List<EstadisticasJugador> all) {
    final copy = all
        .where((e) => e.partidosJugados >= 2 && e.partidosImpagos == 0)
        .toList()
      ..sort((a, b) {
        final cmp = b.scoreBuenPagador.compareTo(a.scoreBuenPagador);
        if (cmp != 0) return cmp;
        return b.porcentajePagoAlDia.compareTo(a.porcentajePagoAlDia);
      });
    return copy;
  }

  List<EstadisticasJugador> pagadoresRapidos(List<EstadisticasJugador> all) {
    final copy = all
        .where((e) => e.pagosAlDia > 0 && e.promedioDiasPago >= 0)
        .toList()
      ..sort((a, b) => a.promedioDiasPago.compareTo(b.promedioDiasPago));
    return copy;
  }

  List<EstadisticasJugador> masActivosRecientes(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.partidosUltimos90Dias > 0).toList()
      ..sort((a, b) =>
          b.partidosUltimos90Dias.compareTo(a.partidosUltimos90Dias));
    return copy;
  }

  List<EstadisticasJugador> mayorDeuda(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.saldoActual > 0).toList()
      ..sort((a, b) => b.saldoActual.compareTo(a.saldoActual));
    return copy;
  }

  List<EstadisticasJugador> masAportado(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.totalGastado > 0).toList()
      ..sort((a, b) => b.totalGastado.compareTo(a.totalGastado));
    return copy;
  }

  List<EstadisticasJugador> reyConvocatoria(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.convocatoriasConfirmadas > 0).toList()
      ..sort((a, b) =>
          b.convocatoriasConfirmadas.compareTo(a.convocatoriasConfirmadas));
    return copy;
  }
}
