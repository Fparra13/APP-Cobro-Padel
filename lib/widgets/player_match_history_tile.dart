import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../domain/deuda_explicacion.dart';
import '../models/detalle_partido.dart';
import '../models/mi_convocatoria.dart';
import '../models/player_historial_entry.dart';
import '../models/saldo_historico.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/matchpay_ui.dart';
import 'comprobante_historico_chip.dart';
import 'sport_icon.dart';

/// Cómo mostrar cada fila del historial de partidos del jugador.
enum PlayerMatchHistorialModo {
  /// Deuda en cuenta: solo el cargo del jugador en cada partido.
  cuentaConDeuda,
  /// Sin deuda consolidada: badge pagado/pendiente por partido.
  porPartido,
}

enum PlayerMatchHistoryVisual {
  compact,
  premium,
}

/// Cabecera visual de la pestaña Partidos (resumen sin chips).
class PlayerMatchHistoryHero extends StatelessWidget {
  final int totalPartidos;
  final int pagados;
  final int pendientes;
  final Map<SportType, int> conteoPorDeporte;
  final SportType? deporteSeleccionado;
  final ValueChanged<SportType?> onDeporteSeleccionado;

  const PlayerMatchHistoryHero({
    super.key,
    required this.totalPartidos,
    required this.pagados,
    required this.pendientes,
    required this.conteoPorDeporte,
    required this.deporteSeleccionado,
    required this.onDeporteSeleccionado,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;
    final deportesOrdenados = conteoPorDeporte.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mostrarFiltros = deportesOrdenados.length > 1;
    final gradientColors = deporteSeleccionado != null
        ? [
            SportThemeConfig.paletteFor(deporteSeleccionado!).primaryDark,
            SportThemeConfig.paletteFor(deporteSeleccionado!).primary,
          ]
        : const [
            Color(0xFF004D57),
            Color(0xFF00838F),
            Color(0xFF00ACC1),
          ];
    final shadowTint = deporteSeleccionado != null
        ? SportThemeConfig.paletteFor(deporteSeleccionado!).primary
        : const Color(0xFF00838F);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
          stops: deporteSeleccionado != null
              ? null
              : const [0.0, 0.45, 1.0],
        ),
        boxShadow: MatchPayTokens.shadowHero(shadowTint),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (deportesOrdenados.isNotEmpty)
            Positioned(
              right: 8,
              bottom: -8,
              child: Opacity(
                opacity: 0.16,
                child: Wrap(
                  spacing: 4,
                  children: deportesOrdenados.map((e) {
                    final sp = SportThemeConfig.paletteFor(e.key);
                    return Text(sp.emoji, style: const TextStyle(fontSize: 44));
                  }).toList(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('playerMatchHistoryTitle'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$totalPartidos',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.tr(
                    'playerMatchHistoryHeroCaption',
                    params: {'count': '$totalPartidos'},
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.tr(
                    'playerMatchHistoryHeroPaidLine',
                    params: {
                      'paid': '$pagados',
                      'pending': '$pendientes',
                    },
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
                if (mostrarFiltros) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SportFilterChip(
                        label: l10n.tr('playerMatchHistoryFilterAll'),
                        emoji: null,
                        count: conteoPorDeporte.values.fold(0, (a, b) => a + b),
                        selected: deporteSeleccionado == null,
                        onTap: () => onDeporteSeleccionado(null),
                      ),
                      for (final entry in deportesOrdenados)
                        _SportFilterChip(
                          label: entry.key.labelForLocale(lang),
                          emoji: SportThemeConfig.paletteFor(entry.key).emoji,
                          count: entry.value,
                          selected: deporteSeleccionado == entry.key,
                          accent: SportThemeConfig.paletteFor(entry.key).primary,
                          onTap: () => onDeporteSeleccionado(
                            deporteSeleccionado == entry.key
                                ? null
                                : entry.key,
                          ),
                        ),
                    ],
                  ),
                ] else if (deportesOrdenados.length == 1) ...[
                  const SizedBox(height: 14),
                  _SportFilterChip(
                    label: deportesOrdenados.first.key.labelForLocale(lang),
                    emoji: SportThemeConfig.paletteFor(deportesOrdenados.first.key)
                        .emoji,
                    count: deportesOrdenados.first.value,
                    selected: true,
                    accent: SportThemeConfig.paletteFor(deportesOrdenados.first.key)
                        .primary,
                    onTap: () {},
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  l10n.tr('playerMatchHistoryTapHint'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SportFilterChip extends StatelessWidget {
  final String label;
  final String? emoji;
  final int count;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;

  const _SportFilterChip({
    required this.label,
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? MatchPayTokens.ink : Colors.white;
    final bg = selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.14);
    final border = selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.22);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
            boxShadow: selected && accent != null
                ? [
                    BoxShadow(
                      color: accent!.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? (accent ?? MatchPayTokens.inkMuted).withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? (accent ?? MatchPayTokens.ink)
                        : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de partido jugado (vista jugador, no ficha de admin).
class PlayerMatchHistoryTile extends StatelessWidget {
  final DetallePartido detalle;
  final double? saldoAnteriorAlPartido;
  final PlayerMatchHistorialModo modo;
  final PlayerMatchHistoryVisual visual;
  /// Abono al registrar el partido (historial de cargo). Solo en [cuentaConDeuda].
  final double? abonoAlRegistrar;
  final bool showChevron;

  const PlayerMatchHistoryTile({
    super.key,
    required this.detalle,
    this.saldoAnteriorAlPartido,
    this.modo = PlayerMatchHistorialModo.porPartido,
    this.visual = PlayerMatchHistoryVisual.compact,
    this.abonoAlRegistrar,
    this.showChevron = false,
  });

  ({Color? color, String? label, bool mostrarDeclarado}) _estado(
    MatchPayStrings l10n,
  ) {
    final snap = saldoAnteriorAlPartido;
    final enRevision = detalle.comprobantePendienteValidacion;
    final cuentaConDeuda = modo == PlayerMatchHistorialModo.cuentaConDeuda;

    if (!cuentaConDeuda) {
      final marginal = montoMarginalPartidoCobro(
        detalle,
        null,
        saldoAnteriorPartido: snap,
      );
      final partidoCerrado = marginal <= 0.005;
      if (partidoCerrado && !enRevision) {
        return (
          color: MatchPayTokens.accentSuccess,
          label: l10n.tr('playerMatchPaid'),
          mostrarDeclarado: false,
        );
      }
      if (enRevision) {
        return (
          color: const Color(0xFFD97706),
          label: l10n.tr('cobroStatusReceiptReview'),
          mostrarDeclarado: false,
        );
      }
      if (marginal > 0.005) {
        return (
          color: MatchPayTokens.accentUrgent,
          label: l10n.tr('pendingStatus'),
          mostrarDeclarado: true,
        );
      }
      return (
        color: MatchPayTokens.accentSuccess,
        label: l10n.tr('playerMatchPaid'),
        mostrarDeclarado: false,
      );
    }
    if (enRevision) {
      return (
        color: const Color(0xFFD97706),
        label: l10n.tr('cobroStatusReceiptReview'),
        mostrarDeclarado: false,
      );
    }
    return (color: null, label: null, mostrarDeclarado: false);
  }

  @override
  Widget build(BuildContext context) {
    if (visual == PlayerMatchHistoryVisual.premium) {
      return _buildPremium(context);
    }
    return _buildCompact(context);
  }

  Widget _buildPremium(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;
    final fecha = detalle.fechaPartido;
    final recinto = detalle.recintoPartido?.trim();
    final sportPalette = detalle.sportType != null
        ? SportThemeConfig.paletteFor(detalle.sportType!)
        : context.sportPalette;
    final estado = _estado(l10n);
    final cuentaConDeuda = modo == PlayerMatchHistorialModo.cuentaConDeuda;
    final montoAbonadoAlRegistrar = cuentaConDeuda
        ? (abonoAlRegistrar ?? 0)
        : detalle.montoPagado;

    final tituloFecha = fecha != null
        ? capitalize(DateFormat('EEEE d MMM', lang).format(fecha))
        : l10n.tr('matchNumber', params: {'id': '${detalle.partidoId}'});
    final hora = fecha != null ? formatHora(fecha) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  sportPalette.primary.withValues(alpha: 0.18),
                  sportPalette.primary.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sportPalette.primary.withValues(alpha: 0.18),
              ),
            ),
            alignment: Alignment.center,
            child: detalle.sportType != null
                ? SportEmoji(sport: detalle.sportType, size: 26)
                : Icon(Icons.event_rounded, color: sportPalette.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tituloFecha,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (hora != null) ...[
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: MatchPayTokens.inkMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hora,
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (recinto != null && recinto.isNotEmpty)
                        const SizedBox(width: 8),
                    ],
                    if (recinto != null && recinto.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: MatchPayTokens.inkMuted,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                recinto,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MatchPayTokens.bodySmallStyle(),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (cuentaConDeuda && montoAbonadoAlRegistrar > 0.005) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.tr(
                      'playerMatchPaidOnRegister',
                      params: {'amount': formatMoney(montoAbonadoAlRegistrar)},
                    ),
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 11.5,
                      color: MatchPayTokens.inkMuted,
                    ),
                  ),
                ] else if (!cuentaConDeuda &&
                    estado.mostrarDeclarado &&
                    (detalle.montoPagoDeclarado ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.tr(
                      'playerMatchPaidAmount',
                      params: {
                        'amount': formatMoney(detalle.montoPagoDeclarado ?? 0),
                      },
                    ),
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 11.5,
                      color: MatchPayTokens.accentUrgent,
                    ),
                  ),
                ],
                ComprobanteHistoricoChip(detalle: detalle),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(detalle.total),
                style: MatchPayTokens.statValueStyle().copyWith(fontSize: 16),
              ),
              const SizedBox(height: 6),
              if (cuentaConDeuda)
                Text(
                  l10n.tr('playerMatchYourShare'),
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (estado.label != null && estado.color != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: estado.color!.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    estado.label!,
                    style: MatchPayTokens.sectionLabelStyle(
                      color: estado.color,
                    ).copyWith(letterSpacing: 0, fontSize: 10),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final l10n = context.l10n;
    final fecha = detalle.fechaPartido;
    final recinto = detalle.recintoPartido?.trim();
    final sportPalette = detalle.sportType != null
        ? SportThemeConfig.paletteFor(detalle.sportType!)
        : null;
    final titulo = fecha != null
        ? formatDiaCompleto(fecha)
        : l10n.tr('matchNumber', params: {'id': '${detalle.partidoId}'});
    final subtitulo = [
      if (detalle.sportType != null)
        detalle.sportType!.labelForLocale(
          context.readSettings().locale.languageCode,
        ),
      if (recinto != null && recinto.isNotEmpty) recinto,
    ].join(' · ');

    final estado = _estado(l10n);
    final cuentaConDeuda = modo == PlayerMatchHistorialModo.cuentaConDeuda;
    final montoAbonadoAlRegistrar = cuentaConDeuda
        ? (abonoAlRegistrar ?? 0)
        : detalle.montoPagado;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (sportPalette?.primary ?? MatchPayTokens.inkMuted)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: detalle.sportType != null
                ? SportEmoji(sport: detalle.sportType, size: 22)
                : Icon(Icons.event_rounded, color: MatchPayTokens.inkMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: 13.5,
                  ),
                ),
                if (subtitulo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 12,
                    ),
                  ),
                ],
                if (cuentaConDeuda && montoAbonadoAlRegistrar > 0.005) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.tr(
                      'playerMatchPaidOnRegister',
                      params: {'amount': formatMoney(montoAbonadoAlRegistrar)},
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 11.5,
                      color: MatchPayTokens.inkMuted,
                    ),
                  ),
                ] else if (!cuentaConDeuda &&
                    estado.mostrarDeclarado &&
                    (detalle.montoPagoDeclarado ?? 0) > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.tr(
                      'playerMatchPaidAmount',
                      params: {
                        'amount':
                            formatMoney(detalle.montoPagoDeclarado ?? 0),
                      },
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 11.5,
                      color: MatchPayTokens.accentUrgent,
                    ),
                  ),
                ],
                ComprobanteHistoricoChip(detalle: detalle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, maxWidth: 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatMoney(detalle.total),
                    maxLines: 1,
                    style: MatchPayTokens.statValueStyle().copyWith(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 4),
                if (cuentaConDeuda)
                  Text(
                    l10n.tr('playerMatchYourShare'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (estado.label != null && estado.color != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: estado.color!.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      estado.label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MatchPayTokens.sectionLabelStyle(
                        color: estado.color,
                      ).copyWith(
                        letterSpacing: 0,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: MatchPayTokens.inkMuted,
              size: 22,
            ),
          ],
        ],
      ),
    );
  }
}

/// Lista de partidos jugados (home, mis cobros, historial).
class PlayerMatchHistoryList extends StatelessWidget {
  final List<DetallePartido> partidos;
  final Map<int, double> saldosPorPartido;
  final PlayerMatchHistorialModo modo;
  final List<SaldoHistorico>? historialSaldo;
  final bool separatedCards;
  final bool groupByMonth;
  final PlayerMatchHistoryVisual visual;
  final void Function(DetallePartido)? onPartidoTap;

  const PlayerMatchHistoryList({
    super.key,
    required this.partidos,
    required this.saldosPorPartido,
    this.modo = PlayerMatchHistorialModo.porPartido,
    this.historialSaldo,
    this.separatedCards = false,
    this.groupByMonth = false,
    this.visual = PlayerMatchHistoryVisual.compact,
    this.onPartidoTap,
  });

  @override
  Widget build(BuildContext context) {
    final abonosAlRegistrar = modo == PlayerMatchHistorialModo.cuentaConDeuda &&
            historialSaldo != null
        ? abonoAlRegistrarPorPartido(historialSaldo!)
        : const <int, double>{};

    if (groupByMonth) {
      final lang = context.readSettings().locale.languageCode;
      final groups = <String, List<DetallePartido>>{};
      final monthDates = <String, DateTime>{};
      final sinFecha = <DetallePartido>[];
      for (final p in partidos) {
        final f = p.fechaPartido;
        if (f == null) {
          sinFecha.add(p);
          continue;
        }
        final key = '${f.year}-${f.month.toString().padLeft(2, '0')}';
        groups.putIfAbsent(key, () => []).add(p);
        monthDates.putIfAbsent(key, () => DateTime(f.year, f.month));
      }
      final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final key in sortedKeys) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                capitalize(
                  DateFormat.yMMMM(lang).format(monthDates[key]!),
                ),
                style: MatchPayTokens.sectionLabelStyle().copyWith(
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...groups[key]!.map(
              (p) => Padding(
                padding: EdgeInsets.only(
                  bottom: p == groups[key]!.last ? 16 : 10,
                ),
                child: _historyCard(
                  context,
                  p,
                  abonosAlRegistrar,
                ),
              ),
            ),
          ],
          if (sinFecha.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                context.l10n.tr('playerMatchHistorySection'),
                style: MatchPayTokens.sectionLabelStyle().copyWith(
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...sinFecha.map(
              (p) => Padding(
                padding: EdgeInsets.only(
                  bottom: p == sinFecha.last ? 0 : 10,
                ),
                child: _historyCard(context, p, abonosAlRegistrar),
              ),
            ),
          ],
        ],
      );
    }

    if (separatedCards) {
      return Column(
        children: [
          for (var i = 0; i < partidos.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < partidos.length - 1 ? 10 : 0),
              child: _historyCard(context, partidos[i], abonosAlRegistrar),
            ),
        ],
      );
    }

