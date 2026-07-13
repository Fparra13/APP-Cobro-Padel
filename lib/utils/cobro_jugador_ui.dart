import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../domain/cobro_logic.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../widgets/desglose_cobro_panel.dart';
import 'formatters.dart';

/// Prioridad de atención para mostrar el cobro protagonista (no cronología pura).
int _prioridadAtencion(DetallePartido d, {double? saldoAnteriorAlPartido}) {
  if (d.comprobantePendienteValidacion) return 0;
  if (saldoAnteriorAlPartido != null &&
      d.pagoParcialNeto(snapshotSaldoAnterior: saldoAnteriorAlPartido)) {
    return 1;
  }
  return 2;
}

DateTime _fechaOrden(DetallePartido d) =>
    d.fechaPartido ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Ordena cobros: comprobante en revisión → parcial → más antiguo → más reciente.
List<DetallePartido> ordenarCobrosPorAtencion(
  List<DetallePartido> deudas, {
  Map<int, double>? saldosAnterioresPorPartido,
}) {
  final copy = List<DetallePartido>.from(deudas);
  copy.sort((a, b) {
    final pa = _prioridadAtencion(
      a,
      saldoAnteriorAlPartido: saldosAnterioresPorPartido?[a.partidoId],
    );
    final pb = _prioridadAtencion(
      b,
      saldoAnteriorAlPartido: saldosAnterioresPorPartido?[b.partidoId],
    );
    if (pa != pb) return pa.compareTo(pb);
    if (pa == 2) {
      final fa = _fechaOrden(a);
      final fb = _fechaOrden(b);
      final cmp = fa.compareTo(fb);
      if (cmp != 0) return cmp;
    }
    return b.partidoId.compareTo(a.partidoId);
  });
  return copy;
}

DetallePartido? protagonistaCobro(List<DetallePartido> deudas) {
  final sorted = ordenarCobrosPorAtencion(deudas);
  return sorted.isEmpty ? null : sorted.first;
}

List<DetallePartido> otrosCobrosPorCerrar(List<DetallePartido> deudas) {
  final sorted = ordenarCobrosPorAtencion(deudas);
  if (sorted.length <= 1) return const [];
  return sorted.sublist(1);
}

bool partidoRequiereAtencionEnLista(
  DetallePartido d, {
  DesgloseJugador? desglose,
  double? saldoAnteriorAlPartido,
}) {
  if (d.comprobantePendienteValidacion) return true;
  return montoMarginalPartidoCobro(
        d,
        desglose,
        saldoAnteriorPartido: saldoAnteriorAlPartido,
      ) >
      0.005;
}

/// Partidos a listar en Mis cobros: ancla de la cuenta + cargos marginales abiertos.
({DetallePartido? ancla, List<DetallePartido> otros}) cobrosVisiblesJugador({
  required List<DetallePartido> deudas,
  required Map<int, DesgloseJugador?> desgloses,
  Map<int, double>? saldosAnterioresPorPartido,
  double? saldoAcumuladoJugador,
}) {
  if (deudas.isEmpty) {
    return (ancla: null, otros: const []);
  }
  final ordenados = ordenarCobrosPorAtencion(
    deudas,
    saldosAnterioresPorPartido: saldosAnterioresPorPartido,
  );
  final ancla = detalleAnclaPago(ordenados) ?? ordenados.first;
  final otros = <DetallePartido>[];

  if (saldoAcumuladoJugador != null && saldoAcumuladoJugador > 0.005) {
    for (final d in ordenados) {
      if (d.partidoId == ancla.partidoId) continue;
      if (d.comprobantePendienteValidacion) otros.add(d);
    }
    return (ancla: ancla, otros: otros);
  }

  for (final d in ordenados) {
    if (d.partidoId == ancla.partidoId) continue;
    if (partidoRequiereAtencionEnLista(
      d,
      desglose: desgloses[d.partidoId],
      saldoAnteriorAlPartido: saldosAnterioresPorPartido?[d.partidoId],
    )) {
      otros.add(d);
    }
  }
  final mostrarAncla = partidoRequiereAtencionEnLista(
    ancla,
    desglose: desgloses[ancla.partidoId],
    saldoAnteriorAlPartido: saldosAnterioresPorPartido?[ancla.partidoId],
  );
  return (
    ancla: mostrarAncla ? ancla : null,
    otros: otros,
  );
}

