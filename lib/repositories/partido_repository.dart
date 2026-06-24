import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/costo_variable.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../models/partido.dart';
import '../repositories/jugador_repository.dart';
import '../services/calculation_service.dart';
import '../utils/formatters.dart';

class PartidoCompleto {
  final Partido partido;
  final List<DetallePartido> detalles;
  final List<CostoVariable> costosVariables;
  final Map<int, List<AsignacionCostoVariable>> asignacionesPorCosto;

  const PartidoCompleto({
    required this.partido,
    required this.detalles,
    this.costosVariables = const [],
    this.asignacionesPorCosto = const {},
  });
}

class ResumenJugador {
  final Jugador jugador;
  final double saldoActual;
  final int partidosJugados;
  final double totalPendiente;

  const ResumenJugador({
    required this.jugador,
    required this.saldoActual,
    required this.partidosJugados,
    required this.totalPendiente,
  });
}

class PartidoRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final JugadorRepository _jugadorRepo = JugadorRepository();

  Future<List<Partido>> getAll({EstadoPartido? soloEstado}) async {
    final db = await _db.database;
    if (soloEstado != null) {
      final rows = await db.query(
        'partidos',
        where: 'estado = ?',
        whereArgs: [soloEstado.dbValue],
        orderBy: 'fecha DESC',
      );
      return rows.map(Partido.fromMap).toList();
    }
    final rows = await db.query('partidos', orderBy: 'fecha DESC');
    return rows.map(Partido.fromMap).toList();
  }

  Future<List<Partido>> getJugados() =>
      getAll(soloEstado: EstadoPartido.jugado);

  Future<List<String>> getRecintosRecientes({int limit = 8}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT recinto
      FROM partidos
      WHERE recinto IS NOT NULL AND TRIM(recinto) != ''
      ORDER BY fecha DESC
      LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => (r['recinto'] as String).trim())
        .where((r) => r.isNotEmpty)
        .toList();
  }

  Future<List<DeudaPartidoAnterior>> getPartidosPendientesJugador(
    int jugadorId,
  ) async {
    await reconciliarDetallesJugador(jugadorId);

    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS partido_id, p.fecha, p.recinto, dp.total, dp.monto_pagado
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ?
        AND dp.asistio = 1
        AND dp.pagado = 0
      ORDER BY p.fecha ASC
    ''', [jugadorId]);

    return rows.map((r) {
      final total = (r['total'] as num).toDouble();
      final pagado = (r['monto_pagado'] as num?)?.toDouble() ?? 0;
      return DeudaPartidoAnterior(
        partidoId: r['partido_id'] as int,
        fecha: DateTime.parse(r['fecha'] as String),
        recinto: r['recinto'] as String?,
        montoPendiente: (total - pagado).clamp(0.0, double.infinity),
      );
    }).where((d) => d.montoPendiente > 0).toList();
  }

  /// Jugadores con al menos un partido impago cuya fecha supera [diasMinimos].
  Future<List<ResumenJugador>> getDeudoresVencidos(int diasMinimos) async {
    final resumenes = await getResumenJugadores();
    final vencidos = <ResumenJugador>[];
    final ahora = DateTime.now();

    for (final r in resumenes) {
      if (r.saldoActual <= 0) continue;
      final pendientes = await getPartidosPendientesJugador(r.jugador.id!);
      final impagoVencido = pendientes.any((p) {
        final dias = ahora.difference(p.fecha).inDays;
        return dias >= diasMinimos;
      });
      if (impagoVencido) vencidos.add(r);
    }

    vencidos.sort(
      (a, b) => a.jugador.nombre.compareTo(b.jugador.nombre),
    );
    return vencidos;
  }

  /// Partidos anteriores impagos que explican la deuda acumulada.
  Future<List<DeudaPartidoAnterior>> getDeudasPartidosAnteriores({
    required int jugadorId,
    required int partidoActualId,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS partido_id, p.fecha, p.recinto, dp.total, dp.monto_pagado
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ?
        AND dp.asistio = 1
        AND dp.pagado = 0
        AND dp.partido_id != ?
      ORDER BY p.fecha ASC
    ''', [jugadorId, partidoActualId]);

    return rows.map((r) {
      final total = (r['total'] as num).toDouble();
      final pagado = (r['monto_pagado'] as num?)?.toDouble() ?? 0;
      return DeudaPartidoAnterior(
        partidoId: r['partido_id'] as int,
        fecha: DateTime.parse(r['fecha'] as String),
        recinto: r['recinto'] as String?,
        montoPendiente: (total - pagado).clamp(0.0, double.infinity),
      );
    }).where((d) => d.montoPendiente > 0).toList();
  }

  Future<({int partidosJugados, int partidosPagados, int partidosImpagos})>
      getResumenPartidosJugador(int jugadorId) async {
    final db = await _db.database;
    final row = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS partidos,
        SUM(CASE WHEN pagado = 1 THEN 1 ELSE 0 END) AS pagados,
        SUM(CASE WHEN pagado = 0 THEN 1 ELSE 0 END) AS impagos
      FROM detalles_partido
      WHERE jugador_id = ? AND asistio = 1
      ''',
      [jugadorId],
    );
    final data = row.first;
    return (
      partidosJugados: (data['partidos'] as int?) ?? 0,
      partidosPagados: (data['pagados'] as int?) ?? 0,
      partidosImpagos: (data['impagos'] as int?) ?? 0,
    );
  }

  Future<PartidoCompleto?> getCompleto(int partidoId) async {
    final db = await _db.database;

    final partidoRows =
        await db.query('partidos', where: 'id = ?', whereArgs: [partidoId]);
    if (partidoRows.isEmpty) return null;

    final detalleRows = await db.rawQuery('''
      SELECT dp.*, j.nombre AS nombre_jugador
      FROM detalles_partido dp
      JOIN jugadores j ON j.id = dp.jugador_id
      WHERE dp.partido_id = ?
      ORDER BY j.nombre COLLATE NOCASE ASC
    ''', [partidoId]);

    final costoRows = await db.query(
      'costos_variables',
      where: 'partido_id = ?',
      whereArgs: [partidoId],
    );
    final costos = costoRows.map(CostoVariable.fromMap).toList();

    final asignaciones = <int, List<AsignacionCostoVariable>>{};
    for (final costo in costos) {
      final rows = await db.query(
        'asignaciones_costo',
        where: 'costo_variable_id = ?',
        whereArgs: [costo.id],
      );
      asignaciones[costo.id!] =
          rows.map(AsignacionCostoVariable.fromMap).toList();
    }

    return PartidoCompleto(
      partido: Partido.fromMap(partidoRows.first),
      detalles: detalleRows.map(DetallePartido.fromMap).toList(),
      costosVariables: costos,
      asignacionesPorCosto: asignaciones,
    );
  }

  Future<List<DesgloseJugador>> getDesglose(int partidoId) async {
    final completo = await getCompleto(partidoId);
    if (completo == null) return [];

    final db = await _db.database;
    final historicos = await db.query(
      'saldos_historicos',
      where: 'partido_id = ?',
      whereArgs: [partidoId],
    );
    final saldosAnteriores = {
      for (final h in historicos)
        h['jugador_id'] as int: (h['saldo_anterior'] as num).toDouble(),
    };

    return DesglosePartido.calcular(
      partido: completo.partido,
      detalles: completo.detalles,
      costosVariables: completo.costosVariables,
      asignacionesPorCosto: completo.asignacionesPorCosto,
      saldosAnteriores: saldosAnteriores,
    );
  }

  Future<List<ResumenJugador>> getResumenJugadores() async {
    final jugadores = await _jugadorRepo.getAll();
    final db = await _db.database;

    final resumenes = <ResumenJugador>[];
    for (final jugador in jugadores) {
      final stats = await db.rawQuery('''
        SELECT
          COUNT(*) AS partidos,
          SUM(CASE WHEN pagado = 0 THEN total ELSE 0 END) AS pendiente
        FROM detalles_partido
        WHERE jugador_id = ? AND asistio = 1
      ''', [jugador.id]);

      resumenes.add(ResumenJugador(
        jugador: jugador,
        saldoActual: jugador.saldoAcumulado,
        partidosJugados: (stats.first['partidos'] as int?) ?? 0,
        totalPendiente: (stats.first['pendiente'] as num?)?.toDouble() ?? 0,
      ));
    }

    resumenes.sort(
      (a, b) => b.saldoActual.compareTo(a.saldoActual),
    );
    return resumenes;
  }

  Future<PartidoCompleto?> getUltimoPartido() async {
    final partidos = await getJugados();
    if (partidos.isEmpty) return null;
    return getCompleto(partidos.first.id!);
  }

  Future<void> recalcularSaldosDesdeHistorial() async {
    final db = await _db.database;
    await db.update('jugadores', {'saldo_acumulado': 0});

    final rows = await db.query(
      'saldos_historicos',
      orderBy: 'fecha ASC, id ASC',
    );

    final saldosFinales = <int, double>{};
    for (final row in rows) {
      saldosFinales[row['jugador_id'] as int] =
          (row['saldo_nuevo'] as num).toDouble();
    }

    for (final entry in saldosFinales.entries) {
      await db.update(
        'jugadores',
        {'saldo_acumulado': entry.value},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  Future<void> actualizarPartido({
    required int partidoId,
    required Partido partido,
    required List<int> jugadoresAsistentes,
    required Map<int, double> montoPagadoPorJugador,
    required List<
            ({
              String concepto,
              double montoTotal,
              List<int> jugadores,
              String? comprobantePath,
            })>
        costosVariables,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('partidos', where: 'id = ?', whereArgs: [partidoId]);
    });
    await recalcularSaldosDesdeHistorial();
    await guardarPartido(
      partido: partido,
      jugadoresAsistentes: jugadoresAsistentes,
      montoPagadoPorJugador: montoPagadoPorJugador,
      costosVariables: costosVariables,
    );
  }

  Future<void> eliminarPartido(int id) async {
    final db = await _db.database;
    await db.delete('partidos', where: 'id = ?', whereArgs: [id]);
    await recalcularSaldosDesdeHistorial();
  }

  /// Guarda un partido completo con cálculos y actualización de saldos.
  Future<int> guardarPartido({
    required Partido partido,
    required List<int> jugadoresAsistentes,
    required Map<int, double> montoPagadoPorJugador,
    required List<
            ({
              String concepto,
              double montoTotal,
              List<int> jugadores,
              String? comprobantePath,
            })>
        costosVariables,
    Map<int, double>? saldosAnterioresSnapshot,
  }) async {
    final db = await _db.database;
    final asistentes = jugadoresAsistentes.toSet().toList();
    final prorrateo = CalculationService.prorrateoFijo(
      costoCancha: partido.costoCancha,
      costoPelotas: partido.costoPelotas,
      cantidadAsistentes: asistentes.length,
    );

    final variablesPorJugador = <int, double>{};
    for (final id in asistentes) {
      variablesPorJugador[id] = 0;
    }

    return db.transaction((txn) async {
      final partidoId = await txn.insert('partidos', partido.toMap());

      final costoIds = <int>[];
      for (final cv in costosVariables) {
        final costoId = await txn.insert('costos_variables', {
          'partido_id': partidoId,
          'concepto': cv.concepto,
          'monto_total': cv.montoTotal,
          'comprobante_path': cv.comprobantePath,
        });
        costoIds.add(costoId);

        final participantes = cv.jugadores.isEmpty ? asistentes : cv.jugadores;
        final montoIndividual = participantes.isEmpty
            ? 0.0
            : CalculationService.prorratear(cv.montoTotal, participantes.length);

        for (final jugadorId in participantes) {
          await txn.insert('asignaciones_costo', {
            'costo_variable_id': costoId,
            'jugador_id': jugadorId,
            'monto': montoIndividual,
          });
          variablesPorJugador[jugadorId] =
              (variablesPorJugador[jugadorId] ?? 0) + montoIndividual;
        }
      }

      for (final jugadorId in asistentes) {
        final jugadorRows = await txn.query(
          'jugadores',
          where: 'id = ?',
          whereArgs: [jugadorId],
        );
        final saldoAnterior = saldosAnterioresSnapshot?[jugadorId] ??
            (jugadorRows.first['saldo_acumulado'] as num).toDouble();

        final totalVars = variablesPorJugador[jugadorId] ?? 0;
        final cargo = CalculationService.cargoPartido(
          prorrateoFijo: prorrateo,
          totalVariables: totalVars,
        );
        final montoPagado =
            roundMoney(montoPagadoPorJugador[jugadorId] ?? 0).toDouble();
        final saldoNuevo = CalculationService.saldoDespuesPago(
          saldoAnterior: saldoAnterior,
          cargoPartido: cargo,
          montoPagado: montoPagado,
        );
        final favorAplicado = CalculationService.saldoFavorAplicado(
          saldoAnterior: saldoAnterior,
          cargoPartido: cargo,
        );
        final pagado = saldoNuevo <= 0;
        final ahora = DateTime.now();
        final concepto = pagado
            ? (montoPagado == 0 && favorAplicado > 0
                ? 'Partido cubierto con saldo a favor'
                : 'Partido pagado')
            : montoPagado > 0
                ? 'Pago parcial'
                : 'Deuda acumulada';

        await txn.insert('detalles_partido', {
          'partido_id': partidoId,
          'jugador_id': jugadorId,
          'asistio': 1,
          'prorrateo_fijo': prorrateo,
          'total_variables': totalVars,
          'total': cargo,
          'pagado': pagado ? 1 : 0,
          'monto_pagado': montoPagado,
          'fecha_pago': pagado || montoPagado > 0
              ? ahora.toIso8601String()
              : null,
        });

        await txn.update(
          'jugadores',
          {'saldo_acumulado': saldoNuevo},
          where: 'id = ?',
          whereArgs: [jugadorId],
        );

        await txn.insert('saldos_historicos', {
          'jugador_id': jugadorId,
          'partido_id': partidoId,
          'saldo_anterior': saldoAnterior,
          'cargo_partido': cargo,
          'abono': montoPagado,
          'saldo_nuevo': saldoNuevo,
          'fecha': montoPagado > 0 ? ahora.toIso8601String() : partido.fecha.toIso8601String(),
          'concepto': concepto,
        });

        await _sincronizarDetallesTrasPago(
          db: txn,
          jugadorId: jugadorId,
          saldoNuevo: saldoNuevo,
          montoAplicado: montoPagado,
          fechaPago: ahora,
        );
      }

      return partidoId;
    });
  }

  /// Convierte un partido en organización a jugado con cobros.
  Future<void> completarPartidoOrganizado({
    required int partidoId,
    required Partido partido,
    required List<int> jugadoresAsistentes,
    required Map<int, double> montoPagadoPorJugador,
    required List<
            ({
              String concepto,
              double montoTotal,
              List<int> jugadores,
              String? comprobantePath,
            })>
        costosVariables,
    Map<int, double>? saldosAnterioresSnapshot,
  }) async {
    final db = await _db.database;
    final asistentes = jugadoresAsistentes.toSet().toList();
    final prorrateo = CalculationService.prorrateoFijo(
      costoCancha: partido.costoCancha,
      costoPelotas: partido.costoPelotas,
      cantidadAsistentes: asistentes.length,
    );

    final variablesPorJugador = <int, double>{};
    for (final id in asistentes) {
      variablesPorJugador[id] = 0;
    }

    await db.transaction((txn) async {
      final map = partido.copyWith(estado: EstadoPartido.jugado).toMap();
      map.remove('id');
      await txn.update('partidos', map, where: 'id = ?', whereArgs: [partidoId]);

      await txn.delete(
        'convocatoria_jugadores',
        where: 'partido_id = ?',
        whereArgs: [partidoId],
      );

      for (final cv in costosVariables) {
        final costoId = await txn.insert('costos_variables', {
          'partido_id': partidoId,
          'concepto': cv.concepto,
          'monto_total': cv.montoTotal,
          'comprobante_path': cv.comprobantePath,
        });

        final participantes = cv.jugadores.isEmpty ? asistentes : cv.jugadores;
        final montoIndividual = participantes.isEmpty
            ? 0.0
            : CalculationService.prorratear(cv.montoTotal, participantes.length);

        for (final jugadorId in participantes) {
          await txn.insert('asignaciones_costo', {
            'costo_variable_id': costoId,
            'jugador_id': jugadorId,
            'monto': montoIndividual,
          });
          variablesPorJugador[jugadorId] =
              (variablesPorJugador[jugadorId] ?? 0) + montoIndividual;
        }
      }

      for (final jugadorId in asistentes) {
        final jugadorRows = await txn.query(
          'jugadores',
          where: 'id = ?',
          whereArgs: [jugadorId],
        );
        final saldoAnterior = saldosAnterioresSnapshot?[jugadorId] ??
            (jugadorRows.first['saldo_acumulado'] as num).toDouble();

        final totalVars = variablesPorJugador[jugadorId] ?? 0;
        final cargo = CalculationService.cargoPartido(
          prorrateoFijo: prorrateo,
          totalVariables: totalVars,
        );
        final montoPagado =
            roundMoney(montoPagadoPorJugador[jugadorId] ?? 0).toDouble();
        final saldoNuevo = CalculationService.saldoDespuesPago(
          saldoAnterior: saldoAnterior,
          cargoPartido: cargo,
          montoPagado: montoPagado,
        );
        final favorAplicado = CalculationService.saldoFavorAplicado(
          saldoAnterior: saldoAnterior,
          cargoPartido: cargo,
        );
        final pagado = saldoNuevo <= 0;
        final ahora = DateTime.now();
        final concepto = pagado
            ? (montoPagado == 0 && favorAplicado > 0
                ? 'Partido cubierto con saldo a favor'
                : 'Partido pagado')
            : montoPagado > 0
                ? 'Pago parcial'
                : 'Deuda acumulada';

        await txn.insert('detalles_partido', {
          'partido_id': partidoId,
          'jugador_id': jugadorId,
          'asistio': 1,
          'prorrateo_fijo': prorrateo,
          'total_variables': totalVars,
          'total': cargo,
          'pagado': pagado ? 1 : 0,
          'monto_pagado': montoPagado,
          'fecha_pago': pagado || montoPagado > 0
              ? ahora.toIso8601String()
              : null,
        });

        await txn.update(
          'jugadores',
          {'saldo_acumulado': saldoNuevo},
          where: 'id = ?',
          whereArgs: [jugadorId],
        );

        await txn.insert('saldos_historicos', {
          'jugador_id': jugadorId,
          'partido_id': partidoId,
          'saldo_anterior': saldoAnterior,
          'cargo_partido': cargo,
          'abono': montoPagado,
          'saldo_nuevo': saldoNuevo,
          'fecha': montoPagado > 0
              ? ahora.toIso8601String()
              : partido.fecha.toIso8601String(),
          'concepto': concepto,
        });

        await _sincronizarDetallesTrasPago(
          db: txn,
          jugadorId: jugadorId,
          saldoNuevo: saldoNuevo,
          montoAplicado: montoPagado,
          fechaPago: ahora,
        );
      }
    });
  }

  /// Alinea detalles_partido con el saldo real tras un pago o abono.
  /// El ranking usa estos registros; sin esto quedan impagos fantasma.
  Future<void> _sincronizarDetallesTrasPago({
    required DatabaseExecutor db,
    required int jugadorId,
    required double saldoNuevo,
    required double montoAplicado,
    required DateTime fechaPago,
  }) async {
    final ahora = fechaPago.toIso8601String();

    if (saldoNuevo <= 0) {
      await db.rawUpdate(
        '''
        UPDATE detalles_partido
        SET pagado = 1,
            fecha_pago = ?,
            monto_pagado = total
        WHERE jugador_id = ? AND asistio = 1 AND pagado = 0
        ''',
        [ahora, jugadorId],
      );
      return;
    }

    if (montoAplicado <= 0) return;

    final rows = await db.rawQuery(
      '''
      SELECT dp.id, dp.total, dp.monto_pagado
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ? AND dp.asistio = 1 AND dp.pagado = 0
      ORDER BY p.fecha ASC, dp.id ASC
      ''',
      [jugadorId],
    );

    var restante = roundMoney(montoAplicado).toDouble();
    for (final row in rows) {
      if (restante <= 0) break;

      final id = row['id'] as int;
      final total = (row['total'] as num).toDouble();
      final yaPagado = (row['monto_pagado'] as num?)?.toDouble() ?? 0;
      final pendiente = roundMoney(total - yaPagado).toDouble();
      if (pendiente <= 0) {
        await db.update(
          'detalles_partido',
          {'pagado': 1, 'fecha_pago': ahora},
          where: 'id = ?',
          whereArgs: [id],
        );
        continue;
      }

      final aplicar = restante >= pendiente ? pendiente : restante;
      final nuevoMonto = roundMoney(yaPagado + aplicar).toDouble();
      final cubierto = nuevoMonto >= total - 0.005;

      await db.update(
        'detalles_partido',
        {
          'monto_pagado': nuevoMonto,
          'pagado': cubierto ? 1 : 0,
          'fecha_pago': ahora,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      restante = roundMoney(restante - aplicar).toDouble();
    }
  }

  Future<double> _sumPendienteDetalles(
    DatabaseExecutor db,
    int jugadorId,
  ) async {
    final rows = await db.rawQuery('''
      SELECT dp.total, dp.monto_pagado
      FROM detalles_partido dp
      WHERE dp.jugador_id = ? AND dp.asistio = 1 AND dp.pagado = 0
    ''', [jugadorId]);

    var sum = 0.0;
    for (final r in rows) {
      final total = (r['total'] as num).toDouble();
      final pagado = (r['monto_pagado'] as num?)?.toDouble() ?? 0;
      sum += (total - pagado).clamp(0.0, double.infinity);
    }
    return roundMoney(sum).toDouble();
  }

  /// Alinea los detalles impagos de un jugador con su saldo_acumulado real.
  Future<void> reconciliarDetallesJugador(int jugadorId) async {
    final jugador = await _jugadorRepo.getById(jugadorId);
    if (jugador == null) return;

    final db = await _db.database;
    await _reconciliarDetallesJugador(
      db: db,
      jugadorId: jugadorId,
      saldo: jugador.saldoAcumulado,
    );
  }

  Future<void> _reconciliarDetallesJugador({
    required DatabaseExecutor db,
    required int jugadorId,
    required double saldo,
  }) async {
    final ahora = DateTime.now();

    if (saldo <= 0) {
      await _sincronizarDetallesTrasPago(
        db: db,
        jugadorId: jugadorId,
        saldoNuevo: saldo,
        montoAplicado: 0,
        fechaPago: ahora,
      );
      return;
    }

    final sumPendiente = await _sumPendienteDetalles(db, jugadorId);
    final diff = roundMoney(sumPendiente - saldo).toDouble();

    if (diff > 0.01) {
      await _sincronizarDetallesTrasPago(
        db: db,
        jugadorId: jugadorId,
        saldoNuevo: saldo,
        montoAplicado: diff,
        fechaPago: ahora,
      );
      return;
    }

    if (diff < -0.01) {
      await _reabrirDetallesPorDeficit(
        db: db,
        jugadorId: jugadorId,
        deficit: roundMoney(saldo - sumPendiente).toDouble(),
      );
    }
  }

  /// Reabre partidos pagados (del más reciente al más antiguo) cuando
  /// la suma de impagos quedó por debajo del saldo real.
  Future<void> _reabrirDetallesPorDeficit({
    required DatabaseExecutor db,
    required int jugadorId,
    required double deficit,
  }) async {
    if (deficit <= 0) return;

    final rows = await db.rawQuery('''
      SELECT dp.id, dp.total, dp.monto_pagado
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ? AND dp.asistio = 1 AND dp.pagado = 1
      ORDER BY p.fecha DESC, dp.id DESC
    ''', [jugadorId]);

    var restante = deficit;
    for (final row in rows) {
      if (restante <= 0.01) break;

      final id = row['id'] as int;
      final total = (row['total'] as num).toDouble();
      final yaPagado = (row['monto_pagado'] as num?)?.toDouble() ?? 0;
      if (yaPagado <= 0) continue;

      final reabrir = restante >= yaPagado ? yaPagado : restante;
      final nuevoPagado = roundMoney(yaPagado - reabrir).toDouble();
      final siguePagado = nuevoPagado >= total - 0.005;

      final updates = <String, Object?>{
        'monto_pagado': nuevoPagado,
        'pagado': siguePagado ? 1 : 0,
      };
      if (!siguePagado) updates['fecha_pago'] = null;

      await db.update(
        'detalles_partido',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );

      restante = roundMoney(restante - reabrir).toDouble();
    }
  }

  /// Repara detalles_partido desalineados con el saldo acumulado de cada jugador.
  Future<void> repararDetallesInconsistentes() async {
    final db = await _db.database;
    final jugadores = await db.query('jugadores');
    for (final j in jugadores) {
      await _reconciliarDetallesJugador(
        db: db,
        jugadorId: j['id'] as int,
        saldo: (j['saldo_acumulado'] as num?)?.toDouble() ?? 0,
      );
    }
  }

  Future<void> registrarAbono({
    required int jugadorId,
    required double monto,
    String concepto = 'Abono manual',
  }) async {
    final jugador = await _jugadorRepo.getById(jugadorId);
    if (jugador == null) return;

    final saldoAnterior = jugador.saldoAcumulado;
    final saldoNuevo = roundMoney(saldoAnterior - monto).toDouble();
    final ahora = DateTime.now();

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'jugadores',
        {'saldo_acumulado': saldoNuevo},
        where: 'id = ?',
        whereArgs: [jugadorId],
      );

      await txn.insert('saldos_historicos', {
        'jugador_id': jugadorId,
        'saldo_anterior': saldoAnterior,
        'cargo_partido': 0,
        'abono': monto,
        'saldo_nuevo': saldoNuevo.toDouble(),
        'fecha': ahora.toIso8601String(),
        'concepto': concepto,
      });

      await _sincronizarDetallesTrasPago(
        db: txn,
        jugadorId: jugadorId,
        saldoNuevo: saldoNuevo.toDouble(),
        montoAplicado: monto,
        fechaPago: ahora,
      );
    });
  }

  Future<int> delete(int id) async {
    await eliminarPartido(id);
    return 1;
  }
}