    return MatchPaySurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < partidos.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: MatchPayTokens.borderSubtle,
              ),
            _MatchHistoryCard(
              onTap: onPartidoTap != null
                  ? () => onPartidoTap!(partidos[i])
                  : null,
              child: PlayerMatchHistoryTile(
                detalle: partidos[i],
                saldoAnteriorAlPartido: saldosPorPartido[partidos[i].partidoId],
                modo: modo,
                visual: visual,
                abonoAlRegistrar: abonosAlRegistrar[partidos[i].partidoId],
                showChevron: onPartidoTap != null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyCard(
    BuildContext context,
    DetallePartido partido,
    Map<int, double> abonosAlRegistrar,
  ) {
    final sportPalette = partido.sportType != null
        ? SportThemeConfig.paletteFor(partido.sportType!)
        : context.sportPalette;

    final card = MatchPaySurfaceCard(
      elevated: visual == PlayerMatchHistoryVisual.premium,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          if (visual == PlayerMatchHistoryVisual.premium)
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: sportPalette.primary,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
            ),
          PlayerMatchHistoryTile(
            detalle: partido,
            saldoAnteriorAlPartido: saldosPorPartido[partido.partidoId],
            modo: modo,
            visual: visual,
            abonoAlRegistrar: abonosAlRegistrar[partido.partidoId],
          ),
        ],
      ),
    );

    if (onPartidoTap == null) return card;

    return MatchPayTapScale(
      onTap: () => onPartidoTap!(partido),
      child: card,
    );
  }
}

