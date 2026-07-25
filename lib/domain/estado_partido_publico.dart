import 'package:flutter/material.dart';

import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/mi_convocatoria.dart';
import 'partido_lifecycle.dart';
import 'convocatoria_cupo_logic.dart';

/// Estados oficiales visibles para organizador y jugador (mismo idioma en toda la app).
enum EstadoPartidoPublico {
  confirmado,
  esperandoConfirmaciones,
  enEvaluacion,
  reprogramado,
  cancelado,
  jugado,
}

/// Ventana antes del partido para pasar a [EstadoPartidoPublico.enEvaluacion].
const Duration kPartidoEvaluacionAntes = Duration(hours: 6);

class PartidoEstadoPublicoView {
  final EstadoPartidoPublico estado;
  final int confirmados;
  final int cuposMax;
  final int pendientes;
  final int faltan;
  final bool cupoImposible;

  const PartidoEstadoPublicoView({
    required this.estado,
    required this.confirmados,
    required this.cuposMax,
    required this.pendientes,
    required this.faltan,
    this.cupoImposible = false,
  });

  bool get cupoCompleto => cuposMax > 0 && confirmados >= cuposMax;

  String get emoji => switch (estado) {
        EstadoPartidoPublico.confirmado => '🟢',
        EstadoPartidoPublico.esperandoConfirmaciones => '🟡',
        EstadoPartidoPublico.enEvaluacion => '🟠',
        EstadoPartidoPublico.reprogramado => '🔵',
        EstadoPartidoPublico.cancelado => '⚫',
        EstadoPartidoPublico.jugado => '🏁',
      };

  Color get accentColor => switch (estado) {
        EstadoPartidoPublico.confirmado => const Color(0xFF15803D),
        EstadoPartidoPublico.esperandoConfirmaciones => const Color(0xFFCA8A04),
        EstadoPartidoPublico.enEvaluacion => const Color(0xFFEA580C),
        EstadoPartidoPublico.reprogramado => const Color(0xFF2563EB),
        EstadoPartidoPublico.cancelado => const Color(0xFF525252),
        EstadoPartidoPublico.jugado => const Color(0xFF64748B),
      };

  static PartidoEstadoPublicoView resolve(
    ConvocatoriaCompleta convocatoria, [
    DateTime? reference,
  ]) {
    final ref = reference ?? DateTime.now();
    final partido = convocatoria.partido;
    final confirmados = convocatoria.confirmados;
    final pendientes = convocatoria.pendientes;
    final cupos = partido.cuposMax;
    final faltan = cupos > 0 ? (cupos - confirmados).clamp(0, cupos) : 0;

    if (partido.esCancelado) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.cancelado,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: faltan,
      );
    }

    if (partido.estado == EstadoPartido.jugado) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.jugado,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: faltan,
      );
    }

    final futuro = partido.fecha.isAfter(ref);
    final expirada = PartidoLifecycle.convocatoriaExpirada(partido, ref);

    final enviada = convocatoria.convocatoriaEnviada;

    if (partido.reprogramadoEn != null && futuro && faltan > 0) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.reprogramado,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: faltan,
      );
    }

    if (futuro && faltan == 0) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.confirmado,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: 0,
      );
    }

    if (futuro && faltan > 0) {
      if (ConvocatoriaCupoLogic.cupoImposible(convocatoria, ref)) {
        return PartidoEstadoPublicoView(
          estado: EstadoPartidoPublico.enEvaluacion,
          confirmados: confirmados,
          cuposMax: cupos,
          pendientes: pendientes,
          faltan: faltan,
          cupoImposible: true,
        );
      }
      final restante = partido.fecha.difference(ref);
      final evaluacion =
          enviada && restante <= kPartidoEvaluacionAntes;
      return PartidoEstadoPublicoView(
        estado: evaluacion
            ? EstadoPartidoPublico.enEvaluacion
            : EstadoPartidoPublico.esperandoConfirmaciones,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: faltan,
      );
    }

    if (expirada && PartidoLifecycle.evidenciaPartidoJugado(convocatoria, ref)) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.jugado,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: faltan,
      );
    }

    if (expirada && faltan > 0) {
      return PartidoEstadoPublicoView(
        estado: enviada
            ? EstadoPartidoPublico.enEvaluacion
            : EstadoPartidoPublico.esperandoConfirmaciones,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: faltan,
      );
    }

    if (expirada) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.jugado,
        confirmados: confirmados,
        cuposMax: cupos,
        pendientes: pendientes,
        faltan: faltan,
      );
    }

    return PartidoEstadoPublicoView(
      estado: EstadoPartidoPublico.esperandoConfirmaciones,
      confirmados: confirmados,
      cuposMax: cupos,
      pendientes: pendientes,
      faltan: faltan,
    );
  }

  static PartidoEstadoPublicoView? resolveJugador(
    MiConvocatoria convocatoria,
    ConvocatoriaCompleta? completa, [
    DateTime? reference,
  ]) {
    if (completa != null) {
      return resolve(completa, reference);
    }
    final p = convocatoria.partido;
    if (p.esCancelado) {
      return const PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.cancelado,
        confirmados: 0,
        cuposMax: 0,
        pendientes: 0,
        faltan: 0,
      );
    }
    if (p.estado == EstadoPartido.jugado) {
      return const PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.jugado,
        confirmados: 0,
        cuposMax: 0,
        pendientes: 0,
        faltan: 0,
      );
    }

    if (convocatoria.esReprogramadoPendiente) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.reprogramado,
        confirmados: 0,
        cuposMax: p.cuposMax,
        pendientes: 1,
        faltan: p.cuposMax,
      );
    }

    // Sin roster: la confirmación PERSONAL no implica encuentro completo.
    // Nunca inventar confirmados = cuposMax ni estado confirmado.
    if (convocatoria.estaConfirmado) {
      final cupos = p.cuposMax;
      final faltan = cupos > 0 ? (cupos - 1).clamp(0, cupos) : 0;
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.esperandoConfirmaciones,
        confirmados: 1,
        cuposMax: cupos,
        pendientes: 0,
        faltan: faltan,
      );
    }
    if (convocatoria.requiereRespuesta) {
      return PartidoEstadoPublicoView(
        estado: EstadoPartidoPublico.esperandoConfirmaciones,
        confirmados: 0,
        cuposMax: p.cuposMax,
        pendientes: 1,
        faltan: p.cuposMax,
      );
    }
    return null;
  }
}
