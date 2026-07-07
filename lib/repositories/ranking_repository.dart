import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

class RankingJugador {
  final int jugadorId;
  final String jugadorKeyId;
  final String nombre;
  final int partidosJugados;
  final int pagosAlDia;
  final int pagosTardios;
  final int partidosImpagos;
  final double promedioDiasPago;
  final double saldoActual;

  const RankingJugador({
    required this.jugadorId,
    this.jugadorKeyId = '',
    required this.nombre,
    required this.partidosJugados,
    required this.pagosAlDia,
    required this.pagosTardios,
    required this.partidosImpagos,
    required this.promedioDiasPago,
    required this.saldoActual,
  });

  double get porcentajePagoAlDia =>
      partidosJugados == 0 ? 0 : (pagosAlDia / partidosJugados) * 100;

  int get scoreBuenPagador => pagosAlDia * 10 - partidosImpagos * 5 - pagosTardios * 2;

  int get scoreMalPagador => partidosImpagos * 10 + pagosTardios * 3 - pagosAlDia;
}

class RankingRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<RankingJugador>> getRanking() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        j.id AS jugador_id,
        j.nombre,
        j.saldo_acumulado,
        COUNT(dp.id) AS partidos_jugados,
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
        SUM(CASE WHEN dp.pagado = 0 THEN 1 ELSE 0 END) AS partidos_impagos
      FROM jugadores j
      LEFT JOIN detalles_partido dp ON dp.jugador_id = j.id AND dp.asistio = 1
      LEFT JOIN partidos p ON p.id = dp.partido_id
      GROUP BY j.id
      HAVING partidos_jugados > 0
      ORDER BY j.nombre COLLATE NOCASE ASC
    ''');

    final rankings = <RankingJugador>[];
    for (final row in rows) {
      final jugadorId = row['jugador_id'] as int;
      final promedio = await _promedioDiasPago(db, jugadorId);

      rankings.add(RankingJugador(
        jugadorId: jugadorId,
        jugadorKeyId: jugadorId.toString(),
        nombre: row['nombre'] as String,
        partidosJugados: row['partidos_jugados'] as int? ?? 0,
        pagosAlDia: row['pagos_al_dia'] as int? ?? 0,
        pagosTardios: row['pagos_tardios'] as int? ?? 0,
        partidosImpagos: row['partidos_impagos'] as int? ?? 0,
        promedioDiasPago: promedio,
        saldoActual: (row['saldo_acumulado'] as num?)?.toDouble() ?? 0,
      ));
    }
    return rankings;
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

  List<RankingJugador> mejoresPagadores(List<RankingJugador> all) {
    final copy = all
        .where((r) => r.pagosAlDia > 0 && r.partidosImpagos == 0)
        .toList();
    copy.sort((a, b) {
      final cmp = b.scoreBuenPagador.compareTo(a.scoreBuenPagador);
      if (cmp != 0) return cmp;
      return a.promedioDiasPago.compareTo(b.promedioDiasPago);
    });
    return copy;
  }

  List<RankingJugador> peoresPagadores(List<RankingJugador> all) {
    final copy = all
        .where((r) => r.partidosImpagos > 0 || r.pagosTardios > 0)
        .toList();
    copy.sort((a, b) {
      final cmp = b.scoreMalPagador.compareTo(a.scoreMalPagador);
      if (cmp != 0) return cmp;
      return b.promedioDiasPago.compareTo(a.promedioDiasPago);
    });
    return copy;
  }
}
