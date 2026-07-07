import '../utils/formatters.dart';
import 'cobro_logic.dart';

/// Tipos de inconsistencia detectables en datos históricos de cobro.
enum CobroInconsistenciaTipo {
  partidoSinHistorial,
  detalleSinSnapshotHistorico,
  saldoAcumuladoDifiereHistorial,
  historialMovimientoIncoherente,
  historialCadenaRota,
  historialDetalleDesalineado,
  historialSnapshotDuplicado,
  montoPagadoSuperaCargoAsignado,
  pagadoContradiceCobroLogic,
  valorImposible,
}

extension CobroInconsistenciaTipoLabel on CobroInconsistenciaTipo {
  String get etiqueta => switch (this) {
        CobroInconsistenciaTipo.partidoSinHistorial =>
          'Partido con detalles sin historial',
        CobroInconsistenciaTipo.detalleSinSnapshotHistorico =>
          'Detalle sin snapshot en saldos_historicos',
        CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial =>
          'saldo_acumulado difiere del historial',
        CobroInconsistenciaTipo.historialMovimientoIncoherente =>
          'Movimiento histórico incoherente',
        CobroInconsistenciaTipo.historialCadenaRota =>
          'Cadena de saldos históricos rota',
        CobroInconsistenciaTipo.historialDetalleDesalineado =>
          'Historial y detalle desalineados',
        CobroInconsistenciaTipo.historialSnapshotDuplicado =>
          'Snapshot histórico duplicado por partido/jugador',
        CobroInconsistenciaTipo.montoPagadoSuperaCargoAsignado =>
          'monto_pagado supera cargo asignado (total)',
        CobroInconsistenciaTipo.pagadoContradiceCobroLogic =>
          'pagado contradice CobroLogic',
        CobroInconsistenciaTipo.valorImposible => 'Valor imposible',
      };
}

/// Fila de detalle_partido para diagnóstico (solo lectura).
class DiagnosticoDetalleInput {
  final int? detalleId;
  final int partidoId;
  final String jugadorId;
  final String? jugadorNombre;
  final bool asistio;
  final double total;
  final double montoPagado;
  final bool pagado;

  const DiagnosticoDetalleInput({
    this.detalleId,
    required this.partidoId,
    required this.jugadorId,
    this.jugadorNombre,
    this.asistio = true,
    required this.total,
    required this.montoPagado,
    required this.pagado,
  });
}

/// Fila de saldos_historicos para diagnóstico (solo lectura).
class DiagnosticoHistorialInput {
  final int? historialId;
  final String jugadorId;
  final String? jugadorNombre;
  final int? partidoId;
  final double saldoAnterior;
  final double cargoPartido;
  final double abono;
  final double saldoNuevo;
  final DateTime fecha;
  final String concepto;

  const DiagnosticoHistorialInput({
    this.historialId,
    required this.jugadorId,
    this.jugadorNombre,
    this.partidoId,
    required this.saldoAnterior,
    required this.cargoPartido,
    required this.abono,
    required this.saldoNuevo,
    required this.fecha,
    required this.concepto,
  });

  bool get esSnapshotPartido =>
      partidoId != null && cargoPartido > 0.005;
}

/// Jugador con saldo actual para comparar contra historial.
class DiagnosticoJugadorInput {
  final String jugadorId;
  final String? nombre;
  final double saldoAcumulado;

  const DiagnosticoJugadorInput({
    required this.jugadorId,
    this.nombre,
    required this.saldoAcumulado,
  });
}

/// Una inconsistencia detectada.
class CobroInconsistencia {
  final CobroInconsistenciaTipo tipo;
  final int? detalleId;
  final int? historialId;
  final int? partidoId;
  final String? jugadorId;
  final String? jugadorNombre;
  final String mensaje;
  final Map<String, Object?> datos;

  const CobroInconsistencia({
    required this.tipo,
    this.detalleId,
    this.historialId,
    this.partidoId,
    this.jugadorId,
    this.jugadorNombre,
    required this.mensaje,
    this.datos = const {},
  });
}

/// Reporte agregado de diagnóstico (solo lectura).
class CobroDiagnosticoReporte {
  final List<CobroInconsistencia> inconsistencias;
  final DateTime generadoEn;

  const CobroDiagnosticoReporte({
    required this.inconsistencias,
    required this.generadoEn,
  });

  int get total => inconsistencias.length;

  bool get tieneProblemas => inconsistencias.isNotEmpty;

  Map<CobroInconsistenciaTipo, int> get conteoPorTipo {
    final map = <CobroInconsistenciaTipo, int>{};
    for (final i in inconsistencias) {
      map[i.tipo] = (map[i.tipo] ?? 0) + 1;
    }
    return map;
  }

