import 'package:sqflite/sqflite.dart';

import '../core/sport_type.dart';
import '../domain/cobro_logic.dart';
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
  /// Saldo anterior del jugador al registrar este partido (UUID o id local).
  final Map<String, double> saldoAnteriorPorJugador;

  const PartidoCompleto({
    required this.partido,
    required this.detalles,
    this.costosVariables = const [],
    this.asignacionesPorCosto = const {},
    this.saldoAnteriorPorJugador = const {},
  });

  double saldoAnteriorCobro(DetallePartido d) {
    final snap = snapshotSaldoCobro(d);
    return snap ?? 0;
  }

  /// Snapshot inmutable de `saldos_historicos`; null si no existe.
  double? snapshotSaldoCobro(DetallePartido d) {
    final key = d.jugadorKeyId;
    if (key.isEmpty || !saldoAnteriorPorJugador.containsKey(key)) {
      return null;
    }
    return saldoAnteriorPorJugador[key];
  }

  int contarAsistentesConDeudaNeta() {
    var n = 0;
    for (final d in detalles) {
      if (!d.asistio) continue;
      final snap = snapshotSaldoCobro(d);
      if (snap == null) continue;
      if (d.tieneDeudaNeto(snapshotSaldoAnterior: snap)) n++;
    }
    return n;
  }
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

  /// Deuda neta del jugador. Fuente: [saldoActual] (`profiles.saldo_acumulado`).
  double get deudaVisible =>
      CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoActual);

  /// Crédito a favor del jugador (positivo).
  double get creditoVisible =>
      CobroLogic.obtenerCreditoJugador(saldoAcumulado: saldoActual);

  bool get tieneCredito => creditoVisible > 0.005;

  bool get tieneDeuda => deudaVisible > 0.005;
}

class PartidoRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final JugadorRepository _jugadorRepo = JugadorRepository();

  EstadoPagoPartidoResult _estadoPagoPartido({
    required double saldoAnterior,
    required double cargo,
    required double montoPagadoOrganizador,
  }) =>
      CobroLogic.estadoPagoPartido(
        saldoAnterior: saldoAnterior,
        cargo: cargo,
        montoPagadoOrganizador: montoPagadoOrganizador,
      );

  Future<double> _requerirSaldoAnteriorSnapshot(
    DatabaseExecutor db, {
    required int jugadorId,
    required int partidoId,
  }) async {
    final rows = await db.query(
      'saldos_historicos',
      columns: ['saldo_anterior'],
      where: 'partido_id = ? AND jugador_id = ?',
      whereArgs: [partidoId, jugadorId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw DatosInconsistentesException(
        'Datos inconsistentes: falta snapshot saldo_anterior '
        '(jugador $jugadorId, partido $partidoId)',
      );
    }
    return CobroLogic.saldoAnteriorAlPartido(
      snapshotHistorico: (rows.first['saldo_anterior'] as num).toDouble(),
    );
  }

  double _saldoAnteriorAlRegistrarCargo({
    required double saldoAcumulado,
    Map<int, double>? saldosAnterioresSnapshot,
    required int jugadorId,
  }) {
    final snap = saldosAnterioresSnapshot?[jugadorId];
    if (snap != null) return roundMoney(snap).toDouble();
    return roundMoney(saldoAcumulado).toDouble();
  }

  Future<void> _aplicarPagoEnDetallesImpagos({
    required DatabaseExecutor db,
    required int jugadorId,
    required double monto,
    required DateTime fecha,
  }) async {
    if (monto <= 0.005) return;

    final rows = await db.rawQuery(
      '''
      SELECT dp.id, dp.total, dp.monto_pagado, dp.partido_id
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ? AND dp.asistio = 1 AND dp.pagado = 0
      ORDER BY p.fecha ASC, dp.partido_id ASC
      ''',
      [jugadorId],
    );

    var restante = roundMoney(monto).toDouble();
    final ahora = fecha.toIso8601String();

    for (final row in rows) {
      if (restante <= 0.005) break;

      final id = row['id'] as int;
      final partidoId = row['partido_id'] as int;
      final total = (row['total'] as num).toDouble();
      final yaPagado = (row['monto_pagado'] as num?)?.toDouble() ?? 0;

      final saldoAnt = await _requerirSaldoAnteriorSnapshot(
        db,
        jugadorId: jugadorId,
        partidoId: partidoId,
      );
      final pendiente = CobroLogic.obtenerPendientePartido(
        saldoAnteriorAlPartido: saldoAnt,
        cargoPartido: total,
        montoPagadoEnPartido: yaPagado,
      );

      if (pendiente <= 0.005) {
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
      final cubierto = CobroLogic.partidoEstaCerrado(
        saldoAnteriorAlPartido: saldoAnt,
        cargoPartido: total,
        montoPagadoEnPartido: nuevoMonto,
      );

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

  Future<void> _insertarCargoJugador({
    required DatabaseExecutor txn,
    required int partidoId,
    required int jugadorId,
    required Partido partido,
    required double prorrateo,
    required double totalVars,
    required double montoOrganizador,
    Map<int, double>? saldosAnterioresSnapshot,
    required double saldoAcumuladoVivo,
  }) async {
    final saldoAnterior = _saldoAnteriorAlRegistrarCargo(
      saldoAcumulado: saldoAcumuladoVivo,
      saldosAnterioresSnapshot: saldosAnterioresSnapshot,
      jugadorId: jugadorId,
    );
    final cargo = CalculationService.cargoPartido(
      prorrateoFijo: prorrateo,
      totalVariables: totalVars,
    );
    final pago = _estadoPagoPartido(
      saldoAnterior: saldoAnterior,
      cargo: cargo,
      montoPagadoOrganizador: roundMoney(montoOrganizador).toDouble(),
    );
    final ahora = DateTime.now();

    await txn.insert('detalles_partido', {
      'partido_id': partidoId,
      'jugador_id': jugadorId,
      'asistio': 1,
      'prorrateo_fijo': prorrateo,
      'total_variables': totalVars,
      'total': cargo,
      'pagado': pago.pagado ? 1 : 0,
      'monto_pagado': pago.montoPagado,
      if (pago.pagado || pago.montoPagado > 0)
        'fecha_pago': ahora.toIso8601String(),
    });

    await txn.insert('saldos_historicos', {
      'jugador_id': jugadorId,
      'partido_id': partidoId,
      'saldo_anterior': saldoAnterior,
      'cargo_partido': cargo,
      'abono': pago.montoPagado,
      'saldo_nuevo': pago.saldoNuevo,
      'fecha': pago.montoPagado > 0
          ? ahora.toIso8601String()
          : partido.fecha.toIso8601String(),
      'concepto': pago.concepto,
    });

    await txn.update(
      'jugadores',
      {'saldo_acumulado': pago.saldoNuevo},
      where: 'id = ?',
      whereArgs: [jugadorId],
    );
  }

  Future<void> _recalcularSaldoJugadorLocal(
    DatabaseExecutor db,
    int jugadorId,
  ) async {
    final rows = await db.query(
      'saldos_historicos',
      where: 'jugador_id = ?',
      whereArgs: [jugadorId],
      orderBy: 'fecha ASC, id ASC',
    );
    if (rows.isEmpty) {
      await db.update(
        'jugadores',
        {'saldo_acumulado': 0},
        where: 'id = ?',
        whereArgs: [jugadorId],
      );
      return;
    }
    final saldo = (rows.last['saldo_nuevo'] as num).toDouble();
    await db.update(
      'jugadores',
      {'saldo_acumulado': saldo},
      where: 'id = ?',
      whereArgs: [jugadorId],
    );
  }

  Future<Map<String, double>> _fetchSnapshotsPorPartidoJugadorLocal(
    DatabaseExecutor db, {
    Iterable<int>? partidoIds,
    int? jugadorId,
  }) async {
    if (partidoIds != null && partidoIds.isEmpty) return {};

    final whereParts = <String>[];
    final args = <Object?>[];

    if (jugadorId != null) {
      whereParts.add('jugador_id = ?');
      args.add(jugadorId);
    }
    if (partidoIds != null) {
      final placeholders = List.filled(partidoIds.length, '?').join(',');
      whereParts.add('partido_id IN ($placeholders)');
      args.addAll(partidoIds);
    }
    if (whereParts.isEmpty) return {};

    final rows = await db.query(
      'saldos_historicos',
      columns: ['partido_id', 'jugador_id', 'saldo_anterior'],
      where: whereParts.join(' AND '),
      whereArgs: args,
    );

    return {
      for (final r in rows)
        CobroLogic.claveSnapshotPartidoJugador(
          partidoId: r['partido_id'] as int,
          jugadorId: r['jugador_id'] as int,
        ): (r['saldo_anterior'] as num).toDouble(),
    };
  }

  List<DeudaPartidoAnterior> _mapFilasAPendientesNetos(
    List<Map<String, Object?>> rows,
    Map<String, double> snapshots, {
    required int jugadorId,
  }) {
    final result = <DeudaPartidoAnterior>[];
    for (final r in rows) {
      final partidoId = r['partido_id'] as int;
      final key = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: partidoId,
        jugadorId: jugadorId,
      );
      final pendiente = CobroLogic.pendienteNetoDetalle(
        partidoId: partidoId,
        jugadorId: jugadorId,
        cargoPartido: (r['total'] as num).toDouble(),
        montoPagadoEnPartido: (r['monto_pagado'] as num?)?.toDouble() ?? 0,
        snapshotSaldoAnterior: snapshots[key],
      );
      if (pendiente <= 0.005) continue;
      result.add(
        DeudaPartidoAnterior(
          partidoId: partidoId,
          fecha: DateTime.parse(r['fecha'] as String),
          recinto: r['recinto'] as String?,
          pendienteNeto: pendiente,
          sportType: SportType.fromDb(r['sport_type'] as String?),
        ),
      );
    }
    result.sort((a, b) => a.fecha.compareTo(b.fecha));
    return result;
  }

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
    int jugadorId, {
    bool reconciliar = false,
  }) async {
    if (reconciliar) {
      throw UnsupportedError(
        'reconciliar en getPartidosPendientesJugador ya no está soportado',
      );
    }

    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS partido_id, p.fecha, p.recinto, p.sport_type,
             dp.total, dp.monto_pagado
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ?
        AND dp.asistio = 1
      ORDER BY p.fecha ASC
    ''', [jugadorId]);

    final partidoIds =
        rows.map((r) => r['partido_id'] as int).toSet();
    final snapshots = await _fetchSnapshotsPorPartidoJugadorLocal(
      db,
      jugadorId: jugadorId,
      partidoIds: partidoIds,
    );

    return _mapFilasAPendientesNetos(
      rows.cast<Map<String, Object?>>(),
      snapshots,
      jugadorId: jugadorId,
    );
  }

  /// Jugadores con al menos un partido impago cuya fecha supera [diasMinimos].
  Future<List<ResumenJugador>> getDeudoresVencidos(int diasMinimos) async {
    final resumenes = await getResumenJugadores();
    final deudores = resumenes.where((r) => r.tieneDeuda).toList();
    if (deudores.isEmpty) return [];

    final db = await _db.database;
    final ids = deudores
        .map((r) => r.jugador.id)
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return [];

    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT dp.jugador_id, p.id AS partido_id, p.fecha, p.recinto, p.sport_type,
             dp.total, dp.monto_pagado
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id IN ($placeholders)
        AND dp.asistio = 1
      ORDER BY p.fecha ASC
    ''', ids);

    final partidoIds =
        rows.map((r) => r['partido_id'] as int).toSet();
    final snapshots = await _fetchSnapshotsPorPartidoJugadorLocal(
      db,
      partidoIds: partidoIds,
    );

    final pendientesPorJugador = <int, List<DeudaPartidoAnterior>>{
      for (final id in ids) id: [],
    };
    for (final r in rows) {
      final jid = r['jugador_id'] as int;
      final partidoId = r['partido_id'] as int;
      final key = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: partidoId,
        jugadorId: jid,
      );
      final pendiente = CobroLogic.pendienteNetoDetalle(
        partidoId: partidoId,
        jugadorId: jid,
        cargoPartido: (r['total'] as num).toDouble(),
        montoPagadoEnPartido: (r['monto_pagado'] as num?)?.toDouble() ?? 0,
        snapshotSaldoAnterior: snapshots[key],
      );
      if (pendiente <= 0.005) continue;
      pendientesPorJugador.putIfAbsent(jid, () => []).add(
            DeudaPartidoAnterior(
              partidoId: partidoId,
              fecha: DateTime.parse(r['fecha'] as String),
              recinto: r['recinto'] as String?,
              pendienteNeto: pendiente,
              sportType: SportType.fromDb(r['sport_type'] as String?),
            ),
          );
    }

    final ahora = DateTime.now();
    final vencidos = deudores.where((r) {
      final jid = r.jugador.id;
      if (jid == null) return false;
      final pendientes = pendientesPorJugador[jid] ?? [];
      return pendientes.any(
        (p) => ahora.difference(p.fecha).inDays >= diasMinimos,
      );
    }).toList();

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
      SELECT p.id AS partido_id, p.fecha, p.recinto, p.sport_type,
             dp.total, dp.monto_pagado
      FROM detalles_partido dp
      JOIN partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = ?
        AND dp.asistio = 1
        AND dp.partido_id != ?
      ORDER BY p.fecha ASC
    ''', [jugadorId, partidoActualId]);

    final partidoIds =
        rows.map((r) => r['partido_id'] as int).toSet();
    final snapshots = await _fetchSnapshotsPorPartidoJugadorLocal(
      db,
      jugadorId: jugadorId,
      partidoIds: partidoIds,
    );

    return _mapFilasAPendientesNetos(
      rows.cast<Map<String, Object?>>(),
      snapshots,
      jugadorId: jugadorId,
    );
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

    final historicos = await db.query(
      'saldos_historicos',
      where: 'partido_id = ?',
      whereArgs: [partidoId],
    );

    return PartidoCompleto(
      partido: Partido.fromMap(partidoRows.first),
      detalles: detalleRows.map(DetallePartido.fromMap).toList(),
      costosVariables: costos,
      asignacionesPorCosto: asignaciones,
      saldoAnteriorPorJugador: {
        for (final h in historicos)
          (h['jugador_id'] as int).toString():
              (h['saldo_anterior'] as num).toDouble(),
      },
    );
  }

  Future<List<PartidoCompleto>> getCompletosListaResumen(
    List<int> partidoIds,
  ) async {
    if (partidoIds.isEmpty) return [];
    final result = <PartidoCompleto>[];
    for (final id in partidoIds) {
      final completo = await getCompleto(id);
      if (completo != null) result.add(completo);
    }
    return result;
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

    for (final d in completo.detalles.where((d) => d.asistio)) {
      if (!saldosAnteriores.containsKey(d.jugadorId)) {
        throw DatosInconsistentesException(
          'Datos inconsistentes: falta snapshot saldo_anterior '
          '(jugador ${d.jugadorId}, partido $partidoId)',
        );
      }
    }

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
    if (jugadores.isEmpty) return [];

    final db = await _db.database;
    final detalleRows = await db.rawQuery('''
      SELECT jugador_id, partido_id, total, monto_pagado, asistio
      FROM detalles_partido
      WHERE asistio = 1
    ''');

    final partidoIds = detalleRows
        .map((r) => r['partido_id'] as int)
        .toSet();
    final snapshots = await _fetchSnapshotsPorPartidoJugadorLocal(
      db,
      partidoIds: partidoIds,
    );

    final ids = jugadores
        .map((j) => j.id)
        .whereType<int>()
        .map((id) => id.toString())
        .toList();
    final pendientePorJugador = CobroLogic.pendienteNetoPorJugadorBatch(
      jugadorIds: ids,
      detalleRows: detalleRows,
      snapshotsPorPartidoJugador: snapshots,
      jugadorIdDeFila: (map) => (map['jugador_id'] as int).toString(),
      partidoIdDeFila: (map) => map['partido_id'] as int,
    );

    final partidosPorJugador = <String, int>{};
    for (final row in detalleRows) {
      final jid = (row['jugador_id'] as int).toString();
      partidosPorJugador[jid] = (partidosPorJugador[jid] ?? 0) + 1;
    }

    final resumenes = jugadores.map((jugador) {
      final key = jugador.id?.toString() ?? '';
      return ResumenJugador(
        jugador: jugador,
        saldoActual: jugador.saldoAcumulado,
        partidosJugados: partidosPorJugador[key] ?? 0,
        totalPendiente: pendientePorJugador[key] ?? 0,
      );
    }).toList();

    resumenes.sort(
      (a, b) => b.deudaVisible.compareTo(a.deudaVisible),
    );
    return resumenes;
  }

  Future<PartidoCompleto?> getUltimoPartido() async {
    final partidos = await getJugados();
    if (partidos.isEmpty) return null;
    return getCompleto(partidos.first.id!);
  }

  Future<List<PartidoCompleto>> getPartidosJugadosRecientesResumen({
    int limit = 8,
  }) async {
    final partidos = await getJugados();
    if (partidos.isEmpty) return const [];
    final ids = partidos
        .take(limit)
        .map((p) => p.id)
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return const [];
    return getCompletosListaResumen(ids);
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
              String? iconKey,
            })>
        costosVariables,
  }) async {
    final db = await _db.database;
    final detalleRows = await db.query(
      'detalles_partido',
      columns: ['jugador_id'],
      where: 'partido_id = ?',
      whereArgs: [partidoId],
    );
    final jugadorIds = detalleRows
        .map((r) => r['jugador_id'] as int)
        .toSet();

    await db.delete(
      'saldos_historicos',
      where: 'partido_id = ?',
      whereArgs: [partidoId],
    );
    await db.delete('partidos', where: 'id = ?', whereArgs: [partidoId]);

    for (final jid in jugadorIds) {
      await _recalcularSaldoJugadorLocal(db, jid);
    }

    await guardarPartido(
      partido: partido,
      jugadoresAsistentes: jugadoresAsistentes,
      montoPagadoPorJugador: montoPagadoPorJugador,
      costosVariables: costosVariables,
    );
  }

  Future<void> eliminarPartido(int id) async {
    final db = await _db.database;
    final detalleRows = await db.query(
      'detalles_partido',
      columns: ['jugador_id'],
      where: 'partido_id = ?',
      whereArgs: [id],
    );
    final jugadorIds = detalleRows
        .map((r) => r['jugador_id'] as int)
        .toSet();

    await db.delete(
      'saldos_historicos',
      where: 'partido_id = ?',
      whereArgs: [id],
    );
    await db.delete('partidos', where: 'id = ?', whereArgs: [id]);

    for (final jid in jugadorIds) {
      await _recalcularSaldoJugadorLocal(db, jid);
    }
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
              String? iconKey,
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
          if (cv.iconKey != null) 'icon_key': cv.iconKey,
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
        final saldoAcumulado =
            (jugadorRows.first['saldo_acumulado'] as num).toDouble();

        await _insertarCargoJugador(
          txn: txn,
          partidoId: partidoId,
          jugadorId: jugadorId,
          partido: partido,
          prorrateo: prorrateo,
          totalVars: variablesPorJugador[jugadorId] ?? 0,
          montoOrganizador: montoPagadoPorJugador[jugadorId] ?? 0,
          saldosAnterioresSnapshot: saldosAnterioresSnapshot,
          saldoAcumuladoVivo: saldoAcumulado,
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
              String? iconKey,
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
          if (cv.iconKey != null) 'icon_key': cv.iconKey,
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
        final saldoAcumulado =
            (jugadorRows.first['saldo_acumulado'] as num).toDouble();

        await _insertarCargoJugador(
          txn: txn,
          partidoId: partidoId,
          jugadorId: jugadorId,
          partido: partido,
          prorrateo: prorrateo,
          totalVars: variablesPorJugador[jugadorId] ?? 0,
          montoOrganizador: montoPagadoPorJugador[jugadorId] ?? 0,
          saldosAnterioresSnapshot: saldosAnterioresSnapshot,
          saldoAcumuladoVivo: saldoAcumulado,
        );
      }
    });
  }

  /// Reparación manual: alinea detalles con bruto (no usar en flujo normal).
  @Deprecated('Solo reparación manual; usar _aplicarPagoEnDetallesImpagos en pagos')
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

  /// Reparación manual fuera del flujo normal.
  @Deprecated('Solo reparación manual; no usar en flujo normal')
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
      final rows = await db.rawQuery('''
        SELECT dp.id, dp.total, dp.monto_pagado
        FROM detalles_partido dp
        JOIN partidos p ON p.id = dp.partido_id
        WHERE dp.jugador_id = ? AND dp.asistio = 1 AND dp.pagado = 0
        ORDER BY p.fecha ASC, dp.id ASC
      ''', [jugadorId]);

      if (rows.isEmpty) return;

      var saldoActual = saldo;
      final ahoraIso = ahora.toIso8601String();
      for (final row in rows) {
        final id = row['id'] as int;
        final total = (row['total'] as num).toDouble();
        final montoPagado =
            (row['monto_pagado'] as num?)?.toDouble() ?? 0;
        final pago = CobroLogic.estadoPagoPartido(
          saldoAnterior: saldoActual,
          cargo: total,
          montoPagadoOrganizador: montoPagado,
        );
        if (!pago.pagado) continue;

        await db.update(
          'detalles_partido',
          {
            'pagado': 1,
            'fecha_pago': ahoraIso,
            'monto_pagado': pago.montoPagado,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        saldoActual = pago.saldoNuevo;
      }

      if ((saldoActual - saldo).abs() > 0.005) {
        await db.update(
          'jugadores',
          {'saldo_acumulado': saldoActual},
          where: 'id = ?',
          whereArgs: [jugadorId],
        );
      }
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
    final saldoNuevo = CobroLogic.saldoTrasPago(
      saldoAcumulado: saldoAnterior,
      montoPagado: monto,
    );
    final ahora = DateTime.now();

    final db = await _db.database;
    await db.transaction((txn) async {
      await _aplicarPagoEnDetallesImpagos(
        db: txn,
        jugadorId: jugadorId,
        monto: monto,
        fecha: ahora,
      );

      await txn.insert('saldos_historicos', {
        'jugador_id': jugadorId,
        'saldo_anterior': saldoAnterior,
        'cargo_partido': 0,
        'abono': monto,
        'saldo_nuevo': saldoNuevo,
        'fecha': ahora.toIso8601String(),
        'concepto': concepto,
      });

      await txn.update(
        'jugadores',
        {'saldo_acumulado': saldoNuevo},
        where: 'id = ?',
        whereArgs: [jugadorId],
      );
    });
  }

  Future<int> delete(int id) async {
    await eliminarPartido(id);
    return 1;
  }
}
