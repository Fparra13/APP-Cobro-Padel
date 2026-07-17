/// Plazo de respuesta a convocatoria.
///
/// El organizador elige cuántas horas tienen los jugadores para responder
/// desde el envío (`now + horas`). Las opciones del selector no pueden
/// superar la hora del encuentro (no tiene sentido confirmar después).
class ConvocatoriaPlazoRespuesta {
  ConvocatoriaPlazoRespuesta._();

  /// Partido en ≤24 h: plazos cortos.
  static const opcionesUrgentes = [1, 2, 4, 6, 8, 12];

  /// Partido en >24 h: plazos amplios (sin 1–2 h).
  static const opcionesExtendidas = [8, 12, 24];

  /// A partir de aquí se usan plazos extendidos.
  static const umbralPartidoLejanoHoras = 24;

  /// Horas completas (redondeo hacia arriba) hasta el partido.
  static int horasHastaPartido(DateTime fechaPartido, [DateTime? reference]) {
    final mins = fechaPartido.difference(reference ?? DateTime.now()).inMinutes;
    if (mins <= 0) return 0;
    return (mins / 60.0).ceil();
  }

  static bool partidoLejano(DateTime fechaPartido, [DateTime? reference]) =>
      horasHastaPartido(fechaPartido, reference) > umbralPartidoLejanoHoras;

  /// @deprecated Sin ventana de cierre; se mantiene por compatibilidad.
  static bool dentroVentanaCierre(
    DateTime fechaPartido, [
    DateTime? reference,
  ]) =>
      false;

  /// Máximo de horas enteras que caben antes de la hora del partido.
  static int horasPlazoMaximasSeleccionables(
    DateTime fechaPartido, [
    DateTime? reference,
  ]) {
    final now = reference ?? DateTime.now();
    final mins = fechaPartido.difference(now).inMinutes;
    if (mins <= 0) return 1;
    final maxH = mins ~/ 60;
    if (maxH < 1) return 1;
    return maxH.clamp(1, 24);
  }

  /// Opciones según cuánto falta para el partido.
  static List<int> opcionesPermitidas(
    DateTime fechaPartido, [
    DateTime? reference,
  ]) {
    final now = reference ?? DateTime.now();
    final horasHasta = horasHastaPartido(fechaPartido, now);
    if (horasHasta <= 0) return const [1];

    final maxHoras = horasPlazoMaximasSeleccionables(fechaPartido, now);
    final base = partidoLejano(fechaPartido, now)
        ? opcionesExtendidas
        : opcionesUrgentes;

    final opts = base.where((h) => h <= maxHoras).toList();
    if (opts.isNotEmpty) return opts;

    // Entre presets: usar el máximo real (p. ej. 3 h → opción 3).
    if (!partidoLejano(fechaPartido, now) && maxHoras > 1) {
      return [maxHoras.clamp(1, 24)];
    }
    return [1];
  }

  /// Ajusta horas elegidas a una opción válida (la mayor que quepa).
  static int ajustarHoras(
    int horasActuales,
    DateTime fechaPartido, [
    DateTime? reference,
  ]) {
    final opts = opcionesPermitidas(fechaPartido, reference);
    if (opts.contains(horasActuales)) return horasActuales;
    return opts.last;
  }

  /// Plazo sugerido al elegir fecha.
  static int sugerirHoras(DateTime fechaPartido, [DateTime? reference]) {
    final ref = reference ?? DateTime.now();
    final opts = opcionesPermitidas(fechaPartido, ref);
    if (opts.isEmpty) return 1;

    if (partidoLejano(fechaPartido, ref)) {
      if (opts.contains(24)) return 24;
      return opts.last;
    }

    return opts.last;
  }

  /// `now + horas`, sin pasar la hora del partido.
  static DateTime calcularTiempoLimite({
    required DateTime enviadoEn,
    required int horasLimite,
    required DateTime fechaPartido,
  }) {
    final porHoras = enviadoEn.add(Duration(hours: horasLimite));
    if (porHoras.isAfter(fechaPartido)) return fechaPartido;
    return porHoras;
  }

  /// True si `now + horas` pasaría la hora del encuentro.
  static bool plazoRecortadoPorPartido({
    required int horasLimite,
    required DateTime fechaPartido,
    DateTime? enviadoEn,
  }) {
    final envio = enviadoEn ?? DateTime.now();
    final porHoras = envio.add(Duration(hours: horasLimite));
    return porHoras.isAfter(fechaPartido);
  }
}