class _MatchHistoryCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _MatchHistoryCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        child: child,
      ),
    );
  }
}

int countPartidosPagadosHistorial(
  List<DetallePartido> partidos,
  Map<int, double> saldosPorPartido,
) {
  var pagados = 0;
  for (final p in partidos) {
    final snap = saldosPorPartido[p.partidoId];
    if (snap == null) continue;
    if (p.partidoCerradoNeto(snapshotSaldoAnterior: snap) &&
        !p.comprobantePendienteValidacion) {
      pagados++;
    }
  }
  return pagados;
}

int countPartidosPendientesHistorial(
  List<DetallePartido> partidos,
  Map<int, double> saldosPorPartido,
) {
  var pendientes = 0;
  for (final p in partidos) {
    final snap = saldosPorPartido[p.partidoId];
    if (snap == null) continue;
    if (p.tieneDeudaNeto(snapshotSaldoAnterior: snap) ||
        p.comprobantePendienteValidacion) {
      pendientes++;
    }
  }
  return pendientes;
}

Set<SportType> deportesEnHistorial(List<DetallePartido> partidos) {
  return partidos
      .map((p) => p.sportType)
      .whereType<SportType>()
      .toSet();
}

Map<SportType, int> conteoDeportesHistorial(List<DetallePartido> partidos) {
  final counts = <SportType, int>{};
  for (final p in partidos) {
    final sport = p.sportType;
    if (sport == null) continue;
    counts[sport] = (counts[sport] ?? 0) + 1;
  }
  return counts;
}

