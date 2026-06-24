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
  rechazado;

  String get dbValue => name;

  static EstadoConfirmacion fromDb(String? value) {
    switch (value) {
      case 'confirmado':
        return EstadoConfirmacion.confirmado;
      case 'rechazado':
        return EstadoConfirmacion.rechazado;
      default:
        return EstadoConfirmacion.invitado;
    }
  }

  EstadoConfirmacion siguiente() {
    switch (this) {
      case EstadoConfirmacion.invitado:
        return EstadoConfirmacion.confirmado;
      case EstadoConfirmacion.confirmado:
        return EstadoConfirmacion.rechazado;
      case EstadoConfirmacion.rechazado:
        return EstadoConfirmacion.invitado;
    }
  }
}
