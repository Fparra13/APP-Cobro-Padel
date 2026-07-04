import '../core/supabase_helpers.dart';
import '../models/estadisticas_jugador.dart';
import '../repositories/ranking_repository.dart';

/// Estadísticas calculadas en cliente desde Supabase.
class EstadisticasRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<List<EstadisticasJugador>> getAll() async {
    return SupabaseHelpers.guard('Estadísticas jugadores', () async {
      final profiles = await _client.from('profiles').select();
      if ((profiles as List).isEmpty) return [];

      // 3 consultas en total (antes: 1 + 2 por jugador).
      final results = await Future.wait([
        _client
            .from('detalles_partido')
            .select(
              'pagado, total, fecha_pago, jugador_id, partidos!inner(fecha)',
            )
            .eq('asistio', true),
        _client
            .from('convocatoria_jugadores')
            .select('jugador_id')
            .eq('estado_confirmacion', 'confirmado'),
      ]);

      final detallesPorJugador = <String, List<Map<String, dynamic>>>{};
      for (final row in results[0] as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final jugadorId = map['jugador_id'] as String?;
        if (jugadorId == null) continue;
        detallesPorJugador.putIfAbsent(jugadorId, () => []).add(map);
      }

      final convPorJugador = <String, int>{};
      for (final row in results[1] as List) {
        final jugadorId = (row as Map)['jugador_id'] as String?;
        if (jugadorId == null) continue;
        convPorJugador[jugadorId] = (convPorJugador[jugadorId] ?? 0) + 1;
      }

      final limite90 = DateTime.now().subtract(const Duration(days: 90));
      final stats = <EstadisticasJugador>[];

      for (final profile in profiles as List) {
        final jugadorId = profile['id'] as String;
        final detalles = detallesPorJugador[jugadorId] ?? const [];

        var pagosAlDia = 0;
        var pagosTardios = 0;
        var impagos = 0;
        var totalGastado = 0.0;
        var partidos90 = 0;
        final diasPago = <double>[];

        for (final d in detalles) {
          totalGastado += (d['total'] as num?)?.toDouble() ?? 0;
          final partido = d['partidos'] as Map<String, dynamic>?;
          final fechaPartido = partido == null
              ? null
              : DateTime.tryParse(partido['fecha'] as String? ?? '');
          if (fechaPartido != null && !fechaPartido.isBefore(limite90)) {
            partidos90++;
          }

          final pagado = d['pagado'] == true;
          if (!pagado) {
            impagos++;
            continue;
          }
          if (fechaPartido == null) continue;
          final fechaPagoStr = d['fecha_pago'] as String?;
          final fechaPago = fechaPagoStr != null
              ? DateTime.tryParse(fechaPagoStr) ?? fechaPartido
              : fechaPartido;
          final dias = fechaPago.difference(fechaPartido).inDays;
          diasPago.add(dias.toDouble());
          if (dias <= 1) {
            pagosAlDia++;
          } else {
            pagosTardios++;
          }
        }

        stats.add(EstadisticasJugador(
          jugadorId: 0,
          jugadorKeyId: jugadorId,
          nombre: profile['nombre'] as String,
          fotoUrl: profile['foto_url'] as String?,
          partidosJugados: detalles.length,
          pagosAlDia: pagosAlDia,
          pagosTardios: pagosTardios,
          partidosImpagos: impagos,
          promedioDiasPago: diasPago.isEmpty
              ? 0
              : diasPago.reduce((a, b) => a + b) / diasPago.length,
          totalGastado: totalGastado,
          saldoActual: (profile['saldo_acumulado'] as num?)?.toDouble() ?? 0,
          convocatoriasConfirmadas: convPorJugador[jugadorId] ?? 0,
          partidosUltimos90Dias: partidos90,
        ));
      }

      stats.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
      return stats;
    });
  }

  List<EstadisticasJugador> masParticipacion(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.partidosJugados > 0).toList()
      ..sort((a, b) => b.partidosJugados.compareTo(a.partidosJugados));
    return copy;
  }

  List<EstadisticasJugador> mejoresPagadores(List<EstadisticasJugador> all) {
    final copy = all
        .where((e) => e.pagosAlDia > 0 && e.partidosImpagos == 0)
        .toList()
      ..sort((a, b) => b.scoreBuenPagador.compareTo(a.scoreBuenPagador));
    return copy;
  }

  List<EstadisticasJugador> pagadoresRapidos(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.partidosJugados > 0).toList()
      ..sort((a, b) => a.promedioDiasPago.compareTo(b.promedioDiasPago));
    return copy;
  }

  List<EstadisticasJugador> masActivosRecientes(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.partidosUltimos90Dias > 0).toList()
      ..sort(
        (a, b) =>
            b.partidosUltimos90Dias.compareTo(a.partidosUltimos90Dias),
      );
    return copy;
  }

  List<EstadisticasJugador> reyConvocatoria(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.convocatoriasConfirmadas > 0).toList()
      ..sort(
        (a, b) =>
            b.convocatoriasConfirmadas.compareTo(a.convocatoriasConfirmadas),
      );
    return copy;
  }

  List<EstadisticasJugador> masAportado(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.totalGastado > 0).toList()
      ..sort((a, b) => b.totalGastado.compareTo(a.totalGastado));
    return copy;
  }

  List<EstadisticasJugador> mayorDeuda(List<EstadisticasJugador> all) {
    final copy = all.where((e) => e.saldoActual > 0).toList()
      ..sort((a, b) => b.saldoActual.compareTo(a.saldoActual));
    return copy;
  }
}