List<DetallePartido> filtrarPartidosPorDeporte(
  List<DetallePartido> partidos,
  SportType? deporte,
) {
  if (deporte == null) return partidos;
  return partidos.where((p) => p.sportType == deporte).toList();
}

/// Fila de partido cancelado en el historial del jugador.
class PlayerHistorialCanceladoTile extends StatelessWidget {
  final MiConvocatoria convocatoria;
  final PlayerMatchHistoryVisual visual;

  const PlayerHistorialCanceladoTile({
    super.key,
    required this.convocatoria,
    this.visual = PlayerMatchHistoryVisual.premium,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;
    final partido = convocatoria.partido;
    final fecha = partido.fecha;
    final recinto = partido.recinto?.trim();
    const muted = Color(0xFF525252);
    const mutedBg = Color(0xFFF3F4F6);

    final tituloFecha = capitalize(
      DateFormat('EEEE d MMM', lang).format(fecha),
    );
    final hora = formatHora(fecha);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: mutedBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MatchPayTokens.borderSubtle),
            ),
            alignment: Alignment.center,
            child: const Text('😢', style: TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tituloFecha,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: 15,
                    color: MatchPayTokens.inkSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: MatchPayTokens.inkMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hora,
                      style: MatchPayTokens.bodySmallStyle().copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (recinto != null && recinto.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: MatchPayTokens.inkMuted,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                recinto,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MatchPayTokens.bodySmallStyle(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.tr('matchStatusCancelledBody'),
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    fontSize: 11.5,
                    color: MatchPayTokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: mutedBg,
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
              border: Border.all(color: MatchPayTokens.borderSubtle),
            ),
            child: Text(
              l10n.tr('matchStatusCancelledShort'),
              style: MatchPayTokens.bodySmallStyle().copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Historial del jugador mezclando partidos jugados y cancelados.
class PlayerHistorialEntryList extends StatelessWidget {
  final List<PlayerHistorialEntry> entradas;
  final Map<int, double> saldosPorPartido;
  final PlayerMatchHistorialModo modo;
  final List<SaldoHistorico>? historialSaldo;
  final bool groupByMonth;
  final PlayerMatchHistoryVisual visual;
  final void Function(DetallePartido)? onJugadoTap;
  final void Function(MiConvocatoria)? onCanceladoTap;

  const PlayerHistorialEntryList({
    super.key,
    required this.entradas,
    required this.saldosPorPartido,
    this.modo = PlayerMatchHistorialModo.porPartido,
    this.historialSaldo,
    this.groupByMonth = false,
    this.visual = PlayerMatchHistoryVisual.premium,
    this.onJugadoTap,
    this.onCanceladoTap,
  });

  @override
  Widget build(BuildContext context) {
    final abonosAlRegistrar = modo == PlayerMatchHistorialModo.cuentaConDeuda &&
            historialSaldo != null
        ? abonoAlRegistrarPorPartido(historialSaldo!)
        : const <int, double>{};

    if (groupByMonth) {
      final lang = context.readSettings().locale.languageCode;
      final groups = <String, List<PlayerHistorialEntry>>{};
      final monthDates = <String, DateTime>{};
      final sinFecha = <PlayerHistorialEntry>[];

      for (final e in entradas) {
        final f = e.fecha;
        if (f == null) {
          sinFecha.add(e);
          continue;
        }
        final key = '${f.year}-${f.month.toString().padLeft(2, '0')}';
        groups.putIfAbsent(key, () => []).add(e);
        monthDates.putIfAbsent(key, () => DateTime(f.year, f.month));
      }
      final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final key in sortedKeys) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                capitalize(DateFormat.yMMMM(lang).format(monthDates[key]!)),
                style: MatchPayTokens.sectionLabelStyle().copyWith(
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...groups[key]!.map(
              (e) => Padding(
                padding: EdgeInsets.only(
                  bottom: e == groups[key]!.last ? 16 : 10,
                ),
                child: _entryCard(context, e, abonosAlRegistrar),
              ),
            ),
          ],
          if (sinFecha.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                context.l10n.tr('playerMatchHistorySection'),
                style: MatchPayTokens.sectionLabelStyle().copyWith(
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...sinFecha.map(
              (e) => Padding(
                padding: EdgeInsets.only(
                  bottom: e == sinFecha.last ? 0 : 10,
                ),
                child: _entryCard(context, e, abonosAlRegistrar),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0; i < entradas.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < entradas.length - 1 ? 10 : 0),
            child: _entryCard(context, entradas[i], abonosAlRegistrar),
          ),
      ],
    );
  }

  Widget _entryCard(
    BuildContext context,
    PlayerHistorialEntry entry,
    Map<int, double> abonosAlRegistrar,
  ) {
    if (entry.esCancelado) {
      final conv = entry.cancelado!;
      final card = MatchPaySurfaceCard(
        elevated: visual == PlayerMatchHistoryVisual.premium,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            if (visual == PlayerMatchHistoryVisual.premium)
              Positioned(
                left: 0,
                top: 12,
                bottom: 12,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9CA3AF),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            PlayerHistorialCanceladoTile(
              convocatoria: conv,
              visual: visual,
            ),
          ],
        ),
      );
      if (onCanceladoTap == null) return card;
      return MatchPayTapScale(
        onTap: () => onCanceladoTap!(conv),
        child: card,
      );
    }

    final detalle = entry.jugado!;
    final sportPalette = detalle.sportType != null
        ? SportThemeConfig.paletteFor(detalle.sportType!)
        : context.sportPalette;

    final card = MatchPaySurfaceCard(
      elevated: visual == PlayerMatchHistoryVisual.premium,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          if (visual == PlayerMatchHistoryVisual.premium)
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: sportPalette.primary,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
            ),
          PlayerMatchHistoryTile(
            detalle: detalle,
            saldoAnteriorAlPartido: saldosPorPartido[detalle.partidoId],
            modo: modo,
            visual: visual,
            abonoAlRegistrar: abonosAlRegistrar[detalle.partidoId],
            showChevron: onJugadoTap != null,
          ),
        ],
      ),
    );

    if (onJugadoTap == null) return card;
    return MatchPayTapScale(
      onTap: () => onJugadoTap!(detalle),
      child: card,
    );
  }
}

Map<SportType, int> conteoDeportesHistorialEntradas(
  List<PlayerHistorialEntry> entradas,
) {
  final counts = <SportType, int>{};
  for (final e in entradas) {
    final sport = e.sportType;
    if (sport == null) continue;
    counts[sport] = (counts[sport] ?? 0) + 1;
  }
  return counts;
}

List<PlayerHistorialEntry> filtrarEntradasPorDeporte(
  List<PlayerHistorialEntry> entradas,
  SportType? deporte,
) {
  if (deporte == null) return entradas;
  return entradas.where((e) => e.sportType == deporte).toList();
}

List<DetallePartido> detallesJugadosEnEntradas(
  List<PlayerHistorialEntry> entradas,
) {
  return entradas
      .where((e) => !e.esCancelado)
      .map((e) => e.jugado!)
      .toList();
}
