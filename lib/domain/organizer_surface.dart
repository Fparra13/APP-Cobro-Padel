/// Superficie de trabajo del organizador (contrato de navegación).
///
/// Home (u otro entry point) decide la superficie antes de navegar.
/// La UI de cada pantalla debe responder a este valor; no re-derivar la
/// intención con flags locales.
enum OrganizerSurface {
  /// Crear / editar borrador / enviar convocatoria.
  build,

  /// Seguimiento de convocatoria enviada (asistencias, riesgo, confirmado).
  attendance,

  /// Registrar gastos del encuentro.
  expenses,

  /// Cobros / pendientes de pago.
  collection,
}
