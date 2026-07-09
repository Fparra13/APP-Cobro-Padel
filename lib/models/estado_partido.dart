enum EstadoPartido {
  organizando,
  confirmado,
  jugado,
  cancelado;

  String get dbValue => name;

  static EstadoPartido fromDb(String? value) {
    switch (value) {
      case 'organizando':
        return EstadoPartido.organizando;
      case 'confirmado':
        return EstadoPartido.confirmado;
      case 'cancelado':
        return EstadoPartido.cancelado;
      case 'jugado':
        return EstadoPartido.jugado;
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

  String get dbValue {
    switch (this) {
      case EstadoConfirmacion.noRespondio:
        return 'no_respondio';
      default:
        return name;
    }
  }

  static EstadoConfirmacion fromDb(String? value) {
    switch (value) {
      case 'confirmado':
        return EstadoConfirmacion.confirmado;
      case 'rechazado':
        return EstadoConfirmacion.rechazado;
      case 'no_respondio':
      case 'noRespondio': // legacy antes de fix dbValue
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
