import '../models/convocatoria_jugador.dart';
import 'partido_lifecycle.dart';

/// Reglas de cupo: cuándo ya no es posible llenar el partido con quienes quedan.
class ConvocatoriaCupoLogic {
  ConvocatoriaCupoLogic._();

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
