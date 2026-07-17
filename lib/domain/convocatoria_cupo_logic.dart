import '../models/convocatoria_jugador.dart';
import 'partido_lifecycle.dart';

/// Reglas de cupo: cuándo ya no es posible llenar el partido con quienes quedan.
class ConvocatoriaCupoLogic {
  ConvocatoriaCupoLogic._();

  /// Destino al marcar a alguien en el borrador de convocatoria.
  ///
  /// Los primeros [cuposMax] van a invitados; el resto a lista de espera.
  static String destinoSeleccionBorrador({
    required int invitadosActuales,
    required int cuposMax,
  }) =>
      invitadosActuales < cuposMax ? 'invitado' : 'espera';

  /// La lista de espera solo se arma cuando los cupos de invitación están
  /// completos (o ya hay gente en espera cargada desde el servidor).
  static bool mostrarListaEspera({
    required int seleccionados,
    required int cuposMax,
    required int enEspera,
  }) =>
      seleccionados >= cuposMax || enEspera > 0;

  /// Máximo de confirmados alcanzable si responden sí todos los que aún pueden.
  ///
  /// `confirmados + titulares pendientes + suplentes en lista de espera`.
  static int maxConfirmadosPosible(ConvocatoriaCompleta convocatoria) {
    return convocatoria.confirmados +
        convocatoria.pendientes +
        convocatoria.enEspera;
  }

  /// Convocatoria enviada, partido futuro y matemáticamente imposible llenar cupos.
  static bool cupoImposible(
    ConvocatoriaCompleta convocatoria, [
    DateTime? reference,
  ]) {
    final partido = convocatoria.partido;
    if (!convocatoria.convocatoriaEnviada) return false;
    if (!partido.esOrganizando) return false;
    if (PartidoLifecycle.convocatoriaExpirada(partido, reference)) {
      return false;
    }

    final cupos = partido.cuposMax;
    if (cupos <= 0) return false;
    if (convocatoria.confirmados >= cupos) return false;

    return maxConfirmadosPosible(convocatoria) < cupos;
  }
}
