import '../utils/formatters.dart';

/// Plazo de respuesta a convocatoria acotado a la fecha del partido.
class ConvocatoriaPlazoRespuesta {
  ConvocatoriaPlazoRespuesta._();

  /// Partido en ≤24 h: plazos cortos acotados al cierre.
  static const opcionesUrgentes = [1, 2, 4, 6, 8, 12];

  /// Partido en >24 h: plazos amplios (sin 1–2 h).
  static const opcionesExtendidas = [8, 12, 24];

  /// A partir de aquí se usan plazos extendidos.
  static const umbralPartidoLejanoHoras = 24;

  /// Los jugadores deben confirmar como máximo 6 h antes del partido.
  static const ventanaCierre = Duration(hours: 6);

  /// Margen mínimo si se convoca dentro de las 6 h finales.
  static const margenMinimoAntesPartido = Duration(hours: 1);

  static DateTime topeMaximoConfirmacion(DateTime fechaPartido) =>
      fechaPartido.subtract(ventanaCierre);

  /// Horas completas (redondeo hacia arriba) hasta el partido.
  static int horasHastaPartido(DateTime fechaPartido, [DateTime? reference]) {
    final mins = fechaPartido.difference(reference ?? DateTime.now()).inMinutes;
    if (mins <= 0) return 0;
    return (mins / 60.0).ceil();
  }

  static bool partidoLejano(DateTime fechaPartido, [DateTime? reference]) =>
      horasHastaPartido(fechaPartido, reference) > umbralPartidoLejanoHoras;

  static bool dentroVentanaCierre(
    DateTime fechaPartido, [
    DateTime? reference,
  ]) {
    final now = reference ?? DateTime.now();
    return now.isAfter(topeMaximoConfirmacion(fechaPartido));
  }

  /// Máximo de horas seleccionables respetando cierre 6 h antes.
  static int horasPlazoMaximasSeleccionables(
    DateTime fechaPartido, [
    DateTime? reference,
  ]) {
    final now = reference ?? DateTime.now();
    final tope = topeMaximoConfirmacion(fechaPartido);

    if (now.isAfter(tope)) {
      final horasHasta = horasHastaPartido(fechaPartido, now);
      if (horasHasta <= 1) return 1;
      return horasHasta.clamp(1, 2);
    }

    final maxH = tope.difference(now).inMinutes ~/ 60;
    if (maxH >= 1) return maxH.clamp(1, 24);
    return 1;
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

    // Entre presets: usar el máximo real (p. ej. 17 h → opción 17 en urgente).
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

  /// `now + horas`, sin pasar 6 h antes del partido.
  static DateTime calcularTiempoLimite({
    required DateTime enviadoEn,
    required int horasLimite,
    required DateTime fechaPartido,
  }) {
    final porHoras = enviadoEn.add(Duration(hours: horasLimite));
    final tope = topeMaximoConfirmacion(fechaPartido);
    final piso = fechaPartido.subtract(margenMinimoAntesPartido);

    if (!enviadoEn.isAfter(tope)) {
      if (porHoras.isAfter(tope)) return tope;
      return porHoras;
    }

    final candidato = porHoras.isBefore(piso) ? porHoras : piso;
    if (candidato.isAfter(enviadoEn)) return candidato;
    final urgente = enviadoEn.add(const Duration(hours: 1));
    return urgente.isBefore(piso) ? urgente : piso;
  }

  static bool plazoRecortadoPorPartido({
    required int horasLimite,
    required DateTime fechaPartido,
    DateTime? enviadoEn,
  }) {
    final envio = enviadoEn ?? DateTime.now();
    final porHoras = envio.add(Duration(hours: horasLimite));
    final tope = topeMaximoConfirmacion(fechaPartido);
    return porHoras.isAfter(tope);
  }
}
