import '../domain/cobro_logic.dart';
import '../models/cobros_resumen.dart';
import '../models/detalle_partido.dart';
import '../repositories/partido_repository.dart';

/// Pendiente neto del cobro (descuenta saldo a favor del partido).
double pendienteOrganizadorDetalle(
  DetallePartido d, {
  double saldoAnteriorPartido = 0,
}) =>
    CobroLogic.obtenerPendientePartido(
      saldoAnteriorAlPartido: saldoAnteriorPartido,
      cargoPartido: d.total,
      montoPagadoEnPartido: d.montoPagado,
    );

/// Cobro del partido aún abierto para el organizador (deuda monetaria neta).
/// Los comprobantes por validar tienen su propia sección en el home.
bool detalleCobroOrganizadorPendiente(
  DetallePartido d, {
  double saldoAnteriorPartido = 0,
}) {
  if (!d.asistio) return false;

  final pendiente = pendienteOrganizadorDetalle(
    d,
    saldoAnteriorPartido: saldoAnteriorPartido,
  );
  if (pendiente <= 0.005) return false;

  // Comprobante pendiente cuando el partido ya está cubierto (neto).
  if (d.comprobantePendienteValidacion &&
      CobroLogic.partidoEstaCerrado(
        saldoAnteriorAlPartido: saldoAnteriorPartido,
        cargoPartido: d.total,
        montoPagadoEnPartido: d.montoPagado,
      )) {
    return false;
  }

  return true;
}

List<DetallePartido> cobrosOrganizadorPendientes(PartidoCompleto completo) =>
    completo.detalles
        .where(
          (d) => detalleCobroOrganizadorPendiente(
            d,
            saldoAnteriorPartido: completo.saldoAnteriorCobro(d),
          ),
        )
        .toList();

bool partidoOrganizadorCobrosCerrados(PartidoCompleto completo) {
  if (completo.detalles.isEmpty) return false;
  return cobrosOrganizadorPendientes(completo).isEmpty;
}

List<PartidoCompleto> partidosConCobrosPendientes(
  List<PartidoCompleto> partidosRecientes,
) =>
    partidosRecientes
        .where((pc) => cobrosOrganizadorPendientes(pc).isNotEmpty)
        .toList();

double montoPendientePartido(PartidoCompleto completo) =>
    cobrosOrganizadorPendientes(completo).fold<double>(
      0,
      (s, d) =>
          s +
          pendienteOrganizadorDetalle(
            d,
            saldoAnteriorPartido: completo.saldoAnteriorCobro(d),
          ),
    );

/// Partido más antiguo con cobros abiertos (prioridad para cobrar).
PartidoCompleto? partidoConCobrosPendientes(
  List<PartidoCompleto> partidosRecientes,
) {
  final pendientes = partidosConCobrosPendientes(partidosRecientes);
  if (pendientes.isEmpty) return null;
  pendientes.sort((a, b) => a.partido.fecha.compareTo(b.partido.fecha));
  return pendientes.first;
}

@Deprecated('Usar deudaTotalGrupo(resumenes) para total del grupo')
double montoTotalCobrosPendientes(List<PartidoCompleto> partidosRecientes) {
  var total = 0.0;
  for (final pc in partidosConCobrosPendientes(partidosRecientes)) {
    total += montoPendientePartido(pc);
  }
  return total;
}

int jugadoresPendientesUnicos(List<PartidoCompleto> partidosRecientes) {
  final ids = <String>{};
  for (final pc in partidosConCobrosPendientes(partidosRecientes)) {
    for (final d in cobrosOrganizadorPendientes(pc)) {
      final key = d.jugadorKeyId;
      if (key.isNotEmpty) ids.add(key);
    }
  }
  return ids.length;
}

PartidoCompleto? partidoCerradoReciente(
  List<PartidoCompleto> partidosRecientes, {
  int maxDias = 14,
}) {
  final now = DateTime.now();
  for (final pc in partidosRecientes) {
    if (!partidoOrganizadorCobrosCerrados(pc)) continue;
    final dias = now.difference(pc.partido.fecha).inDays;
    if (dias <= maxDias) return pc;
  }
  return null;
}

/// Si el resumen del grupo tiene deuda pero ningún detalle bruto impago, elige
/// el partido reciente donde participa un jugador con deuda.
PartidoCompleto? partidoFallbackDeudaGrupo(
  List<PartidoCompleto> partidosRecientes,
  List<ResumenJugador> resumenes,
) {
  final deudores = resumenes
      .where((r) => r.tieneDeuda)
      .map((r) => r.jugador.supabaseId ?? r.jugador.id?.toString())
      .whereType<String>()
      .toSet();
  if (deudores.isEmpty) return null;

  for (final pc in partidosRecientes) {
    final tieneDeudor = pc.detalles.any((d) {
      if (!d.asistio) return false;
      final key = d.jugadorSupabaseId ?? d.jugadorKeyId;
      return deudores.contains(key);
    });
    if (tieneDeudor) return pc;
  }
  return partidosRecientes.isNotEmpty ? partidosRecientes.first : null;
}

double deudaTotalGrupo(List<ResumenJugador> resumenes) =>
    CobroLogic.obtenerPendienteGrupo(
      saldosAcumulados: resumenes.map((r) => r.saldoActual),
    );

int jugadoresConDeudaGrupo(List<ResumenJugador> resumenes) =>
    resumenes.where((r) => r.tieneDeuda).length;

CobrosResumen cobrosResumenDesdeResumenes(List<ResumenJugador> resumenes) =>
    CobrosResumen(
      montoTotalPendiente: deudaTotalGrupo(resumenes),
      jugadoresConDeuda: jugadoresConDeudaGrupo(resumenes),
    );