  Set<int> get partidosAfectados => inconsistencias
      .map((i) => i.partidoId)
      .whereType<int>()
      .toSet();

  Set<String> get jugadoresAfectados => inconsistencias
      .map((i) => i.jugadorId)
      .whereType<String>()
      .toSet();

  String resumenTexto() {
    final buf = StringBuffer()
      ..writeln('Diagnóstico SSOT de cobros')
      ..writeln('Generado: ${generadoEn.toIso8601String()}')
      ..writeln('Total inconsistencias: $total')
      ..writeln('Partidos afectados: ${partidosAfectados.length}')
      ..writeln('Jugadores afectados: ${jugadoresAfectados.length}')
      ..writeln();

    final porTipo = conteoPorTipo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (porTipo.isNotEmpty) {
      buf.writeln('Por tipo:');
      for (final e in porTipo) {
        buf.writeln('  - ${e.key.etiqueta}: ${e.value}');
      }
      buf.writeln();
    }

    for (final i in inconsistencias) {
      buf.writeln('[${i.tipo.etiqueta}] ${i.mensaje}');
      if (i.partidoId != null) buf.writeln('  partido: ${i.partidoId}');
      if (i.jugadorId != null) {
        buf.writeln(
          '  jugador: ${i.jugadorNombre ?? i.jugadorId} (${i.jugadorId})',
        );
      }
      if (i.detalleId != null) buf.writeln('  detalle_id: ${i.detalleId}');
      if (i.historialId != null) {
        buf.writeln('  historial_id: ${i.historialId}');
      }
      if (i.datos.isNotEmpty) buf.writeln('  datos: ${i.datos}');
      buf.writeln();
    }
    return buf.toString();
  }
}

/// Motor de diagnóstico histórico de cobros. Solo lectura; no repara datos.
class CobroDiagnostico {
  CobroDiagnostico._();

  static const _tol = 0.005;