/// Ranking calculado en cliente desde Supabase.
class RankingRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<List<RankingJugador>> getRanking() async {
    return SupabaseHelpers.guard('Ranking jugadores', () async {
      final profiles = await _client.from('profiles').select();
      if ((profiles as List).isEmpty) return [];

      final detalleRows = await _client
          .from('detalles_partido')
          .select(
            'pagado, fecha_pago, jugador_id, partidos!inner(fecha)',
          )
          .eq('asistio', true);

      final detallesPorJugador = <String, List<Map<String, dynamic>>>{};
      for (final row in detalleRows as List) {
        final map = Map<String, dynamic>.from(row);
        final jugadorId = map['jugador_id'] as String;
        detallesPorJugador.putIfAbsent(jugadorId, () => []).add(map);
      }

      final rankings = <RankingJugador>[];
      for (final profile in profiles as List) {
        final jugadorId = profile['id'] as String;
        final detalles = detallesPorJugador[jugadorId];
        if (detalles == null || detalles.isEmpty) continue;

        var pagosAlDia = 0;
        var pagosTardios = 0;
        var impagos = 0;
        final diasPago = <double>[];

        for (final d in detalles) {
          final pagado = d['pagado'] == true;
          if (!pagado) {
            impagos++;
            continue;
          }
          final partido = d['partidos'] as Map<String, dynamic>;
          final fechaPartido = DateTime.parse(partido['fecha'] as String);
          final fechaPagoStr = d['fecha_pago'] as String?;
          final fechaPago =
              fechaPagoStr != null ? DateTime.parse(fechaPagoStr) : fechaPartido;
          final dias = fechaPago.difference(fechaPartido).inDays;
          diasPago.add(dias.toDouble());
          if (dias <= 1) {
            pagosAlDia++;
          } else {
            pagosTardios++;
          }
        }

        rankings.add(RankingJugador(
          jugadorId: 0,
          jugadorKeyId: jugadorId,
          nombre: profile['nombre'] as String,
          partidosJugados: detalles.length,
          pagosAlDia: pagosAlDia,
          pagosTardios: pagosTardios,
          partidosImpagos: impagos,
          promedioDiasPago: diasPago.isEmpty
              ? 0
              : diasPago.reduce((a, b) => a + b) / diasPago.length,
          saldoActual: (profile['saldo_acumulado'] as num?)?.toDouble() ?? 0,
        ));
      }

      rankings.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
      return rankings;
    });
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