double totalPendienteCobros(
  List<DetallePartido> deudas,
  Map<int, DesgloseJugador?> desgloses, {
  Map<int, double>? saldosAnterioresPorPartido,
  double? saldoAcumuladoJugador,
}) {
  if (saldoAcumuladoJugador != null && saldoAcumuladoJugador > 0.005) {
    return CobroLogic.obtenerPendienteJugador(
      saldoAcumulado: saldoAcumuladoJugador,
    );
  }
  return deudas.fold<double>(
    0,
    (s, d) =>
        s +
        montoATransferirCobro(
          d,
          desgloses[d.partidoId],
          saldoAnteriorPartido: saldosAnterioresPorPartido?[d.partidoId],
        ),
  );
}

/// Detalle al que se ancla el comprobante (partido más antiguo con deuda activa).
DetallePartido? detalleAnclaPago(List<DetallePartido> deudas) {
  if (deudas.isEmpty) return null;
  final pool = deudas.where((d) => !d.pagado).toList();
  final sorted = List<DetallePartido>.from(pool.isNotEmpty ? pool : deudas)
    ..sort((a, b) {
      final cmp = _fechaOrden(a).compareTo(_fechaOrden(b));
      if (cmp != 0) return cmp;
      return a.partidoId.compareTo(b.partidoId);
    });
  return sorted.first;
}

String antiguedadPartidoTexto(DateTime? fecha) {
  if (fecha == null) return '';
  return formatTiempoRelativo(fecha);
}

bool partidoRequiereAtencionUrgente(DetallePartido d) {
  if (d.comprobantePendienteValidacion) return true;
  final fecha = d.fechaPartido;
  if (fecha == null) return false;
  return DateTime.now().difference(fecha).inDays >= 30;
}

String titularProtagonistaCobro(
  DetallePartido d,
  MatchPayStrings l10n, {
  double? saldoAnteriorAlPartido,
}) {
  if (d.comprobantePendienteValidacion) {
    return l10n.tr('cobrosHeroReceiptReview');
  }
  if (saldoAnteriorAlPartido != null &&
      d.pagoParcialNeto(snapshotSaldoAnterior: saldoAnteriorAlPartido)) {
    return l10n.tr('cobrosHeroPartial');
  }
  final fecha = d.fechaPartido;
  if (fecha != null && DateTime.now().difference(fecha).inDays >= 30) {
    return l10n.tr(
      'cobrosHeroOld',
      params: {'when': antiguedadPartidoTexto(fecha)},
    );
  }
  return l10n.tr('cobrosHeroDefault');
}

/// Líneas tipo "🎾 1 encuentro de Pádel" para el resumen superior.
List<String> resumenDeportesPorCerrar(
  List<DetallePartido> deudas,
  MatchPayStrings l10n,
  String lang,
) {
  final counts = <SportType, int>{};
  for (final d in deudas) {
    final sport = d.sportType ?? SportType.padel;
    counts[sport] = (counts[sport] ?? 0) + 1;
  }
  return counts.entries.map((e) {
    final emoji = SportThemeConfig.paletteFor(e.key).emoji;
    final label = e.key.labelForLang(lang);
    final count = e.value;
    return l10n.tr(
      count == 1 ? 'cobrosSportLineOne' : 'cobrosSportLineMany',
      params: {'emoji': emoji, 'count': '$count', 'sport': label},
    );
  }).toList();
}

String resumenDeportesLinea(
  List<DetallePartido> deudas,
  MatchPayStrings l10n,
  String lang,
) {
  return resumenDeportesPorCerrar(deudas, l10n, lang).join(' · ');
}
