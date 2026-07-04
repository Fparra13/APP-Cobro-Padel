enum EstadoPartido {
  organizando,
  confirmado,
  jugado;

  String get dbValue => name;

  static EstadoPartido fromDb(String? value) {
    switch (value) {
      case 'organizando':
        return EstadoPartido.organizando;
      case 'confirmado':
        return EstadoPartido.confirmado;
      default:
        return EstadoPartido.jugado;
    }
  }
}

enum EstadoConfirmacion {
  invitado,
  confirmado,
  rechazado,
  noRespondio;

  String get dbValue => name;

  static EstadoConfirmacion fromDb(String? value) {
    switch (value) {
      case 'confirmado':
        return EstadoConfirmacion.confirmado;
      case 'rechazado':
        return EstadoConfirmacion.rechazado;
      case 'no_respondio':
        return EstadoConfirmacion.noRespondio;
      default:
        return EstadoConfirmacion.invitado;
    }
  }

  /// Titular activo: ocupa o puede ocupar un cupo.
  bool get esTitularActivo =>
      this == invitado || this == confirmado;

  bool get liberaCupo =>
      this == rechazado || this == noRespondio;

  EstadoConfirmacion siguiente({bool esSuplente = false}) {
    if (esSuplente) return invitado;
    switch (this) {
      case EstadoConfirmacion.invitado:
        return EstadoConfirmacion.confirmado;
      case EstadoConfirmacion.confirmado:
        return EstadoConfirmacion.rechazado;
      case EstadoConfirmacion.rechazado:
      case EstadoConfirmacion.noRespondio:
        return EstadoConfirmacion.invitado;
    }
  }
}
