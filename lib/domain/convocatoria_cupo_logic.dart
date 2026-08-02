import '../models/convocatoria_jugador.dart';
import 'partido_lifecycle.dart';

/// Titulares + reservas del borrador de convocatoria (pre-envío).
class SeleccionBorradorCupo {
  final List<String> titulares;
  final List<String> reservas;

  const SeleccionBorradorCupo({
    required this.titulares,
    required this.reservas,
  });
}

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

  /// Seleccionar/deseleccionar en borrador con auto-promoción de reservas.
  ///
  /// - Al marcar: titular si hay cupo; si no, al final de reservas.
  /// - Al desmarcar un titular: promueve reservas (en orden) hasta llenar cupo.
  /// - Al desmarcar una reserva: titulares no cambian; el resto de reservas
  ///   conserva el orden relativo.
  static SeleccionBorradorCupo aplicarToggleSeleccionBorrador({
    required List<String> titulares,
    required List<String> reservas,
    required int cuposMax,
    required String jugadorId,
    required bool seleccionar,
  }) {
    final t = List<String>.from(titulares);
    final r = List<String>.from(reservas);

    if (seleccionar) {
      if (t.contains(jugadorId) || r.contains(jugadorId)) {
        return SeleccionBorradorCupo(titulares: t, reservas: r);
      }
      if (t.length < cuposMax) {
        t.add(jugadorId);
      } else {
        r.add(jugadorId);
      }
      return SeleccionBorradorCupo(titulares: t, reservas: r);
    }

    final eraTitular = t.remove(jugadorId);
    r.remove(jugadorId);
    if (eraTitular) {
      while (t.length < cuposMax && r.isNotEmpty) {
        t.add(r.removeAt(0));
      }
    }
    return SeleccionBorradorCupo(titulares: t, reservas: r);
  }

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
