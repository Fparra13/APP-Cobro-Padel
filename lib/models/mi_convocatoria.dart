import 'convocatoria_jugador.dart';
import '../domain/partido_lifecycle.dart';
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

  bool get requiereRespuesta => PartidoLifecycle.puedeResponderJugador(this);

  bool get puedeDeclinarTrasConfirmar =>
      PartidoLifecycle.puedeDeclinarTrasConfirmar(this);

  bool get convocatoriaExpirada =>
      PartidoLifecycle.convocatoriaExpirada(partido);

  bool get estaConfirmado =>
      !entry.esSuplente && entry.estado == EstadoConfirmacion.confirmado;

  bool get esProximo =>
      partido.esConvocatoriaPendiente && !convocatoriaExpirada;

  /// Tras reprogramar: el jugador debe volver a confirmar la nueva fecha.
  bool get esReprogramadoPendiente =>
      partido.reprogramadoEn != null &&
      partido.fecha.isAfter(DateTime.now()) &&
      requiereRespuesta;
}