  static CobroDiagnosticoReporte analizar({
    required List<DiagnosticoDetalleInput> detalles,
    required List<DiagnosticoHistorialInput> historial,
    required List<DiagnosticoJugadorInput> jugadores,
  }) {
    final issues = <CobroInconsistencia>[];

    final historialPorPartido = <int, List<DiagnosticoHistorialInput>>{};
    final snapshotsPorPartidoJugador =
        <String, List<DiagnosticoHistorialInput>>{};
    final historialPorJugador = <String, List<DiagnosticoHistorialInput>>{};

    for (final h in historial) {
      historialPorJugador.putIfAbsent(h.jugadorId, () => []).add(h);
      final pid = h.partidoId;
      if (pid != null) {
        historialPorPartido.putIfAbsent(pid, () => []).add(h);
        if (h.esSnapshotPartido) {
          final key = CobroLogic.claveSnapshotPartidoJugador(
            partidoId: pid,
            jugadorId: h.jugadorId,
          );
          snapshotsPorPartidoJugador.putIfAbsent(key, () => []).add(h);
        }
      }
    }

    final detallesAsistioPorPartido = <int, List<DiagnosticoDetalleInput>>{};
    for (final d in detalles) {
      if (!d.asistio) continue;
      detallesAsistioPorPartido.putIfAbsent(d.partidoId, () => []).add(d);
    }

    // 1. Partidos con detalles pero sin historial del partido.
    for (final entry in detallesAsistioPorPartido.entries) {
      final partidoId = entry.key;
      if ((historialPorPartido[partidoId] ?? const []).isEmpty) {
        issues.add(
          CobroInconsistencia(
            tipo: CobroInconsistenciaTipo.partidoSinHistorial,
            partidoId: partidoId,
            mensaje:
                'Partido $partidoId tiene ${entry.value.length} asistente(s) '
                'sin ninguna fila en saldos_historicos',
            datos: {'asistentes': entry.value.length},
          ),
        );
      }
    }

    // Snapshots duplicados.
    for (final entry in snapshotsPorPartidoJugador.entries) {
      if (entry.value.length <= 1) continue;
      final h = entry.value.first;
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.historialSnapshotDuplicado,
          partidoId: h.partidoId,
          jugadorId: h.jugadorId,
          jugadorNombre: h.jugadorNombre,
          mensaje:
              'Hay ${entry.value.length} snapshots de cargo para '
              'partido ${h.partidoId} / jugador ${h.jugadorId}',
          datos: {
            'historial_ids':
                entry.value.map((x) => x.historialId).whereType<int>().toList(),
          },
        ),
      );
    }

    // 2–4. Por detalle asistente.
    for (final d in detalles.where((x) => x.asistio)) {
      _revisarValoresImposiblesDetalle(d, issues);
      _revisarMontoPagadoSuperaCargo(d, issues);

      final key = CobroLogic.claveSnapshotPartidoJugador(
        partidoId: d.partidoId,
        jugadorId: d.jugadorId,
      );
      final snapshots = snapshotsPorPartidoJugador[key] ?? const [];

      if (snapshots.isEmpty) {
        issues.add(
          CobroInconsistencia(
            tipo: CobroInconsistenciaTipo.detalleSinSnapshotHistorico,
            detalleId: d.detalleId,
            partidoId: d.partidoId,
            jugadorId: d.jugadorId,
            jugadorNombre: d.jugadorNombre,
            mensaje:
                'Detalle sin snapshot: partido ${d.partidoId}, '
                'jugador ${d.jugadorNombre ?? d.jugadorId}',
          ),
        );
        continue;
      }

      final snap = snapshots.first;
      _revisarAlineacionHistorialDetalle(d, snap, issues);
      _revisarPagadoVsCobroLogic(d, snap.saldoAnterior, issues);
    }

    // Historial: coherencia de cada movimiento y cadena por jugador.
    for (final entry in historialPorJugador.entries) {
      final rows = List<DiagnosticoHistorialInput>.from(entry.value)
        ..sort((a, b) {
          final cmp = a.fecha.compareTo(b.fecha);
          if (cmp != 0) return cmp;
          return (a.historialId ?? 0).compareTo(b.historialId ?? 0);
        });

      double? saldoPrevio;
      for (final h in rows) {
        _revisarValoresImposiblesHistorial(h, issues);
        _revisarMovimientoHistorial(h, issues);

        if (saldoPrevio != null &&
            (h.saldoAnterior - saldoPrevio).abs() > _tol) {
          issues.add(
            CobroInconsistencia(
              tipo: CobroInconsistenciaTipo.historialCadenaRota,
              historialId: h.historialId,
              partidoId: h.partidoId,
              jugadorId: h.jugadorId,
              jugadorNombre: h.jugadorNombre,
              mensaje:
                  'saldo_anterior ${h.saldoAnterior} no encadena con '
                  'saldo_nuevo previo $saldoPrevio',
              datos: {
                'saldo_anterior': h.saldoAnterior,
                'saldo_nuevo_previo': saldoPrevio,
              },
            ),
          );
        }
        saldoPrevio = h.saldoNuevo;
      }
    }

    // 3. saldo_acumulado vs último saldo_nuevo del historial.
    final saldoEsperadoPorJugador = <String, double>{};
    for (final entry in historialPorJugador.entries) {
      final rows = entry.value.toList()
        ..sort((a, b) {
          final cmp = a.fecha.compareTo(b.fecha);
          if (cmp != 0) return cmp;
          return (a.historialId ?? 0).compareTo(b.historialId ?? 0);
        });
      if (rows.isNotEmpty) {
        saldoEsperadoPorJugador[entry.key] = rows.last.saldoNuevo;
      }
    }

    for (final j in jugadores) {
      final esperado = saldoEsperadoPorJugador[j.jugadorId];
      if (esperado == null) {
        if (j.saldoAcumulado.abs() > _tol) {
          issues.add(
            CobroInconsistencia(
              tipo: CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial,
              jugadorId: j.jugadorId,
              jugadorNombre: j.nombre,
              mensaje:
                  'Jugador ${j.nombre ?? j.jugadorId} tiene saldo '
                  '${j.saldoAcumulado} sin movimientos en historial',
              datos: {
                'saldo_acumulado': j.saldoAcumulado,
                'saldo_esperado_historial': 0,
              },
            ),
          );
        }
        continue;
      }

      if ((j.saldoAcumulado - esperado).abs() > _tol) {
        issues.add(
          CobroInconsistencia(
            tipo: CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial,
            jugadorId: j.jugadorId,
            jugadorNombre: j.nombre,
            mensaje:
                'saldo_acumulado ${j.saldoAcumulado} ≠ '
                'último saldo_nuevo histórico $esperado',
            datos: {
              'saldo_acumulado': j.saldoAcumulado,
              'saldo_esperado_historial': esperado,
              'diferencia':
                  roundMoney(j.saldoAcumulado - esperado).toDouble(),
            },
          ),
        );
      }
    }

    return CobroDiagnosticoReporte(
      inconsistencias: issues,
      generadoEn: DateTime.now(),
    );
  }

  static void _revisarValoresImposiblesDetalle(
    DiagnosticoDetalleInput d,
    List<CobroInconsistencia> issues,
  ) {
    if (d.total < -_tol) {
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.valorImposible,
          detalleId: d.detalleId,
          partidoId: d.partidoId,
          jugadorId: d.jugadorId,
          jugadorNombre: d.jugadorNombre,
          mensaje: 'total negativo (${d.total}) en detalle',
          datos: {'total': d.total},
        ),
      );
    }
    if (d.montoPagado < -_tol) {
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.valorImposible,
          detalleId: d.detalleId,
          partidoId: d.partidoId,
          jugadorId: d.jugadorId,
          jugadorNombre: d.jugadorNombre,
          mensaje: 'monto_pagado negativo (${d.montoPagado})',
          datos: {'monto_pagado': d.montoPagado},
        ),
      );
    }
  }

  static void _revisarValoresImposiblesHistorial(
    DiagnosticoHistorialInput h,
    List<CobroInconsistencia> issues,
  ) {
    if (h.cargoPartido < -_tol || h.abono < -_tol) {
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.valorImposible,
          historialId: h.historialId,
          partidoId: h.partidoId,
          jugadorId: h.jugadorId,
          jugadorNombre: h.jugadorNombre,
          mensaje:
              'cargo o abono negativo (cargo=${h.cargoPartido}, abono=${h.abono})',
        ),
      );
    }
  }

  static void _revisarMontoPagadoSuperaCargo(
    DiagnosticoDetalleInput d,
    List<CobroInconsistencia> issues,
  ) {
    if (d.montoPagado > d.total + _tol) {
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.montoPagadoSuperaCargoAsignado,
          detalleId: d.detalleId,
          partidoId: d.partidoId,
          jugadorId: d.jugadorId,
          jugadorNombre: d.jugadorNombre,
          mensaje:
              'monto_pagado ${d.montoPagado} > total asignado ${d.total}',
          datos: {
            'monto_pagado': d.montoPagado,
            'total': d.total,
          },
        ),
      );
    }
  }

  static void _revisarMovimientoHistorial(
    DiagnosticoHistorialInput h,
    List<CobroInconsistencia> issues,
  ) {
    final esperado = CobroLogic.saldoTrasMovimiento(
      saldoAnterior: h.saldoAnterior,
      cargoPartido: h.cargoPartido,
      montoPagado: h.abono,
    );
    if ((h.saldoNuevo - esperado).abs() > _tol) {
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.historialMovimientoIncoherente,
          historialId: h.historialId,
          partidoId: h.partidoId,
          jugadorId: h.jugadorId,
          jugadorNombre: h.jugadorNombre,
          mensaje:
              'saldo_nuevo ${h.saldoNuevo} ≠ esperado $esperado '
              '(saldo_anterior=${h.saldoAnterior}, '
              'cargo=${h.cargoPartido}, abono=${h.abono})',
          datos: {
            'saldo_nuevo': h.saldoNuevo,
            'saldo_nuevo_esperado': esperado,
          },
        ),
      );
    }
  }

  static void _revisarAlineacionHistorialDetalle(
    DiagnosticoDetalleInput d,
    DiagnosticoHistorialInput snap,
    List<CobroInconsistencia> issues,
  ) {
    final cargoDiff = (snap.cargoPartido - d.total).abs();
    final abonoDiff = (snap.abono - d.montoPagado).abs();
    if (cargoDiff > _tol || abonoDiff > _tol) {
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.historialDetalleDesalineado,
          detalleId: d.detalleId,
          historialId: snap.historialId,
          partidoId: d.partidoId,
          jugadorId: d.jugadorId,
          jugadorNombre: d.jugadorNombre,
          mensaje:
              'Snapshot histórico no coincide con detalle '
              '(cargo hist=${snap.cargoPartido} vs total=${d.total}, '
              'abono hist=${snap.abono} vs monto_pagado=${d.montoPagado})',
          datos: {
            'cargo_historial': snap.cargoPartido,
            'total_detalle': d.total,
            'abono_historial': snap.abono,
            'monto_pagado_detalle': d.montoPagado,
          },
        ),
      );
    }
  }

  static void _revisarPagadoVsCobroLogic(
    DiagnosticoDetalleInput d,
    double snapshotSaldoAnterior,
    List<CobroInconsistencia> issues,
  ) {
    final cerrado = CobroLogic.partidoEstaCerrado(
      saldoAnteriorAlPartido: snapshotSaldoAnterior,
      cargoPartido: d.total,
      montoPagadoEnPartido: d.montoPagado,
    );
    if (d.pagado != cerrado) {
      issues.add(
        CobroInconsistencia(
          tipo: CobroInconsistenciaTipo.pagadoContradiceCobroLogic,
          detalleId: d.detalleId,
          partidoId: d.partidoId,
          jugadorId: d.jugadorId,
          jugadorNombre: d.jugadorNombre,
          mensaje:
              'pagado=${d.pagado} pero CobroLogic.partidoEstaCerrado=$cerrado',
          datos: {
            'pagado': d.pagado,
            'partido_cerrado_neto': cerrado,
            'snapshot_saldo_anterior': snapshotSaldoAnterior,
            'total': d.total,
            'monto_pagado': d.montoPagado,
          },
        ),
      );
    }
  }
}
