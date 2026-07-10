import '../domain/organizer_cycle_logic.dart';
import '../domain/estado_partido_publico.dart';
import '../domain/partido_lifecycle.dart';
import '../models/detalle_partido.dart';
import '../models/mi_convocatoria.dart';
import '../models/convocatoria_jugador.dart';
import '../repositories/partido_repository.dart';

/// Acciones pendientes en el modo jugador (deudas + convocatorias por responder).
int playerModePendingCount({
  required List<DetallePartido> misDeudas,
  required List<MiConvocatoria> misInvitaciones,
}) {
  var count = 0;
  if (misDeudas.isNotEmpty) count += 1;
  count += misInvitaciones.where((c) => c.requiereRespuesta).length;
  return count;
}

/// Acciones pendientes en el modo organizador (convocatorias, cobros, validaciones).
int organizerModePendingCount({
  required List<ConvocatoriaCompleta> convocatorias,
  required List<PartidoCompleto> partidosJugadosRecientes,
  required List<DetallePartido> pagosPorValidar,
}) {
  var count = 0;

  count += convocatorias
      .where(
        (c) =>
            PartidoLifecycle.situacionOrganizador(c) ==
            ConvocatoriaOrganizadorSituacion.sinResolver,
      )
      .length;

  count += convocatorias
      .where(
        (c) =>
            PartidoLifecycle.situacionOrganizador(c) ==
            ConvocatoriaOrganizadorSituacion.listoParaGastos,
      )
      .length;

  count += convocatorias.where((c) {
    final estado = PartidoEstadoPublicoView.resolve(c).estado;
    return estado == EstadoPartidoPublico.enEvaluacion ||
        estado == EstadoPartidoPublico.reprogramado;
  }).length;

  for (final c in convocatorias.where((c) {
    final estado = PartidoEstadoPublicoView.resolve(c).estado;
    return estado == EstadoPartidoPublico.esperandoConfirmaciones;
  })) {
    final cupos = c.partido.cuposMax;
    final faltan =
        cupos > 0 ? (cupos - c.confirmados).clamp(0, cupos) : 0;
    if (c.pendientes > 0 || faltan > 0) count += 1;
  }

  if (partidoConCobrosPendientes(partidosJugadosRecientes) != null) {
    count += 1;
  }

  count += pagosPorValidar
      .where((d) => d.comprobantePendienteValidacion)
      .length;

  return count;
}
