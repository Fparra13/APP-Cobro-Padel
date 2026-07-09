import '../models/detalle_partido.dart';
import '../models/estadisticas_jugador.dart';
import '../models/jugador.dart';
import '../models/mi_convocatoria.dart';

/// Estadísticas del jugador autenticado a partir de datos ya visibles con RLS de jugador.
EstadisticasJugador? buildMisEstadisticasDesdeHome({
  required String? uid,
  required Jugador? perfil,
  required List<DetallePartido> partidosJugados,
  required List<MiConvocatoria> convocatorias,
}) {
  if (uid == null) return null;

  final limite90 = DateTime.now().subtract(const Duration(days: 90));
  var pagosAlDia = 0;
  var pagosTardios = 0;
  var impagos = 0;
  var totalGastado = 0.0;
  var partidos90 = 0;

  for (final p in partidosJugados) {
    totalGastado += p.total;
    final fecha = p.fechaPartido;
    if (fecha != null && !fecha.isBefore(limite90)) {
      partidos90++;
    }

    if (p.pagado) {
      pagosAlDia++;
    } else if (p.comprobantePendienteValidacion) {
      pagosTardios++;
    } else {
      impagos++;
    }
  }

  final convocatoriasConfirmadas = convocatorias
      .where((c) => !c.entry.esSuplente && c.estaConfirmado)
      .length;

  if (partidosJugados.isEmpty && convocatoriasConfirmadas == 0) {
    return null;
  }

  return EstadisticasJugador(
    jugadorId: 0,
    jugadorKeyId: uid,
    nombre: perfil?.nombre ?? '',
    fotoPath: perfil?.fotoPath,
    fotoUrl: perfil?.fotoUrl,
    partidosJugados: partidosJugados.length,
    pagosAlDia: pagosAlDia,
    pagosTardios: pagosTardios,
    partidosImpagos: impagos,
    promedioDiasPago: 0,
    totalGastado: totalGastado,
    saldoActual: perfil?.saldoAcumulado ?? 0,
    convocatoriasConfirmadas: convocatoriasConfirmadas,
    partidosUltimos90Dias: partidos90,
  );
}
