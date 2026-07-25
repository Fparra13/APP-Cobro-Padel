import 'package:intl/intl.dart';

import '../core/sport_type.dart';
import '../utils/formatters.dart';
import 'desglose_jugador.dart';
import 'detalle_partido.dart';
import 'partido.dart';
import 'costo_variable.dart';

/// Línea de gasto con comprobante opcional (vista jugador/organizador).
class ComprobanteGastoLinea {
  final String concepto;
  final double monto;
  final String path;
  final String? emoji;

  const ComprobanteGastoLinea({
    required this.concepto,
    required this.monto,
    required this.path,
    this.emoji,
  });
}

/// Comprobantes de un encuentro, para agrupar en UI.
class ComprobanteGastoGrupo {
  final int? partidoId;
  final DateTime? fecha;
  final String? organizadorNombre;
  final SportType? sportType;
  final String? lugar;
  final List<ComprobanteGastoLinea> lineas;
  final bool initiallyExpanded;

  const ComprobanteGastoGrupo({
    this.partidoId,
    this.fecha,
    this.organizadorNombre,
    this.sportType,
    this.lugar,
    required this.lineas,
    this.initiallyExpanded = true,
  });

  bool get isEmpty => lineas.isEmpty;
  bool get isNotEmpty => lineas.isNotEmpty;

  /// Fecha abreviada: "Dom 26 jul · 20:00".
  String get tituloFechaHora {
    final f = fecha;
    if (f == null) return '';
    final locale = MoneyFormatConfig.dateLocale.isNotEmpty
        ? MoneyFormatConfig.dateLocale
        : 'es';
    final raw = DateFormat('EEE d MMM', locale).format(f);
    final cleaned = raw.replaceAll('.', '').trim();
    return '${capitalize(cleaned)} · ${formatHora(f)}';
  }

  /// Compat: mismo texto que [tituloFechaHora].
  String get tituloEncuentro => tituloFechaHora;

  /// "🎾 Pádel · Club Central" (partes omitidas si faltan).
  String lineaDeporteLugar({String? sportLabel}) {
    final parts = <String>[];
    final sport = sportType;
    if (sport != null) {
      final label = (sportLabel ?? sport.labelEs).trim();
      final emoji = sport.emoji;
      parts.add(label.isEmpty ? emoji : '$emoji $label');
    }
    final place = lugar?.trim();
    if (place != null && place.isNotEmpty) {
      parts.add(place);
    }
    return parts.join(' · ');
  }

  static String? emojiParaConcepto(String concepto) {
    final c = concepto.toLowerCase().trim();
    if (c.contains('cancha') || c.contains('court') || c.contains('quadra')) {
      return '🏟️';
    }
    if (c.contains('pelota') || c.contains('ball') || c.contains('bola')) {
      return '🎾';
    }
    if (c.contains('asado') || c.contains('meat') || c.contains('bbq')) {
      return '🍖';
    }
    if (c.contains('bebida') ||
        c.contains('drink') ||
        c.contains('schop') ||
        c.contains('barra')) {
      return '🥤';
    }
    return null;
  }

