/// Resumen histórico de invitaciones del jugador (titular, no suplente).
class MisInvitacionesResumen {
  /// Total de convocatorias recibidas como titular.
  final int recibidas;

  /// Respondió (confirmó o rechazó). No cuenta `invitado` ni `no_respondio`.
  final int respondidas;

  /// Solo confirmaciones (`confirmado`).
  final int confirmadas;

  const MisInvitacionesResumen({
    this.recibidas = 0,
    this.respondidas = 0,
    this.confirmadas = 0,
  });

  static const empty = MisInvitacionesResumen();

  /// % de respuesta 0–100. Si no hay invitaciones, 0.
  double get porcentajeRespuesta {
    if (recibidas <= 0) return 0;
    final pct = (respondidas / recibidas) * 100;
    if (pct.isNaN || pct.isInfinite) return 0;
    return pct.clamp(0, 100);
  }
}

/// Qué muestra la 2ª ficha de orgullo en home jugador.
enum PlayerPrideSecondaryKind {
  /// % respuesta a convocatorias.
  respuesta,

  /// Semanas activas (fallback sin invitaciones).
  racha,

  /// Sin dato aún.
  vacio,
}

class PlayerPrideSecondaryMetric {
  final PlayerPrideSecondaryKind kind;

  /// Porcentaje entero 0–100 cuando [kind] == respuesta.
  final int? porcentaje;

  /// Semanas cuando [kind] == racha.
  final int? semanas;

  const PlayerPrideSecondaryMetric._({
    required this.kind,
    this.porcentaje,
    this.semanas,
  });

  factory PlayerPrideSecondaryMetric.respuesta(int porcentaje) =>
      PlayerPrideSecondaryMetric._(
        kind: PlayerPrideSecondaryKind.respuesta,
        porcentaje: porcentaje.clamp(0, 100),
      );

  factory PlayerPrideSecondaryMetric.racha(int semanas) =>
      PlayerPrideSecondaryMetric._(
        kind: PlayerPrideSecondaryKind.racha,
        semanas: semanas,
      );

  factory PlayerPrideSecondaryMetric.vacio() => const PlayerPrideSecondaryMetric._(
        kind: PlayerPrideSecondaryKind.vacio,
      );
}

/// Elige la 2ª métrica: respuesta si hay invitaciones; si no, racha.
PlayerPrideSecondaryMetric resolvePrideSecondaryMetric({
  required MisInvitacionesResumen invitaciones,
  required int semanasJugando,
  int minSemanasRacha = 2,
}) {
  if (invitaciones.recibidas >= 1) {
    return PlayerPrideSecondaryMetric.respuesta(
      invitaciones.porcentajeRespuesta.round(),
    );
  }
  if (semanasJugando >= minSemanasRacha) {
    return PlayerPrideSecondaryMetric.racha(semanasJugando);
  }
  return PlayerPrideSecondaryMetric.vacio();
}

/// Cuenta respuesta desde estados de convocatoria (titulares).
MisInvitacionesResumen resumenDesdeEstadosConfirmacion(
  Iterable<String> estadosDb,
) {
  var recibidas = 0;
  var respondidas = 0;
  var confirmadas = 0;
  for (final raw in estadosDb) {
    recibidas++;
    switch (raw) {
      case 'confirmado':
        confirmadas++;
        respondidas++;
      case 'rechazado':
        respondidas++;
      default:
        break;
    }
  }
  return MisInvitacionesResumen(
    recibidas: recibidas,
    respondidas: respondidas,
    confirmadas: confirmadas,
  );
}
