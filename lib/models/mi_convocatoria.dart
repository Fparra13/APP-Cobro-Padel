import 'convocatoria_jugador.dart';
import 'estado_partido.dart';
import 'partido.dart';

/// Convocatoria del jugador actual con datos del partido.
class MiConvocatoria {
  final ConvocatoriaJugadorEntry entry;
  final Partido partido;

  const MiConvocatoria({
    required this.entry,
    required this.partido,
  });

  bool get requiereRespuesta =>
      !entry.esSuplente && entry.estado == EstadoConfirmacion.invitado;

  bool get estaConfirmado =>
      !entry.esSuplente && entry.estado == EstadoConfirmacion.confirmado;

  bool get esProximo =>
      partido.esConvocatoriaPendiente &&
      partido.fecha.isAfter(DateTime.now().subtract(const Duration(hours: 6)));
}