  /// Grupo desde desglose del jugador + detalle del encuentro.
  static ComprobanteGastoGrupo? fromDesglose({
    required DesgloseJugador desglose,
    required DetallePartido detalle,
    String? organizadorNombre,
    required String canchaLabel,
    required String pelotasLabel,
    bool initiallyExpanded = true,
  }) {
    final lineas = <ComprobanteGastoLinea>[];

    final canchaUrl = desglose.comprobanteCanchaUrl?.trim();
    if (canchaUrl != null && canchaUrl.isNotEmpty) {
      lineas.add(
        ComprobanteGastoLinea(
          concepto: canchaLabel,
          monto: desglose.cancha,
          path: canchaUrl,
          emoji: emojiParaConcepto(canchaLabel),
        ),
      );
    }

    final pelotasUrl = desglose.comprobantePelotasUrl?.trim();
    if (pelotasUrl != null && pelotasUrl.isNotEmpty) {
      lineas.add(
        ComprobanteGastoLinea(
          concepto: pelotasLabel,
          monto: desglose.pelotas,
          path: pelotasUrl,
          emoji: emojiParaConcepto(pelotasLabel),
        ),
      );
    }

    for (final g in desglose.gastosVariables) {
      if (!g.tieneComprobante) continue;
      lineas.add(
        ComprobanteGastoLinea(
          concepto: g.concepto,
          monto: g.monto,
          path: g.comprobanteUrl!.trim(),
          emoji: emojiParaConcepto(g.concepto),
        ),
      );
    }

    if (lineas.isEmpty) return null;

    final lugar = detalle.recintoPartido?.trim();
    return ComprobanteGastoGrupo(
      partidoId: detalle.partidoId,
      fecha: detalle.fechaPartido,
      organizadorNombre: organizadorNombre?.trim().isNotEmpty == true
          ? organizadorNombre!.trim()
          : null,
      sportType: detalle.sportType,
      lugar: (lugar != null && lugar.isNotEmpty) ? lugar : null,
      lineas: lineas,
      initiallyExpanded: initiallyExpanded,
    );
  }

  /// Grupos para varios encuentros pendientes (orden por fecha ascendente).
  static List<ComprobanteGastoGrupo> fromPendientes({
    required List<DetallePartido> deudas,
    required Map<int, DesgloseJugador?> desgloses,
    String? organizadorNombre,
    required String canchaLabel,
    required String pelotasLabel,
  }) {
    final sorted = List<DetallePartido>.from(deudas)
      ..sort((a, b) {
        final fa = a.fechaPartido;
        final fb = b.fechaPartido;
        if (fa == null && fb == null) return a.partidoId.compareTo(b.partidoId);
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fa.compareTo(fb);
      });

    final grupos = <ComprobanteGastoGrupo>[];
    for (final d in sorted) {
      final des = desgloses[d.partidoId];
      if (des == null) continue;
      final g = fromDesglose(
        desglose: des,
        detalle: d,
        organizadorNombre: organizadorNombre,
        canchaLabel: canchaLabel,
        pelotasLabel: pelotasLabel,
        initiallyExpanded: true,
      );
      if (g != null) grupos.add(g);
    }
    return grupos;
  }

  /// Vista organizador: un solo encuentro.
  static ComprobanteGastoGrupo? fromPartidoOrganizador({
    required Partido partido,
    required List<CostoVariable> costosVariables,
    required String canchaLabel,
    required String pelotasLabel,
    String? organizadorNombre,
  }) {
    final lineas = <ComprobanteGastoLinea>[];
    if (partido.costoCancha > 0 && partido.comprobanteCancha != null) {
      lineas.add(
        ComprobanteGastoLinea(
          concepto: canchaLabel,
          monto: partido.costoCancha,
          path: partido.comprobanteCancha!,
          emoji: emojiParaConcepto(canchaLabel),
        ),
      );
    }
    if (partido.costoPelotas > 0 && partido.comprobantePelotas != null) {
      lineas.add(
        ComprobanteGastoLinea(
          concepto: pelotasLabel,
          monto: partido.costoPelotas,
          path: partido.comprobantePelotas!,
          emoji: emojiParaConcepto(pelotasLabel),
        ),
      );
    }
    for (final cv in costosVariables) {
      final path = cv.comprobantePath?.trim();
      if (path == null || path.isEmpty) continue;
      lineas.add(
        ComprobanteGastoLinea(
          concepto: cv.concepto,
          monto: cv.montoTotal,
          path: path,
          emoji: emojiParaConcepto(cv.concepto),
        ),
      );
    }
    if (lineas.isEmpty) return null;
    final lugar = partido.recinto?.trim();
    return ComprobanteGastoGrupo(
      partidoId: partido.id,
      fecha: partido.fecha,
      organizadorNombre: organizadorNombre,
      sportType: partido.sportType,
      lugar: (lugar != null && lugar.isNotEmpty) ? lugar : null,
      lineas: lineas,
      initiallyExpanded: true,
    );
  }
}
