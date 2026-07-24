import 'dart:async';

import '../constants/conceptos_cobro.dart';
import '../domain/cobro_logic.dart';
import '../domain/organizer_cycle_logic.dart';
import '../core/supabase_helpers.dart';
import '../core/supabase_parse.dart';
import '../core/sport_type.dart';
import '../models/comprobante_estado.dart';
import '../models/comprobante_pago.dart';
import '../models/costo_variable.dart';
import '../models/cobros_resumen.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/gasto_por_concepto.dart';
import '../models/estado_partido.dart';
import '../models/partido.dart';
import '../models/jugador.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/datos_pago_organizador.dart';
import '../repositories/repository_types.dart';
import '../repositories/jugador_repository_remote.dart';
import '../repositories/partido_repository.dart';
import '../services/calculation_service.dart';
import '../services/cobro_notificacion_service.dart';
import '../services/supabase_realtime_service.dart';
import '../services/comprobante_service.dart';
import '../services/supabase_storage_service.dart';
import '../utils/comprobante_path.dart';
import '../utils/formatters.dart';

/// Partidos y cobros contra Supabase.
class PartidoRepositoryRemote {
  final _client = SupabaseHelpers.client;
  final _jugadorRepo = JugadorRepositoryRemote();
  final _cobroNotificaciones = CobroNotificacionService();

  /// Sube comprobantes de gasto locales a Storage; deja paths cloud intactos.
  Future<({Partido partido, List<CostoVariableInput> costos})>
      _sincronizarComprobantesGastos({
    required Partido partido,
    required List<CostoVariableInput> costosVariables,
    int? partidoId,
  }) async {
    final uid = SupabaseHelpers.currentUserId;
    if (uid == null) {
      return (partido: partido, costos: costosVariables);
    }

    final cancha = await ComprobanteService.instance.ensureCloudPath(
      path: partido.comprobanteCancha,
      userId: uid,
      partidoId: partidoId,
    );
    final pelotas = await ComprobanteService.instance.ensureCloudPath(
      path: partido.comprobantePelotas,
      userId: uid,
      partidoId: partidoId,
    );

    final costos = <CostoVariableInput>[];
    for (final cv in costosVariables) {
      final path = await ComprobanteService.instance.ensureCloudPath(
        path: cv.comprobanteUrl ?? cv.comprobantePath,
        userId: uid,
        partidoId: partidoId,
      );
      costos.add((
        concepto: cv.concepto,
        montoTotal: cv.montoTotal,
        jugadores: cv.jugadores,
        comprobantePath: path,
        comprobanteUrl: path,
        iconKey: cv.iconKey,
      ));
    }

    return (
      partido: partido.copyWith(
        comprobanteCancha: cancha,
        comprobantePelotas: pelotas,
      ),
      costos: costos,
    );
  }

  /// Perfil con login si el organizador cobra a un pre-registro (mismo email).
  Future<String> _resolveJugadorIdForCobro(String jugadorId) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('email, telefono')
          .eq('id', jugadorId)
          .maybeSingle();
      if (profile == null) return jugadorId;

      final map = Map<String, dynamic>.from(profile);
      final email = SupabaseParse.toStringOrNull(map['email']) ??
          SupabaseParse.toStringOrNull(map['telefono']);
      if (email == null || !email.contains('@')) return jugadorId;

