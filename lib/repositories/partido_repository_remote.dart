import '../core/supabase_helpers.dart';
import '../models/costo_variable.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/estado_partido.dart';
import '../models/partido.dart';
import '../repositories/jugador_repository_remote.dart';
import '../repositories/partido_repository.dart';
import '../services/calculation_service.dart';
import '../utils/formatters.dart';

typedef CostoVariableInput = ({
  String concepto,
  double montoTotal,
  List<String> jugadores,
  String? comprobanteUrl,
});

/// Partidos y cobros contra Supabase.
class PartidoRepositoryRemote {
  final _client = SupabaseHelpers.client;
  final _jugadorRepo = JugadorRepositoryRemote();

  Future<List<Partido>> getAll({EstadoPartido? soloEstado}) async {
    return SupabaseHelpers.guard('Listar partidos', () async {
      var query = _client.from('partidos').select();
      if (soloEstado != null) {
        query = query.eq('estado', soloEstado.dbValue);
      }
      final rows = await query.order('fecha', ascending: false);
      return (rows as List)
          .map((r) => Partido.fromSupabaseMap(Map<String, dynamic>.from(r)))
          .toList();
    });
  }

  Future<List<Partido>> getJugados() => getAll(soloEstado: EstadoPartido.jugado);

  Future<List<String>> getRecintosRecientes({int limit = 8}) async {
    return SupabaseHelpers.guard('Recintos recientes', () async {
      final rows = await _client
          .from('partidos')
          .select('recinto, fecha')
          .not('recinto', 'is', null)
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
    return SupabaseHelpers.guard('Obtener partido completo', () async {
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
      for (final costo in costos) {
        final rows = await _client
            .from('asignaciones_costo')
            .select()
            .eq('costo_variable_id', costo.id!);
        asignaciones[costo.id!] = (rows as List)
            .map(
              (r) => AsignacionCostoVariable.fromSupabaseMap(
                Map<String, dynamic>.from(r),
              ),
            )
            .toList();
      }

      return PartidoCompleto(
        partido: Partido.fromSupabaseMap(Map<String, dynamic>.from(partidoRow)),
        detalles: detalles,
        costosVariables: costos,
        asignacionesPorCosto: asignaciones,
      );
    });
  }

  Future<List<DesgloseJugador>> getDesglose(int partidoId) async {
    final completo = await getCompleto(partidoId);
    if (completo == null) return [];

    final histRows = await _client
        .from('saldos_historicos')
        .select('jugador_id, saldo_anterior')
        .eq('partido_id', partidoId);

    final saldosAnteriores = <String, double>{
      for (final h in histRows as List)
        h['jugador_id'] as String: (h['saldo_anterior'] as num).toDouble(),
    };

    final asistentes =
        completo.detalles.where((d) => d.asistio && d.jugadorSupabaseId != null);
    final n = asistentes.length;
    if (n == 0) return [];

    final canchaU = CalculationService.prorrateoCancha(
      costoCancha: completo.partido.costoCancha,
      cantidadAsistentes: n,
    );
    final pelotasU = CalculationService.prorrateoPelotas(
      costoPelotas: completo.partido.costoPelotas,
      cantidadAsistentes: n,
    );

    final varsPorJugador = <String, Map<String, double>>{};
    for (final d in asistentes) {
      varsPorJugador[d.jugadorSupabaseId!] = {};
    }

    for (final cv in completo.costosVariables) {
      final asignaciones = completo.asignacionesPorCosto[cv.id] ?? [];
      for (final a in asignaciones) {
        final jid = a.jugadorSupabaseId;
        if (jid != null && varsPorJugador.containsKey(jid)) {
          varsPorJugador[jid]![cv.concepto] = roundMoney(a.monto).toDouble();
        }
      }
    }

    return asistentes.map((d) {
      final jid = d.jugadorSupabaseId!;
      final saldoAnt = roundMoney(saldosAnteriores[jid] ?? 0).toDouble();
      final vars = varsPorJugador[jid] ?? {};
      final totalVars = vars.values.fold(0.0, (s, v) => s + v);
      final totalPartido = CalculationService.cargoPartido(
        prorrateoFijo: canchaU + pelotasU,
        totalVariables: totalVars,
      );
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

      return DesgloseJugador(
        jugadorSupabaseId: jid,
        nombre: d.nombreJugador ?? '',
        saldoAnterior: saldoAnt,
        cancha: canchaU,
        pelotas: pelotasU,
        variables: vars,
        totalPartido: totalPartido,
        totalDebido: totalDebido,
        montoPagado: montoPagado,
        saldoRestante: saldoRestante,
        pagado: d.pagado,
      );
    }).toList();
  }

  Future<List<ResumenJugador>> getResumenJugadores() async {
    final jugadores = await _jugadorRepo.getAll();
    final resumenes = <ResumenJugador>[];

    for (final jugador in jugadores) {
      final jid = jugador.supabaseId;
      if (jid == null) continue;

      final stats = await _client
          .from('detalles_partido')
          .select('total, pagado')
          .eq('jugador_id', jid)
          .eq('asistio', true);

      var partidos = 0;
      var pendiente = 0.0;
      for (final row in stats as List) {
        partidos++;
        if (row['pagado'] != true) {
          pendiente += (row['total'] as num).toDouble();
        }
      }

      resumenes.add(ResumenJugador(
        jugador: jugador,
        saldoActual: jugador.saldoAcumulado,
        partidosJugados: partidos,
        totalPendiente: pendiente,
      ));
    }

    resumenes.sort((a, b) => b.saldoActual.compareTo(a.saldoActual));
    return resumenes;
  }

  Future<PartidoCompleto?> getUltimoPartido() async {
    final partidos = await getJugados();
    if (partidos.isEmpty) return null;
    return getCompleto(partidos.first.id!);
  }

  Future<int> guardarPartido({
    required Partido partido,
    required List<String> jugadoresAsistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
    String? organizadorId,
  }) async {
    return SupabaseHelpers.guard('Guardar partido', () async {
      final asistentes = jugadoresAsistentes.toSet().toList();
      final prorrateo = CalculationService.prorrateoFijo(
        costoCancha: partido.costoCancha,
        costoPelotas: partido.costoPelotas,
        cantidadAsistentes: asistentes.length,
      );

      final variablesPorJugador = <String, double>{
        for (final id in asistentes) id: 0,
      };

      final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
      final partidoMap = partido.toSupabaseMap(organizadorId: orgId);
      partidoMap.remove('id');

      final partidoRow = await _client
          .from('partidos')
          .insert(partidoMap)
          .select('id')
          .single();
      final partidoId = (partidoRow['id'] as num).toInt();

      for (final cv in costosVariables) {
        final costoRow = await _client
            .from('costos_variables')
            .insert({
              'partido_id': partidoId,
              'concepto': cv.concepto,
              'monto_total': cv.montoTotal,
              'comprobante_url': cv.comprobanteUrl,
            })
            .select('id')
            .single();
        final costoId = (costoRow['id'] as num).toInt();

        final participantes =
            cv.jugadores.isEmpty ? asistentes : cv.jugadores.toSet().toList();
        final montoIndividual = participantes.isEmpty
            ? 0.0
            : CalculationService.prorratear(cv.montoTotal, participantes.length);

        for (final jugadorId in participantes) {
          await _client.from('asignaciones_costo').insert({
            'costo_variable_id': costoId,
            'jugador_id': jugadorId,
            'monto': montoIndividual,
          });
          variablesPorJugador[jugadorId] =
              (variablesPorJugador[jugadorId] ?? 0) + montoIndividual;
        }
      }

      final ahora = DateTime.now();
      for (final jugadorId in asistentes) {
        final jugador = await _jugadorRepo.getById(jugadorId);
        if (jugador == null) continue;

        final saldoAnterior = saldosAnterioresSnapshot?[jugadorId] ??
            jugador.saldoAcumulado;
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
        final concepto = pagado
            ? (montoPagado == 0 && favorAplicado > 0
                ? 'Partido cubierto con saldo a favor'
                : 'Partido pagado')
            : montoPagado > 0
                ? 'Pago parcial'
                : 'Deuda acumulada';

        await _client.from('detalles_partido').insert({
          'partido_id': partidoId,
          'jugador_id': jugadorId,
          'asistio': true,
          'prorrateo_fijo': prorrateo,
          'total_variables': totalVars,
          'total': cargo,
          'pagado': pagado,
          'monto_pagado': montoPagado,
          if (pagado || montoPagado > 0) 'fecha_pago': ahora.toIso8601String(),
        });

        await _jugadorRepo.updateSaldo(jugadorId, saldoNuevo);

        await _client.from('saldos_historicos').insert({
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
      }

      return partidoId;
    });
  }

  Future<void> eliminarPartido(int id) async {
    await SupabaseHelpers.guard('Eliminar partido', () async {
      await _client.from('partidos').delete().eq('id', id);
      await _recalcularSaldosDesdeHistorial();
    });
  }

  Future<void> registrarAbono({
    required String jugadorId,
    required double monto,
    String concepto = 'Abono manual',
  }) async {
    await SupabaseHelpers.guard('Registrar abono', () async {
      final jugador = await _jugadorRepo.getById(jugadorId);
      if (jugador == null) return;

      final saldoAnterior = jugador.saldoAcumulado;
      final saldoNuevo = roundMoney(saldoAnterior - monto).toDouble();
      final ahora = DateTime.now();

      await _jugadorRepo.updateSaldo(jugadorId, saldoNuevo);

      await _client.from('saldos_historicos').insert({
        'jugador_id': jugadorId,
        'saldo_anterior': saldoAnterior,
        'cargo_partido': 0,
        'abono': monto,
        'saldo_nuevo': saldoNuevo,
        'fecha': ahora.toIso8601String(),
        'concepto': concepto,
      });
    });
  }

  Future<void> _recalcularSaldosDesdeHistorial() async {
    final jugadores = await _jugadorRepo.getAll();
    for (final j in jugadores) {
      final jid = j.supabaseId;
      if (jid == null) continue;

      final rows = await _client
          .from('saldos_historicos')
          .select('saldo_nuevo')
          .eq('jugador_id', jid)
          .order('fecha', ascending: true)
          .order('id', ascending: true);

      var saldo = 0.0;
      for (final row in rows as List) {
        saldo = (row['saldo_nuevo'] as num).toDouble();
      }
      await _jugadorRepo.updateSaldo(jid, saldo);
    }
  }
}
