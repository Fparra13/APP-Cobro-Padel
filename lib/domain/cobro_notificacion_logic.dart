import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';

/// Decide si un detalle debe recibir push de cobro pendiente.
bool debeNotificarCobroPendiente({
  required DetallePartido detalle,
  DesgloseJugador? desglose,
  double? snapshotSaldoAnterior,
}) {
  if (!detalle.asistio || detalle.jugadorSupabaseId == null) return false;
  if (detalle.total <= 0.005) return false;

  if (desglose != null && desglose.pendientePartido > 0.005) return true;

  if (snapshotSaldoAnterior != null) {
    return detalle.tieneDeudaNeto(
      snapshotSaldoAnterior: snapshotSaldoAnterior,
    );
  }

  // Sin snapshot aún: notifica si el cargo sigue abierto.
  return !detalle.pagado;
}

/// Partido cubierto solo con saldo a favor (sin transferencia).
bool debeNotificarCobroCubiertoConFavor({
  required DetallePartido detalle,
  DesgloseJugador? desglose,
  double? snapshotSaldoAnterior,
}) {
  if (!detalle.asistio || detalle.jugadorSupabaseId == null) return false;
  if (detalle.total <= 0.005) return false;

  if (desglose != null) {
    return desglose.saldoFavorAplicado > 0.005 &&
        desglose.pendientePartido <= 0.005 &&
        desglose.montoPagado <= 0.005;
  }

  if (snapshotSaldoAnterior == null) return false;
  if (detalle.tieneDeudaNeto(snapshotSaldoAnterior: snapshotSaldoAnterior)) {
    return false;
  }
  // Cubierto y había crédito previo al cargo.
  return snapshotSaldoAnterior < -0.005 && detalle.pagado;
}

/// Monto a comunicar en el cuerpo del push de cobro pendiente.
double montoNotificacionCobroPendiente({
  required DetallePartido detalle,
  DesgloseJugador? desglose,
  double? snapshotSaldoAnterior,
}) {
  if (desglose != null && desglose.pendientePartido > 0.005) {
    return desglose.pendientePartido;
  }
  if (snapshotSaldoAnterior != null) {
    return detalle
        .estadoCobro(snapshotSaldoAnterior: snapshotSaldoAnterior)
        .pendienteNeto;
  }
  return detalle.total;
}