      final resolved = await _client.rpc(
        'resolve_profile_id_for_email',
        params: {'p_email': email},
      );
      final id = resolved?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {
      // RPC no desplegado: usar id original.
    }
    return jugadorId;
  }

  Future<Map<String, String>> _resolverIdsCobro(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    final entries = await Future.wait(
      unique.map((id) async => MapEntry(id, await _resolveJugadorIdForCobro(id))),
    );
    return Map.fromEntries(entries);
  }

  Future<Map<String, Jugador>> _fetchJugadoresPorIds(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', unique);
    final saldosCuenta = await _fetchSaldosCuentaBatch(unique);
    final map = <String, Jugador>{};
    for (final row in rows as List) {
      final jugador = Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
      final id = jugador.supabaseId;
      if (id == null || id.isEmpty) continue;
      map[id] = jugador.copyWith(
        saldoAcumulado: saldosCuenta[id] ?? 0,
      );
    }
    return map;
  }

  /// Calcula estado de pago al guardar/completar partido (efectivo + saldo a favor).
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

  /// Primer snapshot de cargo (`cargo_partido > 0`) por partido+jugador.
  Future<Map<String, double>> _fetchSnapshotsSaldoAnteriorCobroBatch({
    Iterable<int>? partidoIds,
    Iterable<String>? jugadorIds,
  }) async {
    if (partidoIds != null && partidoIds.isEmpty) return {};

    var query = _client
        .from('saldos_historicos')
        .select('partido_id, jugador_id, saldo_anterior, fecha, id')
        .gt('cargo_partido', 0);
    if (partidoIds != null) {
      query = query.inFilter('partido_id', partidoIds.toList());
    }
    if (jugadorIds != null && jugadorIds.isNotEmpty) {
      query = query.inFilter('jugador_id', jugadorIds.toList());
    }

    final rows = await query
        .order('fecha', ascending: true)
        .order('id', ascending: true);

    final map = <String, double>{};
    for (final row in rows as List) {
      final pid = SupabaseParse.toInt(row['partido_id']);
      final jid = row['jugador_id']?.toString();
      if (jid == null || pid <= 0) continue;
      final key = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: pid,
        jugadorId: jid,
      );
      map.putIfAbsent(
        key,
        () => SupabaseParse.toDouble(row['saldo_anterior']),
      );
    }
    return map;
  }

  /// Saldos vivos de cuentas con el organizador autenticado
  /// (`organizador_jugadores.saldo_acumulado`).
  Future<Map<String, double>> _fetchSaldosCuentaBatch(
    Iterable<String> jugadorIds, {
    String? organizadorId,
  }) async {
    final ids = jugadorIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
    if (orgId == null) return {};

    final rows = await _client
        .from('organizador_jugadores')
        .select('jugador_id, saldo_acumulado')
        .eq('organizador_id', orgId)
        .inFilter('jugador_id', ids);

    final map = <String, double>{};
    for (final row in rows as List) {
      final id = row['jugador_id']?.toString();
      if (id == null || id.isEmpty) continue;
      map[id] = SupabaseParse.toDouble(row['saldo_acumulado']);
    }
    return map;
  }

  String? get _organizadorIdActual => SupabaseHelpers.currentUserId;

  /// Snapshot inmutable al registrar el cargo. Error si falta en partido existente.
  Future<double> _requerirSaldoAnteriorSnapshot({
    required String jugadorId,
    required int partidoId,
  }) async {
    final histRow = await _client
        .from('saldos_historicos')
        .select('saldo_anterior')
        .eq('partido_id', partidoId)
        .eq('jugador_id', jugadorId)
        .gt('cargo_partido', 0)
        .order('fecha', ascending: true)
        .order('id', ascending: true)
        .limit(1)
        .maybeSingle();
    if (histRow == null) {
      throw DatosInconsistentesException(
        'Datos inconsistentes: falta snapshot saldo_anterior '
        '(jugador $jugadorId, partido $partidoId)',
      );
    }
    return CobroLogic.saldoAnteriorAlPartido(
      snapshotHistorico:
          SupabaseParse.toDouble(histRow['saldo_anterior']),
    );
  }

  /// Snapshot para validaciones; null si no hay cargo registrado.
  Future<double?> _snapshotSaldoAnteriorOpcional({
    required String jugadorId,
    required int partidoId,
  }) async {
    final histRow = await _client
        .from('saldos_historicos')
        .select('saldo_anterior')
        .eq('partido_id', partidoId)
        .eq('jugador_id', jugadorId)
        .gt('cargo_partido', 0)
        .order('fecha', ascending: true)
        .order('id', ascending: true)
        .limit(1)
        .maybeSingle();
    if (histRow == null) return null;
    return CobroLogic.saldoAnteriorAlPartido(
      snapshotHistorico:
          SupabaseParse.toDouble(histRow['saldo_anterior']),
    );
  }

  /// Saldo al registrar un cargo nuevo: snapshot del formulario o saldo vivo actual.
  double _saldoAnteriorAlRegistrarCargo({
    required Jugador jugador,
    Map<String, double>? saldosAnterioresSnapshot,
    required String rawId,
    required String jugadorId,
  }) {
    final snap = saldosAnterioresSnapshot?[rawId] ??
        saldosAnterioresSnapshot?[jugadorId];
    if (snap != null) return roundMoney(snap).toDouble();
    return roundMoney(jugador.saldoAcumulado).toDouble();
  }

  /// Si el saldo de la cuenta con este org es menor que la suma de pendientes
  /// en detalles de ESTE org, reparte la diferencia en detalles.
  Future<bool> _sincronizarDetallesConSaldoPerfil(String jugadorId) async {
    final orgId = _organizadorIdActual;
    if (orgId == null) return false;

    final saldoCuenta = roundMoney(
      await _jugadorRepo.getSaldoCuenta(
        organizadorId: orgId,
        jugadorId: jugadorId,
      ),
    ).toDouble();
    if (saldoCuenta < -0.005) return false;

    final rows = await _client
        .from('detalles_partido')
        .select(
          'partido_id, total, monto_pagado, '
          'partidos!inner(organizador_id)',
        )
        .eq('jugador_id', jugadorId)
        .eq('asistio', true)
        .eq('partidos.organizador_id', orgId);
    if ((rows as List).isEmpty) return false;

    final partidoIds = <int>{};
    for (final row in rows) {
      partidoIds.add(SupabaseParse.toInt(row['partido_id']));
    }
    final snapshots = await _fetchSnapshotsSaldoAnteriorCobroBatch(
      partidoIds: partidoIds,
      jugadorIds: [jugadorId],
    );

    var sumPendiente = 0.0;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      final partidoId = SupabaseParse.toInt(map['partido_id']);
      final key = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: partidoId,
        jugadorId: jugadorId,
      );
      final saldoAnt = CobroLogic.saldoAnteriorAlPartido(
        snapshotHistorico: snapshots[key] ?? 0,
      );
      sumPendiente += CobroLogic.obtenerPendientePartido(
        saldoAnteriorAlPartido: saldoAnt,
        cargoPartido: SupabaseParse.toDouble(map['total']),
        montoPagadoEnPartido: SupabaseParse.toDouble(map['monto_pagado']),
      );
    }
    sumPendiente = roundMoney(sumPendiente).toDouble();

    final exceso = roundMoney(sumPendiente - saldoCuenta).toDouble();
    if (exceso <= 0.005) return false;

    await _aplicarPagoEnDetallesImpagos(
      jugadorId: jugadorId,
      monto: exceso,
      fecha: DateTime.now(),
    );
    return true;
  }

  /// Aplica un pago sobre detalles con deuda neta pendiente (FIFO por fecha).
  /// Solo toca partidos del organizador autenticado.
  Future<void> _aplicarPagoEnDetallesImpagos({
    required String jugadorId,
    required double monto,
    required DateTime fecha,
  }) async {
    if (monto <= 0.005) return;
    final orgId = _organizadorIdActual;

    var query = _client
        .from('detalles_partido')
        .select(
          'id, total, monto_pagado, partido_id, '
          'partidos!inner(fecha, organizador_id)',
        )
        .eq('jugador_id', jugadorId)
        .eq('asistio', true);
    if (orgId != null) {
      query = query.eq('partidos.organizador_id', orgId);
    }
    final rows = await query;

    final sorted = (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final partido = SupabaseParse.mapEmbed(map['partidos']);
      return (
        id: (map['id'] as num).toInt(),
        partidoId: SupabaseParse.toInt(map['partido_id']),
        total: SupabaseParse.toDouble(map['total']),
        yaPagado: SupabaseParse.toDouble(map['monto_pagado']),
        fecha: partido == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : SupabaseParse.toDateTime(partido['fecha']),
      );
    }).toList()
      ..sort((a, b) {
        final cmp = a.fecha.compareTo(b.fecha);
        if (cmp != 0) return cmp;
        return a.partidoId.compareTo(b.partidoId);
      });

    final snapshots = await _fetchSnapshotsSaldoAnteriorCobroBatch(
      partidoIds: sorted.map((r) => r.partidoId).toSet(),
      jugadorIds: [jugadorId],
    );

    var restante = roundMoney(monto).toDouble();
    for (final row in sorted) {
      if (restante <= 0.005) break;

      final snapKey = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: row.partidoId,
        jugadorId: jugadorId,
      );
      final saldoAnt = CobroLogic.saldoAnteriorAlPartido(
        snapshotHistorico: snapshots[snapKey] ?? 0,
      );
      // FIFO: no recontar deuda anterior (ya está en partidos más viejos).
      final pendiente = CobroLogic.pendienteFifoDetalle(
        saldoAnterior: saldoAnt,
        cargoPartido: row.total,
        montoPagadoEnPartido: row.yaPagado,
      );

      if (pendiente <= 0.005) {
        await _client.from('detalles_partido').update({
          'pagado': true,
          'fecha_pago': fecha.toIso8601String(),
          'comprobante_validado': true,
          'comprobante_url': null,
          'monto_pago_declarado': null,
          'pago_es_abono': null,
        }).eq('id', row.id);
        continue;
      }

      final aplicar =
          restante >= pendiente ? pendiente : restante;
      final nuevoMonto = roundMoney(row.yaPagado + aplicar).toDouble();
      final cubierto = CobroLogic.partidoCubiertoFifo(
        saldoAnterior: saldoAnt,
        cargoPartido: row.total,
        montoPagadoEnPartido: nuevoMonto,
      );

      await _client.from('detalles_partido').update({
        'monto_pagado': nuevoMonto,
        'pagado': cubierto,
        'fecha_pago': fecha.toIso8601String(),
        if (cubierto) 'comprobante_validado': true,
        if (cubierto) 'comprobante_url': null,
        if (cubierto) 'monto_pago_declarado': null,
        if (cubierto) 'pago_es_abono': null,
      }).eq('id', row.id);

      restante = roundMoney(restante - aplicar).toDouble();
    }
  }

  Future<void> _prepararReemplazoPartido(int partidoId) async {
    try {
      await _client.rpc(
        'preparar_reemplazo_partido',
        params: {'p_partido_id': partidoId},
      );
      return;
    } catch (_) {
      // RPC no desplegado: fallback manual.
    }

    final detalleRows = await _client
        .from('detalles_partido')
        .select('jugador_id')
        .eq('partido_id', partidoId);

    final jugadorIds = (detalleRows as List)
        .map((row) => row['jugador_id']?.toString())
        .whereType<String>()
        .toSet();

    await _client.from('saldos_historicos').delete().eq('partido_id', partidoId);
    await _client.from('detalles_partido').delete().eq('partido_id', partidoId);
    await _client.from('costos_variables').delete().eq('partido_id', partidoId);

    if (jugadorIds.isNotEmpty) {
      await _jugadorRepo.recalcularSaldosBatch(jugadorIds.toList());
    }
  }

  Future<void> _insertarCostosYDetalles({
    required int partidoId,
    required Partido partido,
    required Map<String, String> idMap,
    required List<String> jugadoresAsistentes,
    required List<String> asistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
    required double prorrateo,
  }) async {
    final variablesPorJugador = <String, double>{
      for (final id in asistentes) id: 0,
    };

    for (final cv in costosVariables) {
      final costoRow = await _client
          .from('costos_variables')
          .insert({
            'partido_id': partidoId,
            'concepto': cv.concepto,
            'monto_total': cv.montoTotal,
            'comprobante_url': cv.comprobanteUrl ?? cv.comprobantePath,
            if (cv.iconKey != null) 'icon_key': cv.iconKey,
          })
          .select('id')
          .single();
      final costoId = (costoRow['id'] as num).toInt();

      final rawParticipantes = cv.jugadores.isEmpty
          ? jugadoresAsistentes.toSet()
          : cv.jugadores.toSet();
      final participantes = rawParticipantes
          .map((id) => idMap[id] ?? id)
          .toSet()
          .toList();
      final montoIndividual = participantes.isEmpty
          ? 0.0
          : CalculationService.prorratear(cv.montoTotal, participantes.length);

      if (participantes.isNotEmpty) {
        await _client.from('asignaciones_costo').insert([
          for (final jugadorId in participantes)
            {
              'costo_variable_id': costoId,
              'jugador_id': jugadorId,
              'monto': montoIndividual,
            },
        ]);
        for (final jugadorId in participantes) {
          variablesPorJugador[jugadorId] =
              (variablesPorJugador[jugadorId] ?? 0) + montoIndividual;
        }
      }
    }

    final jugadoresPorId = await _fetchJugadoresPorIds(asistentes);
    final ahora = DateTime.now();
    final detallesRows = <Map<String, dynamic>>[];
    final historialRows = <Map<String, dynamic>>[];
    final jugadorIdsConCargo = <String>[];

    for (final jugadorId in asistentes) {
      final jugador = jugadoresPorId[jugadorId];
      if (jugador == null) continue;

      final rawId = idMap.entries
          .firstWhere(
            (e) => e.value == jugadorId,
            orElse: () => MapEntry(jugadorId, jugadorId),
          )
          .key;
      final saldoAnterior = _saldoAnteriorAlRegistrarCargo(
        jugador: jugador,
        saldosAnterioresSnapshot: saldosAnterioresSnapshot,
        rawId: rawId,
        jugadorId: jugadorId,
      );
      final totalVars = variablesPorJugador[jugadorId] ?? 0;
      final cargo = CalculationService.cargoPartido(
        prorrateoFijo: prorrateo,
        totalVariables: totalVars,
      );
      final montoOrganizador = montoPagadoPorJugador[rawId] ??
          montoPagadoPorJugador[jugadorId] ??
          0;
      final pago = _estadoPagoPartido(
        saldoAnterior: saldoAnterior,
        cargo: cargo,
        montoPagadoOrganizador: montoOrganizador,
      );
      final montoPagado = pago.montoPagado;
      final saldoNuevo = pago.saldoNuevo;
      final pagado = pago.pagado;
      final concepto = pago.concepto;

      detallesRows.add({
        'partido_id': partidoId,
        'jugador_id': jugadorId,
        'asistio': true,
        'prorrateo_fijo': prorrateo,
        'total_variables': totalVars,
        'total': cargo,
        'pagado': pagado,
        'monto_pagado': montoPagado,
        if (pagado || montoPagado > 0)
          'fecha_pago': ahora.toIso8601String(),
      });

      historialRows.add({
        'jugador_id': jugadorId,
        'partido_id': partidoId,
        'organizador_id': _organizadorIdActual,
        'saldo_anterior': saldoAnterior,
        'cargo_partido': cargo,
        'abono': montoPagado,
        'saldo_nuevo': saldoNuevo,
        // Siempre "ahora": si usamos fecha del partido, un cargo cubierto con
        // saldo a favor queda detrás del abono en ORDER BY fecha y el crédito
        // no se descuenta al recalcular.
        'fecha': ahora.toIso8601String(),
        'concepto': concepto,
      });
      jugadorIdsConCargo.add(jugadorId);
    }

    // 3 round-trips en total (antes: 3 × N). Evita el “parpadeo” del Home
    // a medias mientras Realtime ve inserts parciales.
    if (detallesRows.isNotEmpty) {
      await _client.from('detalles_partido').insert(detallesRows);
    }
    if (historialRows.isNotEmpty) {
      await _client.from('saldos_historicos').insert(historialRows);
    }
    if (jugadorIdsConCargo.isNotEmpty) {
      await _jugadorRepo.recalcularSaldosBatch(jugadorIdsConCargo);
    }
  }

  Future<List<Partido>> getAll({EstadoPartido? soloEstado, int? limit}) async {
    return SupabaseHelpers.guard('Listar encuentros', () async {
      final uid = SupabaseHelpers.currentUserId;
      var query = _client.from('partidos').select();
      if (uid != null) {
        query = query.eq('organizador_id', uid);
      }
      if (soloEstado != null) {
        query = query.eq('estado', soloEstado.dbValue);
      }
      final ordered = query.order('fecha', ascending: false);
      final rows = limit != null
          ? await ordered.limit(limit)
          : await ordered;
      return (rows as List)
          .map((r) => Partido.fromSupabaseMap(Map<String, dynamic>.from(r)))
          .toList();
    });
  }

  Future<List<Partido>> getJugados({int? limit}) =>
      getAll(soloEstado: EstadoPartido.jugado, limit: limit);

  Future<List<String>> getRecintosRecientes({int limit = 8}) async {
    return SupabaseHelpers.guard('Recintos recientes', () async {
      final uid = SupabaseHelpers.currentUserId;
      var query = _client
          .from('partidos')
          .select('recinto, fecha')
          .not('recinto', 'is', null);
      if (uid != null) {
        query = query.eq('organizador_id', uid);
      }
      final rows = await query
          .order('fecha', ascending: false)
          .limit(limit * 3);

      final vistos = <String>{};
      final result = <String>[];
      for (final row in rows as List) {
        final r = (row['recinto'] as String?)?.trim() ?? '';
        if (r.isEmpty || vistos.contains(r)) continue;
        vistos.add(r);
        result.add(r);
        if (result.length >= limit) break;
      }
      return result;
    });
  }

  Future<PartidoCompleto?> getCompleto(int partidoId) async {
    return SupabaseHelpers.guard('Obtener encuentro completo', () async {
      final partidoRow = await _client
          .from('partidos')
          .select()
          .eq('id', partidoId)
          .maybeSingle();
      if (partidoRow == null) return null;

      final detalleRows = await _client
          .from('detalles_partido')
          .select('*, profiles:jugador_id(nombre)')
          .eq('partido_id', partidoId);

      final detalles = (detalleRows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final profile = map['profiles'] as Map?;
        return DetallePartido.fromSupabaseMap(
          map,
          nombreJugador: profile?['nombre'] as String?,
        );
      }).toList()
        ..sort(
          (a, b) => (a.nombreJugador ?? '').toLowerCase().compareTo(
                (b.nombreJugador ?? '').toLowerCase(),
              ),
        );

      final costoRows = await _client
          .from('costos_variables')
          .select()
          .eq('partido_id', partidoId);

      final costos = (costoRows as List)
          .map((r) => CostoVariable.fromSupabaseMap(Map<String, dynamic>.from(r)))
          .toList();

      final asignaciones = <int, List<AsignacionCostoVariable>>{};
      final costoIds = costos.map((c) => c.id).whereType<int>().toList();
      if (costoIds.isNotEmpty) {
        final asigRows = await _client
            .from('asignaciones_costo')
            .select()
            .inFilter('costo_variable_id', costoIds);
        for (final costo in costos) {
          asignaciones[costo.id!] = (asigRows as List)
              .where(
                (r) => SupabaseParse.toInt(r['costo_variable_id']) == costo.id,
              )
              .map(
                (r) => AsignacionCostoVariable.fromSupabaseMap(
                  Map<String, dynamic>.from(r),
                ),
              )
              .toList();
        }
      }

      final jugadorIds = detalles
          .map((d) => d.jugadorKeyId)
          .where((id) => id.isNotEmpty)
          .toSet();
      final histRows = await _fetchSnapshotsSaldoAnteriorCobroBatch(
        partidoIds: [partidoId],
      );
      final saldoAnterior = <String, double>{};
      for (final entry in histRows.entries) {
        final parts = entry.key.split(':');
        if (parts.length != 2) continue;
        if (int.tryParse(parts[0]) != partidoId) continue;
        if (parts[1].isEmpty) continue;
        saldoAnterior[parts[1]] = entry.value;
      }
      final saldosCuenta = await _fetchSaldosCuentaBatch(jugadorIds);

      return PartidoCompleto(
        partido: Partido.fromSupabaseMap(Map<String, dynamic>.from(partidoRow)),
        detalles: detalles,
        costosVariables: costos,
        asignacionesPorCosto: asignaciones,
        saldoAnteriorPorJugador: saldoAnterior,
        saldoCuentaPorJugador: saldosCuenta,
      );
    });
  }

  /// Lista ligera para historial: partido + detalles en 2 consultas (sin costos).
  Future<List<PartidoCompleto>> getCompletosListaResumen(
    List<int> partidoIds,
  ) async {
    if (partidoIds.isEmpty) return [];
    return SupabaseHelpers.guard('Listar encuentros (resumen)', () async {
      final partidoRows = await _client
          .from('partidos')
          .select()
          .inFilter('id', partidoIds);

      final detalleRows = await _client
          .from('detalles_partido')
          .select('*, profiles:jugador_id(nombre)')
          .inFilter('partido_id', partidoIds);

      final histRows = await _fetchSnapshotsSaldoAnteriorCobroBatch(
        partidoIds: partidoIds,
      );

      final saldosPorPartido = <int, Map<String, double>>{};
      for (final entry in histRows.entries) {
        final parts = entry.key.split(':');
        if (parts.length != 2) continue;
        final pid = int.tryParse(parts[0]);
        final jid = parts[1];
        if (pid == null || jid.isEmpty) continue;
        saldosPorPartido.putIfAbsent(pid, () => {})[jid] = entry.value;
      }

      final partidoMap = <int, Partido>{
        for (final row in partidoRows as List)
          SupabaseParse.toInt(row['id']): Partido.fromSupabaseMap(
            Map<String, dynamic>.from(row),
          ),
      };

      final detallesPorPartido = <int, List<DetallePartido>>{};
      final jugadorIds = <String>{};
      for (final row in detalleRows as List) {
        final map = Map<String, dynamic>.from(row);
        final pid = SupabaseParse.toInt(map['partido_id']);
        final profile = map['profiles'] as Map?;
        final detalle = DetallePartido.fromSupabaseMap(
          map,
          nombreJugador: profile?['nombre'] as String?,
        );
        detallesPorPartido.putIfAbsent(pid, () => []).add(detalle);
        final jid = detalle.jugadorKeyId;
        if (jid.isNotEmpty) jugadorIds.add(jid);
      }

      final saldosCuenta = await _fetchSaldosCuentaBatch(jugadorIds);

      final result = <PartidoCompleto>[];
      for (final id in partidoIds) {
        final partido = partidoMap[id];
        if (partido == null) continue;
        final detalles = detallesPorPartido[id] ?? [];
        detalles.sort(
          (a, b) => (a.nombreJugador ?? '').toLowerCase().compareTo(
                (b.nombreJugador ?? '').toLowerCase(),
              ),
        );
        final saldosCuentaPartido = <String, double>{
          for (final d in detalles)
            if (d.jugadorKeyId.isNotEmpty &&
                saldosCuenta.containsKey(d.jugadorKeyId))
              d.jugadorKeyId: saldosCuenta[d.jugadorKeyId]!,
        };
        result.add(PartidoCompleto(
          partido: partido,
          detalles: detalles,
          saldoAnteriorPorJugador: saldosPorPartido[id] ?? const {},
          saldoCuentaPorJugador: saldosCuentaPartido,
        ));
      }
      return result;
    });
  }

  /// Lectura de desglose.
  ///
  /// [repararCuenta] es costoso (N round-trips); solo úsalo en flujos de
  /// reparación explícita, nunca al abrir historial/detalle.
  Future<List<DesgloseJugador>> getDesglose(
    int partidoId, {
    bool reconciliar = false,
    bool repararCuenta = false,
    PartidoCompleto? completo,
  }) async {
    if (reconciliar) {
      throw UnsupportedError(
        'reconciliar en getDesglose ya no está soportado; use reparar manual',
      );
    }
    var loaded = completo ?? await getCompleto(partidoId);
    if (loaded == null) return [];

    final asistentes =
        loaded.detalles.where((d) => d.asistio && d.jugadorSupabaseId != null);
    final asistenteIds = asistentes.map((d) => d.jugadorSupabaseId!).toSet();

    if (repararCuenta) {
      var sincronizado = false;
      for (final jid in asistenteIds) {
        if (await _sincronizarDetallesConSaldoPerfil(jid)) {
          sincronizado = true;
        }
      }
      if (sincronizado) {
        loaded = await getCompleto(partidoId) ?? loaded;
      }
    }

    final snapshots = await _fetchSnapshotsSaldoAnteriorCobroBatch(
      partidoIds: [partidoId],
    );

    final asistentesFinal =
        loaded.detalles.where((d) => d.asistio && d.jugadorSupabaseId != null);
    final asistenteIdsFinal =
        asistentesFinal.map((d) => d.jugadorSupabaseId!).toSet();

    final varsPorJugador = <String, Map<String, double>>{};
    for (final d in asistentesFinal) {
      varsPorJugador[d.jugadorSupabaseId!] = {};
    }

    for (final cv in loaded.costosVariables) {
      final asignaciones = loaded.asignacionesPorCosto[cv.id] ?? [];
      for (final a in asignaciones) {
        final jid = a.jugadorSupabaseId;
        if (jid != null && varsPorJugador.containsKey(jid)) {
          varsPorJugador[jid]![cv.concepto] = roundMoney(a.monto).toDouble();
        }
      }
    }

    final costoCancha = loaded.partido.costoCancha;
    final costoPelotas = loaded.partido.costoPelotas;
    final totalFijo = costoCancha + costoPelotas;

    final saldosCuenta = await _fetchSaldosCuentaBatch(asistenteIdsFinal);

    final desgloses = <DesgloseJugador>[];
    for (final d in asistentesFinal) {
      final jid = d.jugadorSupabaseId!;
      final snapKey = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: partidoId,
        jugadorId: jid,
      );
      if (!snapshots.containsKey(snapKey)) {
        // Datos legacy/demo sin ledger: no tumbar la pantalla; asumir 0.
        // Flujos de reparación / diagnóstico siguen pudiendo exigir snapshot.
      }
      final saldoAnt = CobroLogic.saldoAnteriorAlPartido(
        snapshotHistorico: snapshots[snapKey],
      );
      final pf = roundMoney(d.prorrateoFijo).toDouble();
      var cancha = 0.0;
      var pelotas = 0.0;
      if (totalFijo > 0 && pf > 0) {
        cancha = pf * (costoCancha / totalFijo);
        pelotas = pf * (costoPelotas / totalFijo);
      } else if (pf > 0) {
        cancha = pf;
      }
      final vars = varsPorJugador[jid] ?? {};
      final totalPartido = roundMoney(d.total).toDouble();
      final totalDebido = CalculationService.totalDebido(
        saldoAnterior: saldoAnt,
        cargoPartido: totalPartido,
      );
      final montoPagado = roundMoney(d.montoPagado).toDouble();
      final saldoRestante = CalculationService.saldoDespuesPago(
        saldoAnterior: saldoAnt,
        cargoPartido: totalPartido,
        montoPagado: montoPagado,
      );

      desgloses.add(
        DesgloseJugador(
          jugadorSupabaseId: jid,
          nombre: d.nombreJugador ?? '',
          saldoAnterior: roundMoney(saldoAnt).toDouble(),
          cancha: roundMoney(cancha).toDouble(),
          pelotas: roundMoney(pelotas).toDouble(),
          variables: vars,
          totalPartido: totalPartido,
          totalDebido: roundMoney(totalDebido).toDouble(),
          montoPagado: montoPagado,
          saldoRestante: roundMoney(saldoRestante).toDouble(),
          pagado: d.pagado,
          saldoAcumuladoCuenta: saldosCuenta[jid],
        ),
      );
    }
    return desgloses;
  }

  /// Pendiente real por jugador (neto con snapshot del partido).
  Map<String, double> _pendienteRealPorJugadorBatch(
    List<String> jugadorIds,
    List<dynamic> rows,
    Map<String, double> saldosAnteriores,
  ) =>
      CobroLogic.pendienteNetoPorJugadorBatch(
        jugadorIds: jugadorIds,
        detalleRows: rows,
        snapshotsPorPartidoJugador: saldosAnteriores,
        jugadorIdDeFila: (map) => map['jugador_id']?.toString() ?? '',
        partidoIdDeFila: (map) => SupabaseParse.toInt(map['partido_id']),
      );

  Future<Map<String, double>> _fetchSaldosAnterioresDetalles(
    List<dynamic> rows,
  ) async {
    final partidoIds = <int>{};
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      partidoIds.add(SupabaseParse.toInt(map['partido_id']));
    }
    if (partidoIds.isEmpty) return {};
    return _fetchSnapshotsSaldoAnteriorCobroBatch(partidoIds: partidoIds);
  }

  Future<List<ResumenJugador>> getResumenJugadores({bool reconciliar = false}) async {
    // Roster + saldo de ESTE organizador (getAll → oj.saldo_acumulado).
    final jugadores = await _jugadorRepo.getAll(incluirUsuarioActual: true);
    final ids = jugadores
        .map((j) => j.supabaseId)
        .whereType<String>()
        .toList(growable: false);
    if (ids.isEmpty) return [];

    if (reconciliar) {
      throw UnsupportedError(
        'reconciliar en getResumenJugadores ya no está soportado; use reparar manual',
      );
    }

    final orgId = _organizadorIdActual;
    var statsQuery = _client
        .from('detalles_partido')
        .select(
          'jugador_id, partido_id, total, monto_pagado, pagado, asistio, '
          'comprobante_url, comprobante_validado, monto_pago_declarado, '
          'partidos!inner(fecha, organizador_id)',
        )
        .inFilter('jugador_id', ids)
        .eq('asistio', true);
    // Solo partidos de ESTE organizador (no mezclar cuentas de otros orgs).
    if (orgId != null) {
      statsQuery = statsQuery.eq('partidos.organizador_id', orgId);
    }
    final statsRows = await statsQuery;

    final saldosAnteriores =
        await _fetchSaldosAnterioresDetalles(statsRows as List);
    final pendienteReal =
        _pendienteRealPorJugadorBatch(ids, statsRows, saldosAnteriores);

    final statsPorJugador = <String, ({int partidos, double pendiente})>{};
    for (final id in ids) {
      statsPorJugador[id] = (partidos: 0, pendiente: pendienteReal[id] ?? 0);
    }
    for (final row in statsRows as List) {
      final jid = row['jugador_id']?.toString();
      if (jid == null || !statsPorJugador.containsKey(jid)) continue;
      final prev = statsPorJugador[jid]!;
      statsPorJugador[jid] = (
        partidos: prev.partidos + 1,
        pendiente: prev.pendiente,
      );
    }

    final resumenes = <ResumenJugador>[];
    for (final jugador in jugadores) {
      final jid = jugador.supabaseId;
      if (jid == null) continue;
      final stats = statsPorJugador[jid] ?? (partidos: 0, pendiente: 0.0);
      // SSOT: saldo de la cuenta con este org (ya viene en jugador).
      resumenes.add(ResumenJugador(
        jugador: jugador,
        saldoActual: jugador.saldoAcumulado,
        partidosJugados: stats.partidos,
        totalPendiente: roundMoney(stats.pendiente).toDouble(),
      ));
    }

    resumenes.sort((a, b) => b.deudaVisible.compareTo(a.deudaVisible));
    return resumenes;
  }

  Future<CobrosResumen> getCobrosResumen() async {
    return SupabaseHelpers.guard('Resumen de cobranza', () async {
      try {
        final row =
            await _client.from('cobros_resumen').select().maybeSingle();
        if (row != null) {
          return CobrosResumen(
            montoTotalPendiente:
                SupabaseParse.toDouble(row['monto_total_pendiente']),
            jugadoresConDeuda:
                SupabaseParse.toInt(row['jugadores_con_deuda']),
          );
        }
      } catch (_) {
        // Vista aún no migrada o error puntual: fallback SSOT local.
      }
      final resumenes = await getResumenJugadores();
      return cobrosResumenDesdeResumenes(resumenes);
    });
  }

  Future<PartidoCompleto?> getUltimoPartido() async {
    final partidos = await getJugados(limit: 1);
    if (partidos.isEmpty) return null;
    return getCompleto(partidos.first.id!);
  }

  Future<List<PartidoCompleto>> getPartidosJugadosRecientesResumen({
    int limit = 8,
  }) async {
    // Solo los N más recientes: no cargar todo el historial jugado.
    final partidos = await getJugados(limit: limit);
    if (partidos.isEmpty) return const [];
    final ids = partidos.map((p) => p.id).whereType<int>().toList();
    if (ids.isEmpty) return const [];
    return getCompletosListaResumen(ids);
  }

  Future<int> guardarPartido({
    required Partido partido,
    required List<String> jugadoresAsistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
    String? organizadorId,
  }) async {
    return SupabaseHelpers.write('Guardar encuentro', () async {
      final realtime = SupabaseRealtimeService.instance;
      realtime.beginBulkWrite();
      try {
        final synced = await _sincronizarComprobantesGastos(
          partido: partido,
          costosVariables: costosVariables,
        );
        final partidoSync = synced.partido;
        final costosSync = synced.costos;

        final idMap = await _resolverIdsCobro(jugadoresAsistentes);
        final asistentes = idMap.values.toSet().toList();
        final prorrateo = CalculationService.prorrateoFijo(
          costoCancha: partidoSync.costoCancha,
          costoPelotas: partidoSync.costoPelotas,
          cantidadAsistentes: asistentes.length,
        );

        final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
        final partidoMap = partidoSync.toSupabaseMap(organizadorId: orgId);
        partidoMap.remove('id');

        final partidoRow = await _client
            .from('partidos')
            .insert(partidoMap)
            .select('id')
            .single();
        final partidoId = (partidoRow['id'] as num).toInt();

        await _insertarCostosYDetalles(
          partidoId: partidoId,
          partido: partidoSync,
          idMap: idMap,
          jugadoresAsistentes: jugadoresAsistentes,
          asistentes: asistentes,
          montoPagadoPorJugador: montoPagadoPorJugador,
          costosVariables: costosSync,
          saldosAnterioresSnapshot: saldosAnterioresSnapshot,
          prorrateo: prorrateo,
        );

        unawaited(_cobroNotificaciones.notificarCobrosPartido(partidoId));
        return partidoId;
      } finally {
        realtime.endBulkWrite();
      }
    });
  }

  Future<void> registrarAbono({
    required String jugadorId,
    required double monto,
    String concepto = 'Abono manual',
  }) async {
    await SupabaseHelpers.write('Registrar abono', () async {
      try {
        await _client.rpc(
          'registrar_abono_jugador',
          params: {
            'p_jugador_id': jugadorId,
            'p_monto': roundMoney(monto).toDouble(),
            'p_concepto': concepto,
          },
        );
        return;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('monto_invalido') ||
            msg.contains('permission_denied') ||
            msg.contains('jugador_no_encontrado')) {
          rethrow;
        }
        // Fallback si la migración 050 aún no está.
      }

      final orgId = _organizadorIdActual;
      final jugador = await _jugadorRepo.getById(
        jugadorId,
        organizadorId: orgId,
      );
      if (jugador == null) return;

      final saldoAnterior = jugador.saldoAcumulado;
      final saldoNuevo = CobroLogic.saldoTrasPago(
        saldoAcumulado: saldoAnterior,
        montoPagado: monto,
      );
      final ahora = DateTime.now();

      await _aplicarPagoEnDetallesImpagos(
        jugadorId: jugadorId,
        monto: monto,
        fecha: ahora,
      );

      await _client.from('saldos_historicos').insert({
        'jugador_id': jugadorId,
        'organizador_id': orgId,
        'saldo_anterior': saldoAnterior,
        'cargo_partido': 0,
        'abono': monto,
        'saldo_nuevo': saldoNuevo,
        'fecha': ahora.toIso8601String(),
        'concepto': concepto,
      });

      await _jugadorRepo.updateSaldo(jugadorId, saldoNuevo);
    });
  }

  Future<void> _recalcularSaldoJugador(String jugadorId) async {
    await _jugadorRepo.recalcularSaldosBatch([jugadorId]);
  }

  Future<List<DeudaPartidoAnterior>> _fetchPendientesPorPartido(
    String jugadorId,
  ) async {
    final orgId = _organizadorIdActual;
    var query = _client
        .from('detalles_partido')
        .select(
          'jugador_id, partido_id, total, monto_pagado, '
          'partidos!inner(id, fecha, recinto, sport_type, organizador_id)',
        )
        .eq('jugador_id', jugadorId)
        .eq('asistio', true);
    if (orgId != null) {
      query = query.eq('partidos.organizador_id', orgId);
    }
    final rows = await query;

    final saldosAnteriores =
        await _fetchSaldosAnterioresDetalles(rows as List);
    return _mapPendientesPorPartido(rows, saldosAnteriores);
  }

  Future<Map<String, List<DeudaPartidoAnterior>>> _fetchPendientesPorPartidoBatch(
    List<String> jugadorIds,
  ) async {
    if (jugadorIds.isEmpty) return {};
    final orgId = _organizadorIdActual;
    var query = _client
        .from('detalles_partido')
        .select(
          'jugador_id, partido_id, total, monto_pagado, '
          'partidos!inner(id, fecha, recinto, sport_type, organizador_id)',
        )
        .inFilter('jugador_id', jugadorIds)
        .eq('asistio', true);
    if (orgId != null) {
      query = query.eq('partidos.organizador_id', orgId);
    }
    final rows = await query;

    final saldosAnteriores =
        await _fetchSaldosAnterioresDetalles(rows as List);

    final porJugador = <String, List<DeudaPartidoAnterior>>{
      for (final id in jugadorIds) id: [],
    };
    for (final item in _mapPendientesPorPartidoConJugador(rows, saldosAnteriores)) {
      porJugador.putIfAbsent(item.jugadorId, () => []).add(item.deuda);
    }
    for (final list in porJugador.values) {
      list.sort((a, b) => a.fecha.compareTo(b.fecha));
    }
    return porJugador;
  }

  List<DeudaPartidoAnterior> _mapPendientesPorPartido(
    List rows,
    Map<String, double> saldosAnteriores,
  ) {
    return _mapPendientesPorPartidoConJugador(rows, saldosAnteriores)
        .map((e) => e.deuda)
        .where((d) => d.pendienteNeto > 0)
        .toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
  }

  Iterable<({String jugadorId, DeudaPartidoAnterior deuda})>
      _mapPendientesPorPartidoConJugador(
    List rows,
    Map<String, double> saldosAnteriores,
  ) sync* {
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      final partido = SupabaseParse.mapEmbed(map['partidos']);
      if (partido == null) continue;
      final jid = map['jugador_id']?.toString() ?? '';
      final partidoId =
          SupabaseParse.toInt(map['partido_id'] ?? partido['id']);
      final total = SupabaseParse.toDouble(map['total']);
      final pagado = SupabaseParse.toDouble(map['monto_pagado']);
      final key = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: partidoId,
        jugadorId: jid,
      );
      final monto = CobroLogic.pendienteNetoDetalle(
        partidoId: partidoId,
        jugadorId: jid,
        cargoPartido: total,
        montoPagadoEnPartido: pagado,
        snapshotSaldoAnterior: saldosAnteriores[key],
        exigirSnapshot: false,
      );
      if (monto <= 0.005) continue;
      final deuda = DeudaPartidoAnterior(
        partidoId: partidoId,
        fecha: SupabaseParse.toDateTime(partido['fecha']),
        recinto: SupabaseParse.toStringOrNull(partido['recinto']),
        pendienteNeto: monto,
        sportType: SportType.fromDb(
          SupabaseParse.toStringOrNull(partido['sport_type']),
        ),
      );
      yield (jugadorId: jid, deuda: deuda);
    }
  }

  /// Reparación manual fuera del flujo normal. No invocar en cargas de pantalla.
  @Deprecated('Solo reparación manual; no usar en flujo normal')
  Future<void> reconciliarDetallesJugador(String jugadorId) async {
    await SupabaseHelpers.write('Reconciliar detalles jugador', () async {
      final jugador = await _jugadorRepo.getById(
        jugadorId,
        organizadorId: _organizadorIdActual,
      );
      if (jugador == null) return;

      final saldo = jugador.saldoAcumulado;
      final ahora = DateTime.now();

      if (saldo <= 0) {
        final impagos = await _client
            .from('detalles_partido')
            .select('id, total, monto_pagado, partido_id, partidos!inner(fecha)')
            .eq('jugador_id', jugadorId)
            .eq('asistio', true)
            .eq('pagado', false);

        final sorted = (impagos as List).map((row) {
          final map = Map<String, dynamic>.from(row);
          final partido = SupabaseParse.mapEmbed(map['partidos']);
          return (
            id: (map['id'] as num).toInt(),
            partidoId: SupabaseParse.toInt(map['partido_id']),
            total: SupabaseParse.toDouble(map['total']),
            montoPagado: SupabaseParse.toDouble(map['monto_pagado']),
            fecha: partido == null
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : SupabaseParse.toDateTime(partido['fecha']),
          );
        }).toList()
          ..sort((a, b) {
            final cmp = a.fecha.compareTo(b.fecha);
            if (cmp != 0) return cmp;
            return a.partidoId.compareTo(b.partidoId);
          });

        if (sorted.isEmpty) return;

        var saldoActual = saldo;
        for (final d in sorted) {
          final pago = _estadoPagoPartido(
            saldoAnterior: saldoActual,
            cargo: d.total,
            montoPagadoOrganizador: d.montoPagado,
          );
          if (!pago.pagado) continue;

          await _client.from('detalles_partido').update({
            'pagado': true,
            'fecha_pago': ahora.toIso8601String(),
            'monto_pagado': pago.montoPagado,
            'comprobante_validado': true,
            'comprobante_url': null,
            'monto_pago_declarado': null,
            'pago_es_abono': null,
          }).eq('id', d.id);

          saldoActual = pago.saldoNuevo;
        }

        if ((saldoActual - saldo).abs() > 0.005) {
          await _jugadorRepo.updateSaldo(jugadorId, saldoActual);
        }
        await _recalcularSaldoJugador(jugadorId);
        return;
      }

      final rows = await _client
          .from('detalles_partido')
          .select('id, total, monto_pagado')
          .eq('jugador_id', jugadorId)
          .eq('asistio', true)
          .eq('pagado', false);

      var sumPendiente = 0.0;
      for (final row in rows as List) {
        final total = SupabaseParse.toDouble(row['total']);
        final pagado = SupabaseParse.toDouble(row['monto_pagado']);
        sumPendiente += (total - pagado).clamp(0.0, double.infinity);
      }
      sumPendiente = roundMoney(sumPendiente).toDouble();

      final diff = roundMoney(sumPendiente - saldo).toDouble();
      if (diff > 0.01) {
        await _aplicarAbonoVirtualDetalles(
          jugadorId: jugadorId,
          montoAplicado: diff,
          fecha: ahora,
        );
        await _recalcularSaldoJugador(jugadorId);
        return;
      }

      if (diff < -0.01) {
        await _reabrirDetallesPorDeficit(
          jugadorId: jugadorId,
          deficit: roundMoney(saldo - sumPendiente).toDouble(),
        );
      }

      await _recalcularSaldoJugador(jugadorId);
    });
  }

  /// Reabre cobros marcados pagados cuando la suma de impagos quedó bajo el saldo real.
  Future<void> _reabrirDetallesPorDeficit({
    required String jugadorId,
    required double deficit,
  }) async {
    if (deficit <= 0) return;

    final rows = await _client
        .from('detalles_partido')
        .select('id, total, monto_pagado, partidos!inner(fecha)')
        .eq('jugador_id', jugadorId)
        .eq('asistio', true)
        .eq('pagado', true);

    final sorted = (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final partido = SupabaseParse.mapEmbed(map['partidos']);
      return (
        id: (map['id'] as num).toInt(),
        total: SupabaseParse.toDouble(map['total']),
        yaPagado: SupabaseParse.toDouble(map['monto_pagado']),
        fecha: partido == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : SupabaseParse.toDateTime(partido['fecha']),
      );
    }).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));

    var restante = deficit;
    for (final row in sorted) {
      if (restante <= 0.01) break;
      if (row.yaPagado <= 0) continue;

      final reabrir = restante >= row.yaPagado ? row.yaPagado : restante;
      final nuevoPagado = roundMoney(row.yaPagado - reabrir).toDouble();
      final siguePagado = nuevoPagado >= row.total - 0.005;

      await _client.from('detalles_partido').update({
        'monto_pagado': nuevoPagado,
        'pagado': siguePagado,
        if (!siguePagado) 'fecha_pago': null,
      }).eq('id', row.id);

      restante = roundMoney(restante - reabrir).toDouble();
    }
  }

  @Deprecated('Solo reparación manual; usar _aplicarPagoEnDetallesImpagos en pagos')
  Future<void> _aplicarAbonoVirtualDetalles({
    required String jugadorId,
    required double montoAplicado,
    required DateTime fecha,
  }) async {
    if (montoAplicado <= 0) return;

    final rows = await _client
        .from('detalles_partido')
        .select('id, total, monto_pagado, partidos!inner(fecha)')
        .eq('jugador_id', jugadorId)
        .eq('asistio', true)
        .eq('pagado', false);

    final sorted = (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final partido = SupabaseParse.mapEmbed(map['partidos']);
      return (
        id: (map['id'] as num).toInt(),
        total: SupabaseParse.toDouble(map['total']),
        yaPagado: SupabaseParse.toDouble(map['monto_pagado']),
        fecha: partido == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : SupabaseParse.toDateTime(partido['fecha']),
      );
    }).toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));

    var restante = roundMoney(montoAplicado).toDouble();
    for (final row in sorted) {
      if (restante <= 0.01) break;

      final id = row.id;
      final total = row.total;
      final yaPagado = row.yaPagado;
      final pendiente = roundMoney(total - yaPagado).toDouble();
      if (pendiente <= 0) {
        await _client.from('detalles_partido').update({
          'pagado': true,
          'fecha_pago': fecha.toIso8601String(),
          'comprobante_validado': true,
          'comprobante_url': null,
          'monto_pago_declarado': null,
          'pago_es_abono': null,
        }).eq('id', id);
        continue;
      }

      final aplicar = restante >= pendiente ? pendiente : restante;
      final nuevoMonto = roundMoney(yaPagado + aplicar).toDouble();
      final cubierto = nuevoMonto >= total - 0.005;

      await _client.from('detalles_partido').update({
        'monto_pagado': nuevoMonto,
        'pagado': cubierto,
        if (cubierto) 'fecha_pago': fecha.toIso8601String(),
        if (cubierto) 'comprobante_validado': true,
        if (cubierto) 'comprobante_url': null,
        if (cubierto) 'monto_pago_declarado': null,
        if (cubierto) 'pago_es_abono': null,
      }).eq('id', id);

      restante = roundMoney(restante - aplicar).toDouble();
    }
  }

  Future<List<DeudaPartidoAnterior>> getDeudasPartidosAnteriores({
    required String jugadorId,
    required int partidoActualId,
    bool reconciliar = false,
  }) async {
    if (reconciliar) {
      throw UnsupportedError(
        'reconciliar en getDeudasPartidosAnteriores ya no está soportado',
      );
    }
    return SupabaseHelpers.guard('Deudas encuentros anteriores', () async {
      final pendientes = await _fetchPendientesPorPartido(jugadorId);
      return pendientes.where((d) => d.partidoId != partidoActualId).toList();
    });
  }

  Future<List<DeudaPartidoAnterior>> getPartidosPendientesJugador(
    String jugadorId, {
    bool reconciliar = false,
  }) async {
    if (reconciliar) {
      throw UnsupportedError(
        'reconciliar en getPartidosPendientesJugador ya no está soportado',
      );
    }
    return SupabaseHelpers.guard('Encuentros pendientes jugador', () async {
      return _fetchPendientesPorPartido(jugadorId);
    });
  }

  Future<({int partidosJugados, int partidosPagados, int partidosImpagos})>
      getResumenPartidosJugador(String jugadorId) async {
    return SupabaseHelpers.guard('Resumen encuentros jugador', () async {
      final orgId = _organizadorIdActual;
      var query = _client
          .from('detalles_partido')
          .select('pagado, partidos!inner(organizador_id)')
          .eq('jugador_id', jugadorId)
          .eq('asistio', true);
      if (orgId != null) {
        query = query.eq('partidos.organizador_id', orgId);
      }
      final rows = await query;

      var jugados = 0;
      var pagados = 0;
      var impagos = 0;
      for (final row in rows as List) {
        jugados++;
        if (row['pagado'] == true) {
          pagados++;
        } else {
          impagos++;
        }
      }
      return (
        partidosJugados: jugados,
        partidosPagados: pagados,
        partidosImpagos: impagos,
      );
    });
  }

  Future<List<ResumenJugador>> getDeudoresVencidos(int diasMinimos) async {
    final resumenes = await getResumenJugadores(reconciliar: false);
    final deudores = resumenes.where((r) => r.tieneDeuda).toList();
    if (deudores.isEmpty) return [];

    final ids = deudores
        .map((r) => r.jugador.keyId)
        .where((id) => id.isNotEmpty)
        .toList();
    final pendientesPorJugador = await _fetchPendientesPorPartidoBatch(ids);
    final ahora = DateTime.now();
    final vencidos = deudores.where((r) {
      final pendientes = pendientesPorJugador[r.jugador.keyId] ?? [];
      return pendientes.any(
        (p) => ahora.difference(p.fecha).inDays >= diasMinimos,
      );
    }).toList();
    vencidos.sort(
      (a, b) => a.jugador.nombre.compareTo(b.jugador.nombre),
    );
    return vencidos;
  }

  Future<void> actualizarPartido({
    required int partidoId,
    required Partido partido,
    required List<String> jugadoresAsistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
  }) async {
    await SupabaseHelpers.write('Actualizar encuentro', () async {
      final realtime = SupabaseRealtimeService.instance;
      realtime.beginBulkWrite();
      try {
        final synced = await _sincronizarComprobantesGastos(
          partido: partido,
          costosVariables: costosVariables,
          partidoId: partidoId,
        );
        final partidoSync = synced.partido;
        final costosSync = synced.costos;

        await _prepararReemplazoPartido(partidoId);

        final idMap = await _resolverIdsCobro(jugadoresAsistentes);
        final asistentes = idMap.values.toSet().toList();
        final prorrateo = CalculationService.prorrateoFijo(
          costoCancha: partidoSync.costoCancha,
          costoPelotas: partidoSync.costoPelotas,
          cantidadAsistentes: asistentes.length,
        );

        final partidoMap = partidoSync.toSupabaseMap();
        partidoMap.remove('id');
        final orgId = SupabaseHelpers.currentUserId;
        if (orgId != null) {
          partidoMap['organizador_id'] = orgId;
        }
        await _client.from('partidos').update(partidoMap).eq('id', partidoId);

        await _insertarCostosYDetalles(
          partidoId: partidoId,
          partido: partidoSync,
          idMap: idMap,
          jugadoresAsistentes: jugadoresAsistentes,
          asistentes: asistentes,
          montoPagadoPorJugador: montoPagadoPorJugador,
          costosVariables: costosSync,
          saldosAnterioresSnapshot: saldosAnterioresSnapshot,
          prorrateo: prorrateo,
        );

        unawaited(_cobroNotificaciones.notificarCobrosPartido(partidoId));
      } finally {
        realtime.endBulkWrite();
      }
    });
  }

  Future<void> completarPartidoOrganizado({
    required int partidoId,
    required Partido partido,
    required List<String> jugadoresAsistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
  }) async {
    await SupabaseHelpers.write('Completar encuentro organizado', () async {
      final realtime = SupabaseRealtimeService.instance;
      realtime.beginBulkWrite();
      try {
        final synced = await _sincronizarComprobantesGastos(
          partido: partido,
          costosVariables: costosVariables,
          partidoId: partidoId,
        );
        final partidoSync = synced.partido;
        final costosSync = synced.costos;

        // Idempotente: si un intento previo dejó cobros a medias, limpia antes.
        await _prepararReemplazoPartido(partidoId);

        final idMap = await _resolverIdsCobro(jugadoresAsistentes);
        final asistentes = idMap.values.toSet().toList();
        final prorrateo = CalculationService.prorrateoFijo(
          costoCancha: partidoSync.costoCancha,
          costoPelotas: partidoSync.costoPelotas,
          cantidadAsistentes: asistentes.length,
        );

        final partidoMap =
            partidoSync.copyWith(estado: EstadoPartido.jugado).toSupabaseMap();
        partidoMap.remove('id');
        final orgId = SupabaseHelpers.currentUserId;
        if (orgId != null) {
          partidoMap['organizador_id'] = orgId;
        }
        await _client.from('partidos').update(partidoMap).eq('id', partidoId);

        await _client
            .from('convocatoria_jugadores')
            .delete()
            .eq('partido_id', partidoId);

        await _insertarCostosYDetalles(
          partidoId: partidoId,
          partido: partidoSync,
          idMap: idMap,
          jugadoresAsistentes: jugadoresAsistentes,
          asistentes: asistentes,
          montoPagadoPorJugador: montoPagadoPorJugador,
          costosVariables: costosSync,
          saldosAnterioresSnapshot: saldosAnterioresSnapshot,
          prorrateo: prorrateo,
        );

        unawaited(_cobroNotificaciones.notificarCobrosPartido(partidoId));
      } finally {
        realtime.endBulkWrite();
      }
    });
  }

  /// Saldos anteriores del jugador autenticado en varios partidos.
  Future<Map<int, double>> getMisSaldosAnterioresPartidos(
    Iterable<int> partidoIds,
  ) async {
    return SupabaseHelpers.guard('Mis saldos anteriores', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return {};

      final ids = partidoIds.toSet().toList();
      if (ids.isEmpty) return {};

      final rows = await _client
          .from('saldos_historicos')
          .select('partido_id, saldo_anterior, cargo_partido, fecha, id')
          .eq('jugador_id', uid)
          .inFilter('partido_id', ids)
          .gt('cargo_partido', 0)
          .order('fecha', ascending: true)
          .order('id', ascending: true);

      final map = <int, double>{};
      for (final row in rows as List) {
        final partidoId = SupabaseParse.toInt(row['partido_id']);
        if (partidoId <= 0 || map.containsKey(partidoId)) continue;
        map[partidoId] = SupabaseParse.toDouble(row['saldo_anterior']);
      }
      return map;
    });
  }

  /// Desglose del jugador autenticado para un partido (vista jugador).
  Future<DesgloseJugador?> getMiDesglosePartido(int partidoId) async {
    return SupabaseHelpers.withTimeout(
      SupabaseHelpers.guard('Mi desglose encuentro', () async {
        final uid = SupabaseHelpers.currentUserId;
        if (uid == null) return null;

        try {
          final raw = await _client.rpc(
            'get_mi_desglose_partido',
            params: {'p_partido_id': partidoId},
          );
          if (raw is Map) {
            final rpcMap = Map<String, dynamic>.from(raw);
            final saldoAnt = await _requerirSaldoAnteriorSnapshot(
              jugadorId: uid,
              partidoId: partidoId,
            );
            return _desgloseJugadorFromRpcMap(
              rpcMap,
              uid,
              saldoAnteriorOverride: saldoAnt,
            );
          }
        } catch (e) {
          if (e is DatosInconsistentesException) rethrow;
          // RPC no desplegado: fallback directo.
        }

        final detalleRow = await _client
            .from('detalles_partido')
            .select('*, profiles:jugador_id(nombre)')
            .eq('partido_id', partidoId)
            .eq('jugador_id', uid)
            .maybeSingle();
        if (detalleRow == null) return null;

        final detalleMap = Map<String, dynamic>.from(detalleRow);
        final profile = SupabaseParse.mapEmbed(detalleMap['profiles']);
        final nombre = SupabaseParse.toStringOrNull(profile?['nombre']) ?? 'Participante';

        final partidoRow = await _client
            .from('partidos')
            .select()
            .eq('id', partidoId)
            .maybeSingle();

        final histRow = await _client
            .from('saldos_historicos')
            .select('saldo_anterior')
            .eq('partido_id', partidoId)
            .eq('jugador_id', uid)
            .maybeSingle();
        if (histRow == null) {
          throw DatosInconsistentesException(
            'Datos inconsistentes: falta snapshot saldo_anterior '
            '(jugador $uid, partido $partidoId)',
          );
        }
        final saldoAnt = CobroLogic.saldoAnteriorAlPartido(
          snapshotHistorico:
              SupabaseParse.toDouble(histRow['saldo_anterior']),
        );

        if (partidoRow == null) {
          return _desgloseFallbackDesdeDetalle(
            detalleMap: detalleMap,
            uid: uid,
            nombre: nombre,
            saldoAnterior: saldoAnt,
          );
        }

        final partido =
            Partido.fromSupabaseMap(Map<String, dynamic>.from(partidoRow));

        final pf = (detalleMap['prorrateo_fijo'] as num?)?.toDouble() ?? 0.0;
        final totalFijo = partido.costoCancha + partido.costoPelotas;
        var cancha = 0.0;
        var pelotas = 0.0;
        if (totalFijo > 0 && pf > 0) {
          cancha = pf * (partido.costoCancha / totalFijo);
          pelotas = pf * (partido.costoPelotas / totalFijo);
        } else if (pf > 0) {
          cancha = pf;
        }

        final vars = await _variablesAsignadasPartido(partidoId, uid);
        return _desgloseJugadorDesdeDatos(
          uid: uid,
          nombre: nombre,
          saldoAnterior: saldoAnt,
          cancha: cancha,
          pelotas: pelotas,
          variables: vars,
          detalleMap: detalleMap,
        );
      }),
      operacion: 'Mi desglose encuentro',
    );
  }

  DesgloseJugador? _desgloseJugadorFromRpcMap(
    Map<String, dynamic> map,
    String uid, {
    double? saldoAnteriorOverride,
  }) {
    final nombre = SupabaseParse.toStringOrNull(map['nombre']) ?? 'Participante';
    final saldoAnt = saldoAnteriorOverride ??
        SupabaseParse.toDouble(map['saldo_anterior']);
    final pf = SupabaseParse.toDouble(map['prorrateo_fijo']);
    final costoCancha = SupabaseParse.toDouble(map['costo_cancha']);
    final costoPelotas = SupabaseParse.toDouble(map['costo_pelotas']);
    final totalFijo = costoCancha + costoPelotas;

    var cancha = 0.0;
    var pelotas = 0.0;
    if (totalFijo > 0 && pf > 0) {
      cancha = pf * (costoCancha / totalFijo);
      pelotas = pf * (costoPelotas / totalFijo);
    } else if (pf > 0) {
      cancha = pf;
    }

    final varsRaw = map['variables'];
    final vars = <String, double>{};
    if (varsRaw is Map) {
      for (final entry in varsRaw.entries) {
        final monto = SupabaseParse.toDouble(entry.value);
        if (monto > 0) {
          vars[entry.key.toString()] = monto;
        }
      }
    }

    return _desgloseJugadorDesdeDatos(
      uid: uid,
      nombre: nombre,
      saldoAnterior: saldoAnt,
      cancha: cancha,
      pelotas: pelotas,
      variables: vars,
      detalleMap: map,
    );
  }

  Future<Map<String, double>> _variablesAsignadasPartido(
    int partidoId,
    String uid,
  ) async {
    final rows = await _client
        .from('asignaciones_costo')
        .select('monto, costos_variables!inner(concepto, partido_id)')
        .eq('costos_variables.partido_id', partidoId)
        .eq('jugador_id', uid);

    final vars = <String, double>{};
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row);
      final cv = SupabaseParse.mapEmbed(map['costos_variables']);
      final concepto = SupabaseParse.toStringOrNull(cv?['concepto']);
      final monto = SupabaseParse.toDouble(map['monto']);
      if (concepto != null && monto > 0) {
        vars[concepto] = monto;
      }
    }
    return vars;
  }

  DesgloseJugador _desgloseFallbackDesdeDetalle({
    required Map<String, dynamic> detalleMap,
    required String uid,
    required String nombre,
    required double saldoAnterior,
  }) {
    final pf = SupabaseParse.toDouble(detalleMap['prorrateo_fijo']);
    final tv = SupabaseParse.toDouble(detalleMap['total_variables']);
    final variables = tv > 0 ? <String, double>{'Extras': tv} : <String, double>{};
    return _desgloseJugadorDesdeDatos(
      uid: uid,
      nombre: nombre,
      saldoAnterior: saldoAnterior,
      cancha: pf,
      pelotas: 0,
      variables: variables,
      detalleMap: detalleMap,
    );
  }

  DesgloseJugador _desgloseJugadorDesdeDatos({
    required String uid,
    required String nombre,
    required double saldoAnterior,
    required double cancha,
    required double pelotas,
    required Map<String, double> variables,
    required Map<String, dynamic> detalleMap,
  }) {
    final pf = SupabaseParse.toDouble(detalleMap['prorrateo_fijo']);
    final totalVars = SupabaseParse.toDouble(detalleMap['total_variables']);
    final totalPartido = CalculationService.cargoPartido(
      prorrateoFijo: pf,
      totalVariables: totalVars,
    );
    final montoPagado = SupabaseParse.toDouble(detalleMap['monto_pagado']);
    final pagado = detalleMap['pagado'] as bool? ?? false;
    final totalDebido = CalculationService.totalDebido(
      saldoAnterior: saldoAnterior,
      cargoPartido: totalPartido,
    );
    final saldoRestante = CalculationService.saldoDespuesPago(
      saldoAnterior: saldoAnterior,
      cargoPartido: totalPartido,
      montoPagado: montoPagado,
    );

    return DesgloseJugador(
      jugadorSupabaseId: uid,
      nombre: nombre,
      saldoAnterior: roundMoney(saldoAnterior).toDouble(),
      cancha: roundMoney(cancha).toDouble(),
      pelotas: roundMoney(pelotas).toDouble(),
      variables: variables.map(
        (k, v) => MapEntry(k, roundMoney(v).toDouble()),
      ),
      totalPartido: roundMoney(totalPartido).toDouble(),
      totalDebido: roundMoney(totalDebido).toDouble(),
      montoPagado: roundMoney(montoPagado).toDouble(),
      saldoRestante: roundMoney(saldoRestante).toDouble(),
      pagado: pagado,
    );
  }

  /// Partidos en los que el jugador autenticado asistió (más recientes primero).
  Future<List<DetallePartido>> getMisPartidosJugados({int limit = 30}) async {
    return SupabaseHelpers.guard('Mis encuentros jugados', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return [];

      final rows = await _client
          .from('detalles_partido')
          .select(
            '*, partidos!inner(fecha, recinto, estado, sport_type, organizador_id)',
          )
          .eq('jugador_id', uid)
          .eq('asistio', true)
          .order('partido_id', ascending: false)
          .limit(limit);

      final lista = (rows as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        final partidoEmbed = SupabaseParse.mapEmbed(map['partidos']);
        return DetallePartido.fromSupabaseMap(
          map,
          fechaPartido: partidoEmbed == null
              ? null
              : SupabaseParse.toDateTime(partidoEmbed['fecha']),
          recintoPartido:
              SupabaseParse.toStringOrNull(partidoEmbed?['recinto']),
          sportType: SportType.fromDb(
            SupabaseParse.toStringOrNull(partidoEmbed?['sport_type']),
          ),
          organizadorId:
              SupabaseParse.toStringOrNull(partidoEmbed?['organizador_id']),
        );
      }).toList();

      lista.sort((a, b) {
        final fa = a.fechaPartido;
        final fb = b.fechaPartido;
        if (fa == null && fb == null) return b.partidoId.compareTo(a.partidoId);
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fb.compareTo(fa);
      });
      return lista;
    });
  }

  /// Gastos del jugador autenticado por concepto (su parte en partidos jugados).
  Future<List<GastoPorConcepto>> getMisGastosPorConcepto({
    DateTime? desde,
    DateTime? hasta,
  }) async {
    return SupabaseHelpers.guard('Mis gastos por concepto', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return [];

      final detalleRows = await _client
          .from('detalles_partido')
          .select(
            'partido_id, partidos!inner(id, fecha, costo_cancha, costo_pelotas)',
          )
          .eq('jugador_id', uid)
          .eq('asistio', true);

      final partidosEnRango = <int, Map<String, dynamic>>{};
      for (final row in detalleRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final partidoEmbed = SupabaseParse.mapEmbed(map['partidos']);
        if (partidoEmbed == null) continue;
        final fecha = SupabaseParse.toDateTime(partidoEmbed['fecha']);
        if (desde != null && fecha.isBefore(desde)) continue;
        if (hasta != null && !fecha.isBefore(hasta)) continue;
        final partidoId = SupabaseParse.toInt(map['partido_id']);
        if (partidoId <= 0) continue;
        partidosEnRango[partidoId] = partidoEmbed;
      }

      if (partidosEnRango.isEmpty) return [];

      final partidoIds = partidosEnRango.keys.toList();
      final asistentesRows = await _client
          .from('detalles_partido')
          .select('partido_id')
          .inFilter('partido_id', partidoIds)
          .eq('asistio', true);

      final asistentesPorPartido = <int, int>{};
      for (final row in asistentesRows as List) {
        final id = SupabaseParse.toInt((row as Map)['partido_id']);
        if (id <= 0) continue;
        asistentesPorPartido[id] = (asistentesPorPartido[id] ?? 0) + 1;
      }

      final totales = <String, double>{};
      for (final entry in partidosEnRango.entries) {
        final n = asistentesPorPartido[entry.key] ?? 0;
        if (n <= 0) continue;
        final cancha = SupabaseParse.toDouble(entry.value['costo_cancha']);
        final pelotas = SupabaseParse.toDouble(entry.value['costo_pelotas']);
        if (cancha > 0) {
          totales[ConceptosCobro.cancha] =
              (totales[ConceptosCobro.cancha] ?? 0) + cancha / n;
        }
        if (pelotas > 0) {
          totales[ConceptosCobro.pelotas] =
              (totales[ConceptosCobro.pelotas] ?? 0) + pelotas / n;
        }
      }

      final asigs = await _client
          .from('asignaciones_costo')
          .select('monto, costos_variables!inner(concepto, partido_id)')
          .eq('jugador_id', uid);

      for (final row in asigs as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final cv = SupabaseParse.mapEmbed(map['costos_variables']);
        if (cv == null) continue;
        final partidoId = SupabaseParse.toInt(cv['partido_id']);
        if (!partidosEnRango.containsKey(partidoId)) continue;
        final concepto = SupabaseParse.toStringOrNull(cv['concepto']);
        if (concepto == null || ConceptosCobro.esFijo(concepto)) continue;
        final monto = SupabaseParse.toDouble(map['monto']);
        if (monto <= 0) continue;
        totales[concepto] = (totales[concepto] ?? 0) + monto;
      }

      final lista = totales.entries
          .where((e) => e.value > 0.005)
          .map(
            (e) => GastoPorConcepto(
              concepto: e.key,
              monto: roundMoney(e.value).toDouble(),
            ),
          )
          .toList()
        ..sort((a, b) => b.monto.compareTo(a.monto));
      return lista;
    });
  }

  /// Deudas del jugador autenticado con comprobante pendiente o sin pagar.
  Future<List<DetallePartido>> getMisDeudasPendientes({
    bool reconciliar = false,
  }) async {
    if (reconciliar) {
      throw UnsupportedError(
        'reconciliar en getMisDeudasPendientes ya no está soportado',
      );
    }
    return SupabaseHelpers.guard('Mis deudas', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return [];

      var rpcLista = <DetallePartido>[];
      try {
        final raw = await _client.rpc('get_mis_deudas_pendientes');
        if (raw is List) {
          rpcLista = raw.map((row) {
            final map = Map<String, dynamic>.from(row as Map);
            return DetallePartido.fromSupabaseMap(
              map,
              fechaPartido: SupabaseParse.toDateTime(map['partido_fecha']),
              recintoPartido:
                  SupabaseParse.toStringOrNull(map['partido_recinto']),
              sportType: SportType.fromDb(
                SupabaseParse.toStringOrNull(map['partido_sport_type']),
              ),
            );
          }).toList();
        }
      } catch (_) {
        // RPC no desplegado: fallback con relink manual.
      }

      final directo = await _fetchMisDeudasDirecto(uid);
      final unicos = <String, DetallePartido>{};
      for (final d in [...rpcLista, ...directo]) {
        final key = d.id?.toString() ?? '${d.partidoId}:${d.jugadorKeyId}';
        unicos[key] = d;
      }
      final conOrg = await _enrichOrganizadorIds(unicos.values.toList());
      return _filtrarMisDeudasNetas(conOrg, uid);
    });
  }

  Future<List<DetallePartido>> _enrichOrganizadorIds(
    List<DetallePartido> deudas,
  ) async {
    final missing = deudas
        .where((d) => d.organizadorId == null || d.organizadorId!.isEmpty)
        .map((d) => d.partidoId)
        .toSet()
        .toList();
    if (missing.isEmpty) return deudas;

    final rows = await _client
        .from('partidos')
        .select('id, organizador_id')
        .inFilter('id', missing);
    final byPartido = <int, String>{};
    for (final row in rows as List) {
      final id = (row['id'] as num?)?.toInt();
      final org = row['organizador_id']?.toString();
      if (id == null || org == null || org.isEmpty) continue;
      byPartido[id] = org;
    }
    return [
      for (final d in deudas)
        d.organizadorId != null && d.organizadorId!.isNotEmpty
            ? d
            : d.copyWith(organizadorId: byPartido[d.partidoId]),
    ];
  }

  Future<List<DetallePartido>> _filtrarMisDeudasNetas(
    List<DetallePartido> candidatos,
    String uid,
  ) async {
    if (candidatos.isEmpty) return [];

    final partidoIds = candidatos.map((d) => d.partidoId).toSet().toList();
    final saldoPorPartido = <int, double>{};
    for (final entry in (await _fetchSnapshotsSaldoAnteriorCobroBatch(
      partidoIds: partidoIds,
      jugadorIds: [uid],
    )).entries) {
      final pid = int.tryParse(entry.key.split(':').first);
      if (pid != null) saldoPorPartido[pid] = entry.value;
    }

    return candidatos.where((d) {
      if (d.comprobantePendienteValidacion) return true;
      // Cubierto con saldo a favor: pagado=true y monto_pagado=0. No reabrir.
      if (d.pagado) return false;
      final saldoAnt = saldoPorPartido[d.partidoId];
      if (saldoAnt == null) {
        // Sin snapshot: no inventar deuda neta con saldo 0; solo residual bruto.
        return (d.total - d.montoPagado) > 0.005;
      }
      return CobroLogic.pendienteNetoDetalle(
            partidoId: d.partidoId,
            jugadorId: uid,
            cargoPartido: d.total,
            montoPagadoEnPartido: d.montoPagado,
            snapshotSaldoAnterior: saldoAnt,
          ) >
          0.005;
    }).toList();
  }

  Future<List<DetallePartido>> _fetchMisDeudasDirecto(String uid) async {
    // Solo abiertos o con comprobante en revisión (antes: últimos 40 asistidos
    // incluían partidos ya cubiertos con crédito → UI ofrecía pagar de nuevo).
    final rows = await _client
        .from('detalles_partido')
        .select(
          '*, partidos(fecha, recinto, estado, sport_type, organizador_id)',
        )
        .eq('jugador_id', uid)
        .eq('asistio', true)
        .or(
          'pagado.eq.false,'
          'comprobante_estado.eq.en_revision',
        )
        .order('partido_id', ascending: false)
        .limit(40);

    return (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final partidoEmbed = SupabaseParse.mapEmbed(map['partidos']);
      return DetallePartido.fromSupabaseMap(
        map,
        fechaPartido: partidoEmbed == null
            ? null
            : SupabaseParse.toDateTime(partidoEmbed['fecha']),
        recintoPartido: SupabaseParse.toStringOrNull(partidoEmbed?['recinto']),
        sportType: SportType.fromDb(
          SupabaseParse.toStringOrNull(partidoEmbed?['sport_type']),
        ),
        organizadorId:
            SupabaseParse.toStringOrNull(partidoEmbed?['organizador_id']),
      );
    }).toList();
  }

  Future<void> eliminarPartido(int id) async {
    await SupabaseHelpers.write('Eliminar encuentro', () async {
      final paths = <String>{};

      final pagoRows = await _client
          .from('detalles_partido')
          .select('comprobante_url')
          .eq('partido_id', id);
      for (final row in pagoRows as List) {
        final p = SupabaseParse.toStringOrNull(
          Map<String, dynamic>.from(row)['comprobante_url'],
        );
        if (p != null && p.isNotEmpty) paths.add(p);
      }

      final partidoRow = await _client
          .from('partidos')
          .select('comprobante_cancha_url, comprobante_pelotas_url')
          .eq('id', id)
          .maybeSingle();
      if (partidoRow != null) {
        final map = Map<String, dynamic>.from(partidoRow);
        for (final key in ['comprobante_cancha_url', 'comprobante_pelotas_url']) {
          final p = SupabaseParse.toStringOrNull(map[key]);
          if (p != null && p.isNotEmpty) paths.add(p);
        }
      }

      final gastoRows = await _client
          .from('costos_variables')
          .select('comprobante_url')
          .eq('partido_id', id);
      for (final row in gastoRows as List) {
        final p = SupabaseParse.toStringOrNull(
          Map<String, dynamic>.from(row)['comprobante_url'],
        );
        if (p != null && p.isNotEmpty) paths.add(p);
      }

      try {
        await _client.rpc(
          'eliminar_partido_completo',
          params: {'p_partido_id': id},
        );
      } catch (_) {
        // RPC no desplegado: fallback manual.
        final detalleRows = await _client
            .from('detalles_partido')
            .select('jugador_id')
            .eq('partido_id', id);

        final jugadorIds = (detalleRows as List)
            .map((row) => row['jugador_id']?.toString())
            .whereType<String>()
            .toSet();

        await _client.from('saldos_historicos').delete().eq('partido_id', id);
        await _client.from('partidos').delete().eq('id', id);

        for (final jid in jugadorIds) {
          await _recalcularSaldoJugador(jid);
        }
      }

      for (final path in paths) {
        if (isCloudComprobantePath(path)) {
          await SupabaseStorageService.instance.deleteIfExists(path);
        }
      }
    });
  }

  Future<void> subirComprobantePago({
    required int detalleId,
    required String storagePath,
    required double montoDeclarado,
    required bool esAbono,
    required String organizadorId,
  }) async {
    await SupabaseHelpers.write('Subir comprobante', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) {
        throw Exception('Sesión requerida');
      }
      if (montoDeclarado <= 0) {
        throw Exception('El importe del pago debe ser superior a cero');
      }
      final orgEsperado = organizadorId.trim();
      if (orgEsperado.isEmpty) {
        throw Exception('Organizador requerido');
      }

      final prev = await _client
          .from('detalles_partido')
          .select(
            'partido_id, jugador_id, total, pagado, monto_pagado, comprobante_url, '
            'comprobante_validado, comprobante_estado, monto_pago_declarado, '
            'profiles:jugador_id(nombre), partidos(organizador_id)',
          )
          .eq('id', detalleId)
          .eq('jugador_id', uid)
          .single();

      final prevMap = Map<String, dynamic>.from(prev);
      final yaPendiente = DetallePartido.fromSupabaseMap(prevMap)
          .comprobantePendienteValidacion;
      if (yaPendiente) {
        throw Exception(
          'Ya tienes un pago pendiente de aprobación del organizador',
        );
      }

      final partidoId = (prevMap['partido_id'] as num).toInt();
      final partidoEmbed = SupabaseParse.mapEmbed(prevMap['partidos']);
      final orgDelPartido =
          SupabaseParse.toStringOrNull(partidoEmbed?['organizador_id'])?.trim();
      if (orgDelPartido == null || orgDelPartido.isEmpty) {
        throw Exception('Partido sin organizador');
      }
      if (orgDelPartido != orgEsperado) {
        throw Exception(
          'El comprobante no corresponde al organizador seleccionado',
        );
      }
      final total = SupabaseParse.toDouble(prevMap['total']);
      final montoPagadoEnPartido =
          SupabaseParse.toDouble(prevMap['monto_pagado']);

      final pendienteCuenta = CobroLogic.obtenerPendienteJugador(
        saldoAcumulado: await _jugadorRepo.getSaldoCuenta(
          organizadorId: orgEsperado,
          jugadorId: uid,
        ),
      );

      final snapshotSaldo = await _snapshotSaldoAnteriorOpcional(
        jugadorId: uid,
        partidoId: partidoId,
      );
      final pendientePartido = snapshotSaldo != null
          ? CobroLogic.obtenerPendientePartido(
              saldoAnteriorAlPartido: snapshotSaldo,
              cargoPartido: total,
              montoPagadoEnPartido: montoPagadoEnPartido,
            )
          : 0.0;

      // SSOT: no usar detalle.pagado (puede estar true con saldo_acumulado > 0).
      if (pendienteCuenta <= 0.005 && pendientePartido <= 0.005) {
        throw Exception('Este cobro ya está pagado');
      }

      final monto = roundMoney(montoDeclarado).toDouble();

      await _client.from('detalles_partido').update({
        'comprobante_url': storagePath,
        'comprobante_validado': false,
        'comprobante_estado': ComprobanteEstado.enRevision.dbValue,
        'monto_pago_declarado': monto,
        'pago_es_abono': esAbono,
      }).eq('id', detalleId).eq('jugador_id', uid);

      // Historial: cada abono conserva su foto (no se pisa).
      await _client.from('comprobantes_pago').insert({
        'detalle_id': detalleId,
        'partido_id': partidoId,
        'jugador_id': uid,
        'organizador_id': orgEsperado,
        'storage_path': storagePath,
        'monto_declarado': monto,
        'es_abono': esAbono,
        'estado': ComprobanteEstado.enRevision.dbValue,
      });

      final map = Map<String, dynamic>.from(prev);
      final profile = SupabaseParse.mapEmbed(map['profiles']);
      final nombre = SupabaseParse.toStringOrNull(profile?['nombre']) ?? 'Participante';

      await _cobroNotificaciones.notificarComprobanteOrganizador(
        detalleId: detalleId,
        partidoId: partidoId,
        organizadorId: orgEsperado,
        jugadorNombre: nombre,
        monto: monto,
        esAbono: esAbono,
      );
    });
  }

  Future<void> validarComprobantePago({
    required int detalleId,
    required bool aprobado,
  }) async {
    await SupabaseHelpers.write('Validar comprobante', () async {
      try {
        final raw = await _client.rpc(
          'validar_comprobante_pago',
          params: {
            'p_detalle_id': detalleId,
            'p_aprobado': aprobado,
          },
        );
        final result = Map<String, dynamic>.from(raw as Map);
        final accion = result['accion'] as String? ?? '';

        switch (accion) {
          case 'rechazar':
            final jugadorId =
                SupabaseParse.toStringOrNull(result['jugador_id']) ?? '';
            final partidoId = (result['partido_id'] as num?)?.toInt() ?? 0;
            await _cobroNotificaciones.notificarComprobanteRechazado(
              detalleId: detalleId,
              partidoId: partidoId,
              jugadorId: jugadorId,
              jugadorNombre:
                  SupabaseParse.toStringOrNull(result['jugador_nombre']) ??
                      'Participante',
              pendienteNeto:
                  (result['pendiente_neto'] as num?)?.toDouble() ?? 0,
              fechaPartido: result['fecha_partido'] != null
                  ? SupabaseParse.toDateTime(result['fecha_partido'])
                  : DateTime.now(),
            );
            return;
          case 'ignorar_ya_validado':
          case 'solo_marcar':
          case 'abonar_pendiente':
            return;
          default:
            return;
        }
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('datos_inconsistentes') ||
            msg.contains('detalle_no_encontrado') ||
            msg.contains('permission_denied')) {
          rethrow;
        }
        // Fallback si la migración 068 / 050 aún no está.
      }

      final row = await _client
          .from('detalles_partido')
          .select('*, partidos(fecha)')
          .eq('id', detalleId)
          .single();

      final map = Map<String, dynamic>.from(row);
      final jugadorId = SupabaseParse.toStringOrNull(map['jugador_id']);
      if (jugadorId == null || jugadorId.isEmpty) {
        throw Exception('Detalle sin jugador asociado');
      }
      final partidoId = (map['partido_id'] as num).toInt();
      final total = (map['total'] as num).toDouble();
      final montoPagado = (map['monto_pagado'] as num?)?.toDouble() ?? 0;
      final pagado = map['pagado'] as bool? ?? false;
      final comprobanteValidado = map['comprobante_validado'] as bool? ?? false;
      final montoPagoDeclarado =
          (map['monto_pago_declarado'] as num?)?.toDouble();
      final pagoEsAbono = map['pago_es_abono'] as bool? ?? false;
      final partidoEmbed = SupabaseParse.mapEmbed(map['partidos']);
      final fechaPartido = partidoEmbed == null
          ? DateTime.now()
          : SupabaseParse.toDateTime(partidoEmbed['fecha']);
      final ahora = DateTime.now();

      final saldoAntPartido = await _requerirSaldoAnteriorSnapshot(
        jugadorId: jugadorId,
        partidoId: partidoId,
      );
      final pendientePartido = CobroLogic.obtenerPendientePartido(
        saldoAnteriorAlPartido: saldoAntPartido,
        cargoPartido: total,
        montoPagadoEnPartido: montoPagado,
      );

      final decision = CobroLogic.evaluarValidacionComprobante(
        aprobado: aprobado,
        pagado: pagado,
        comprobanteValidado: comprobanteValidado,
        pendientePartido: pendientePartido,
        montoPagoDeclarado: montoPagoDeclarado,
      );

      switch (decision.accion) {
        case ComprobanteValidacionAccion.rechazar:
          await _client.from('detalles_partido').update({
            'comprobante_validado': false,
            'comprobante_estado': ComprobanteEstado.rechazado.dbValue,
            'monto_pago_declarado': null,
            'pago_es_abono': null,
          }).eq('id', detalleId);
          final jugadorRechazo = await _jugadorRepo.getById(jugadorId);
          await _cobroNotificaciones.notificarComprobanteRechazado(
            detalleId: detalleId,
            partidoId: partidoId,
            jugadorId: jugadorId,
            jugadorNombre: jugadorRechazo?.nombre ?? 'Participante',
            pendienteNeto: pendientePartido,
            fechaPartido: fechaPartido,
          );
          return;
        case ComprobanteValidacionAccion.ignorarYaValidado:
          return;
        case ComprobanteValidacionAccion.soloMarcarComprobante:
          await _client.from('detalles_partido').update({
            'comprobante_validado': true,
            'comprobante_estado': ComprobanteEstado.aprobado.dbValue,
            'monto_pago_declarado': null,
            'pago_es_abono': null,
            if (map['fecha_pago'] == null)
              'fecha_pago': ahora.toIso8601String(),
          }).eq('id', detalleId);
          return;
        case ComprobanteValidacionAccion.abonarPendiente:
          break;
      }

      final jugador = await _jugadorRepo.getById(
        jugadorId,
        organizadorId: _organizadorIdActual,
      );
      if (jugador == null) return;

      final saldoAnterior = jugador.saldoAcumulado;
      final abono = decision.abono;
      final saldoNuevo = CobroLogic.saldoTrasPago(
        saldoAcumulado: saldoAnterior,
        montoPagado: abono,
      );

      final updated = await _client
          .from('detalles_partido')
          .update({
            'comprobante_validado': true,
            'comprobante_estado': ComprobanteEstado.aprobado.dbValue,
            'monto_pago_declarado': null,
            'pago_es_abono': null,
            'fecha_pago': ahora.toIso8601String(),
          })
          .eq('id', detalleId)
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception('No se pudo validar el comprobante');
      }

      await _aplicarPagoEnDetallesImpagos(
        jugadorId: jugadorId,
        monto: abono,
        fecha: ahora,
      );

      await _client.from('saldos_historicos').insert({
        'jugador_id': jugadorId,
        'partido_id': partidoId,
        'organizador_id': _organizadorIdActual,
        'saldo_anterior': saldoAnterior,
        'cargo_partido': 0,
        'abono': abono,
        'saldo_nuevo': saldoNuevo,
        'fecha': ahora.toIso8601String(),
        'concepto': CobroLogic.conceptoValidacionOrganizador(esAbono: pagoEsAbono),
      });

      await _jugadorRepo.updateSaldo(jugadorId, saldoNuevo);
    });
  }

  /// Comprobantes de pago enviados por jugadores, pendientes de conciliar.
  /// Solo partidos del organizador autenticado (no los que envió como jugador).
  Future<List<DetallePartido>> getPagosPorValidar() async {
    return SupabaseHelpers.guard('Pagos por validar', () async {
      final uid = _organizadorIdActual;
      if (uid == null) return [];

      final rows = await _client
          .from('detalles_partido')
          .select(
            '*, partidos!inner(fecha, recinto, sport_type, organizador_id), '
            'profiles:jugador_id(nombre)',
          )
          .eq('comprobante_estado', ComprobanteEstado.enRevision.dbValue)
          .eq('partidos.organizador_id', uid);

      final list = (rows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final partidoEmbed = SupabaseParse.mapEmbed(map['partidos']);
        final profile = SupabaseParse.mapEmbed(map['profiles']);
        return DetallePartido.fromSupabaseMap(
          map,
          nombreJugador: SupabaseParse.toStringOrNull(profile?['nombre']),
          fechaPartido: SupabaseParse.toDateTime(partidoEmbed?['fecha']),
          recintoPartido: SupabaseParse.toStringOrNull(partidoEmbed?['recinto']),
          sportType: SportType.fromDb(
            SupabaseParse.toStringOrNull(partidoEmbed?['sport_type']),
          ),
          organizadorId:
              SupabaseParse.toStringOrNull(partidoEmbed?['organizador_id']),
        );
      }).where((d) => d.comprobantePendienteValidacion).toList();

      list.sort((a, b) {
        final fa = a.fechaPartido ?? DateTime.fromMillisecondsSinceEpoch(0);
        final fb = b.fechaPartido ?? DateTime.fromMillisecondsSinceEpoch(0);
        return fb.compareTo(fa);
      });
      return list;
    });
  }

  /// Historial de fotos de pago/abono de un detalle (no se pisan entre sí).
  Future<List<ComprobantePago>> getComprobantesPagoByDetalle(int detalleId) {
    return SupabaseHelpers.guard('Historial comprobantes', () async {
      final rows = await _client
          .from('comprobantes_pago')
          .select()
          .eq('detalle_id', detalleId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map(
            (row) => ComprobantePago.fromSupabaseMap(
              Map<String, dynamic>.from(row),
            ),
          )
          .where((c) => c.storagePath.trim().isNotEmpty)
          .toList();
    });
  }

  Future<({DatosPagoOrganizador pago, String organizadorNombre})?>
      getDatosPagoOrganizador(String organizadorId) async {
    if (organizadorId.isEmpty) return null;
    return SupabaseHelpers.guard('Datos pago organizador', () async {
      final raw = await _client.rpc(
        'get_datos_pago_organizador',
        params: {'p_organizador_id': organizadorId},
      );
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      if (map['ok'] != true) return null;
      final pago = DatosPagoOrganizador.fromMap(map);
      final nombre =
          SupabaseParse.toStringOrNull(map['organizador_nombre']) ?? '';
      return (pago: pago, organizadorNombre: nombre);
    });
  }

  Future<void> guardarDatosPagoOrganizador({
    required String titular,
    required String detalle,
    required String nota,
  }) {
    return SupabaseHelpers.write('Guardar datos pago', () async {
      await _client.rpc(
        'guardar_datos_pago_organizador',
        params: {
          'p_titular': titular,
          'p_detalle': detalle,
          'p_nota': nota,
        },
      );
    });
  }
}
