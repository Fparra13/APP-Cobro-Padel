import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../domain/deuda_explicacion.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'cobro_pago_flow.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/sport_icon.dart';

/// Resumen único de cobros pendientes (Home y Mis cobros).
class PlayerPendingSummaryCard extends StatelessWidget {
  final double total;
  final int count;
  final bool pagando;
  final VoidCallback onPayTotal;
  final VoidCallback onPayAbono;
  final String? deportesResumen;
  final String? bannerKey;
  final Map<String, String> bannerParams;

  const PlayerPendingSummaryCard({
    super.key,
    required this.total,
    required this.count,
    required this.pagando,
    required this.onPayTotal,
    required this.onPayAbono,
    this.deportesResumen,
    this.bannerKey,
    this.bannerParams = const {},
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MatchPaySurfaceCard(
      urgent: true,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.tr('playerTotalPendingLabel'),
            style: MatchPayTokens.bodySmallStyle().copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(total),
            style: MatchPayTokens.headlineStyle().copyWith(fontSize: 32),
          ),
          const SizedBox(height: 6),
          Text(
            bannerKey != null
                ? l10n.tr(bannerKey!, params: bannerParams)
                : count == 1
                    ? l10n.tr('playerCloseMatchBannerOne')
                    : l10n.tr(
                        'playerCloseMatchBannerMany',
                        params: {'count': '$count'},
                      ),
            style: MatchPayTokens.bodySmallStyle(),
          ),
          if (deportesResumen != null && deportesResumen!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              deportesResumen!,
              style: MatchPayTokens.bodySmallStyle().copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton(
              onPressed: pagando ? null : onPayTotal,
              style: FilledButton.styleFrom(
                backgroundColor: MatchPayTokens.accentUrgent,
              ),
              child: pagando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.tr('cobrosPayTotalBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: pagando ? null : onPayAbono,
              child: Text(l10n.tr('cobrosAbonoShort')),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.tr('cobrosAutoApplyHint'),
            style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Filas legibles del desglose de deuda (misma lógica que la tarjeta superior).
class DeudaExplicacionLineas extends StatelessWidget {
  final ExplicacionDeudaJugador explicacion;
  final bool showTotalFooter;

  const DeudaExplicacionLineas({
    super.key,
    required this.explicacion,
    this.showTotalFooter = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...explicacion.lineas.map((linea) {
          final montoTxt = linea.esResta
              ? '−${formatMoney(linea.monto)}'
              : formatMoney(linea.monto);
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.tr(linea.labelKey),
                    style: MatchPayTokens.bodySmallStyle(),
                  ),
                ),
                Text(
                  montoTxt,
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }),
        if (showTotalFooter) ...[
          Divider(color: MatchPayTokens.borderSubtle, height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.tr('deudaSimpleYouOwe'),
                  style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 14),
                ),
              ),
              Text(
                formatMoney(explicacion.deudaActual),
                style: MatchPayTokens.titleSmallStyle().copyWith(
                  fontSize: 15,
                  color: MatchPayTokens.accentUrgent,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Teaser de aporte pendiente en Home: encuentro + monto + pagar / detalle.
class PlayerHomeCobrosTeaser extends StatelessWidget {
  final double total;
  final bool pagando;
  final bool comprobanteEnRevision;
  final ExplicacionDeudaJugador? explicacion;
  final String? partidoLinea;
  final int encuentrosPendientes;
  final VoidCallback onPayTotal;
  final VoidCallback onPayOther;
  final VoidCallback? onVerDetalle;

  const PlayerHomeCobrosTeaser({
    super.key,
    required this.total,
    required this.pagando,
    required this.comprobanteEnRevision,
    this.explicacion,
    this.partidoLinea,
    this.encuentrosPendientes = 1,
    required this.onPayTotal,
    required this.onPayOther,
    this.onVerDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final subtituloExplicacion = explicacion?.subtituloKey != null
        ? l10n.tr(
            explicacion!.subtituloKey!,
            params: explicacion!.subtituloParams,
          )
        : null;
    final contextoEncuentro = (() {
      final linea = partidoLinea?.trim();
      if (encuentrosPendientes <= 1) {
        return linea ?? '';
      }
      final extras = encuentrosPendientes - 1;
      if (linea == null || linea.isEmpty) {
        return l10n.tr(
          'playerHomeCobrosTeaserManyCount',
          params: {'count': '$encuentrosPendientes'},
        );
      }
      return l10n.tr(
        'playerHomeCobrosTeaserMany',
        params: {
          'count': '$extras',
          'match': linea,
        },
      );
    })();

    return MatchPaySurfaceCard(
      urgent: !comprobanteEnRevision,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comprobanteEnRevision) ...[
            MatchPayStatusBanner(
              icon: Icons.hourglass_top_rounded,
              message: l10n.tr('paymentPendingApprovalBody'),
              urgent: true,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: MatchPayTokens.accentUrgent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 22,
                  color: MatchPayTokens.accentUrgent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('playerHomeCobrosTeaserLabel'),
                      style: MatchPayTokens.bodySmallStyle().copyWith(
                        fontWeight: FontWeight.w700,
                        color: MatchPayTokens.accentUrgent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(total),
                      style: MatchPayTokens.titleSmallStyle().copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (contextoEncuentro.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        contextoEncuentro.trim(),
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (subtituloExplicacion != null &&
                        subtituloExplicacion.isNotEmpty &&
                        subtituloExplicacion != contextoEncuentro) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtituloExplicacion,
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: pagando
                  ? null
                  : () {
                      if (comprobanteEnRevision) {
                        CobroPagoFlow.mostrarComprobanteEnRevision(context);
                        return;
                      }
                      onPayTotal();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: MatchPayTokens.accentUrgent,
              ),
              child: pagando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.tr('cobrosPayTotalBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: pagando
                        ? null
                        : () {
                            if (comprobanteEnRevision) {
                              CobroPagoFlow.mostrarComprobanteEnRevision(
                                context,
                              );
                              return;
                            }
                            onPayOther();
                          },
                    child: Text(l10n.tr('cobrosAbonoShort')),
                  ),
                ),
              ),
              if (onVerDetalle != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: pagando ? null : onVerDetalle,
                      child: Text(l10n.tr('cobrosViewDetail')),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Hero único de Mis cobros: monto + contexto + desglose colapsable + pagar.
class PlayerMisCobrosHeroCard extends StatelessWidget {
  final double total;
  final bool pagando;
  final bool comprobanteEnRevision;
  final ExplicacionDeudaJugador? explicacion;
  final String? partidoLinea;
  final String? deportesResumen;
  final VoidCallback onPayTotal;
  final VoidCallback onPayAbono;
  final VoidCallback? onVerDetallePartido;

  const PlayerMisCobrosHeroCard({
    super.key,
    required this.total,
    required this.pagando,
    required this.comprobanteEnRevision,
    this.explicacion,
    this.partidoLinea,
    this.deportesResumen,
    required this.onPayTotal,
    required this.onPayAbono,
    this.onVerDetallePartido,
  });

  bool get _mostrarDesglose {
    final e = explicacion;
    if (e == null) return false;
    if (e.lineas.length > 1) return true;
    final unica = e.lineas.first;
    return unica.labelKey != 'deudaSimpleYouOweOnly';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final subtitulo = explicacion?.subtituloKey != null
        ? l10n.tr(
            explicacion!.subtituloKey!,
            params: explicacion!.subtituloParams,
          )
        : partidoLinea;

    return MatchPaySurfaceCard(
      urgent: !comprobanteEnRevision,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comprobanteEnRevision) ...[
            MatchPayStatusBanner(
              icon: Icons.hourglass_top_rounded,
              message: l10n.tr('paymentPendingApprovalBody'),
              urgent: true,
            ),
            const SizedBox(height: 14),
          ],
          Text(
            formatMoney(total),
            style: MatchPayTokens.headlineStyle().copyWith(fontSize: 34),
          ),
          if (subtitulo != null && subtitulo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitulo,
              style: MatchPayTokens.bodySmallStyle().copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (partidoLinea != null &&
              explicacion?.subtituloKey != null &&
              partidoLinea!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              partidoLinea!,
              style: MatchPayTokens.bodySmallStyle(),
            ),
          ],
          if (deportesResumen != null && deportesResumen!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              deportesResumen!,
              style: MatchPayTokens.bodySmallStyle(),
            ),
          ],
          if (_mostrarDesglose && explicacion != null) ...[
            const SizedBox(height: 4),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  l10n.tr('misCobrosBreakdownExpand'),
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: 13,
                    color: MatchPayTokens.accentUrgent,
                  ),
                ),
                children: [
                  DeudaExplicacionLineas(
                    explicacion: explicacion!,
                    showTotalFooter: false,
                  ),
                ],
              ),
            ),
          ],
          // Misma jerarquía que el teaser del Home: pagar primero;
          // «Otro monto» y «Ver detalle» como secundarios.
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  (pagando || comprobanteEnRevision) ? null : onPayTotal,
              style: FilledButton.styleFrom(
                backgroundColor: MatchPayTokens.accentUrgent,
              ),
              child: pagando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.tr('cobrosPayTotalBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: (pagando || comprobanteEnRevision)
                        ? null
                        : onPayAbono,
                    child: Text(l10n.tr('cobrosAbonoShort')),
                  ),
                ),
              ),
              if (onVerDetallePartido != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: pagando ? null : onVerDetallePartido,
                      child: Text(l10n.tr('cobrosViewDetail')),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr('cobrosAutoApplyHint'),
            style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Resumen superior: total multi-org (sin CTA de pago).
class PlayerMisCobrosTotalResumen extends StatelessWidget {
  final double total;

  const PlayerMisCobrosTotalResumen({super.key, required this.total});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MatchPaySurfaceCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.tr('myChargesScreenTitle'),
            style: MatchPayTokens.bodySmallStyle().copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(total),
            style: MatchPayTokens.headlineStyle().copyWith(fontSize: 32),
          ),
        ],
      ),
    );
  }
}

/// Una cuenta pendiente con un organizador concreto.
class PlayerCuentaOrganizadorPendienteCard extends StatelessWidget {
  final String organizadorNombre;
  final double deuda;
  final bool pagando;
  final bool comprobanteEnRevision;
  final VoidCallback onPayTotal;
  final VoidCallback onPayAbono;
  final VoidCallback? onVerDetalle;

  const PlayerCuentaOrganizadorPendienteCard({
    super.key,
    required this.organizadorNombre,
    required this.deuda,
    required this.pagando,
    required this.comprobanteEnRevision,
    required this.onPayTotal,
    required this.onPayAbono,
    this.onVerDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bloqueado = pagando || comprobanteEnRevision;
    return MatchPaySurfaceCard(
      urgent: !comprobanteEnRevision,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comprobanteEnRevision) ...[
            MatchPayStatusBanner(
              icon: Icons.hourglass_top_rounded,
              message: l10n.tr('paymentPendingApprovalBody'),
              urgent: true,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            organizadorNombre,
            style: MatchPayTokens.titleSmallStyle().copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(deuda),
            style: MatchPayTokens.headlineStyle().copyWith(fontSize: 26),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: FilledButton(
              onPressed: bloqueado ? null : onPayTotal,
              style: FilledButton.styleFrom(
                backgroundColor: MatchPayTokens.accentUrgent,
              ),
              child: pagando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.tr('cobrosPayTotalBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: bloqueado ? null : onPayAbono,
                    child: Text(l10n.tr('cobrosAbonoShort')),
                  ),
                ),
              ),
              if (onVerDetalle != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: pagando ? null : onVerDetalle,
                      child: Text(l10n.tr('cobrosViewDetail')),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Al día en cuenta; opcionalmente con saldo a favor.
class PlayerCuentaAlDiaCard extends StatelessWidget {
  final double saldoAFavor;

  const PlayerCuentaAlDiaCard({
    super.key,
    required this.saldoAFavor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 48,
            color: MatchPayTokens.accentSuccess,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.tr('playerStatusUpToDate'),
            style: MatchPayTokens.titleSmallStyle(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.tr('playerStatusUpToDateSub'),
            style: MatchPayTokens.bodySmallStyle(),
            textAlign: TextAlign.center,
          ),
          if (saldoAFavor > 0.005) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MatchPayTokens.accentSuccess.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.tr(
                  'playerCreditBalance',
                  params: {'amount': formatMoney(saldoAFavor)},
                ),
                style: MatchPayTokens.bodySmallStyle().copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.tr('playerCreditBalanceHint'),
              style: MatchPayTokens.bodySmallStyle(),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Desglose «¿por qué debo X?» en home / mis cobros del jugador.
class PlayerDeudaExplicacionCard extends StatelessWidget {
  final ExplicacionDeudaJugador explicacion;
  final String? partidoLinea;
  final VoidCallback? onVerDetalle;

  const PlayerDeudaExplicacionCard({
    super.key,
    required this.explicacion,
    this.partidoLinea,
    this.onVerDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MatchPaySurfaceCard(
      urgent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_rounded,
                  color: MatchPayTokens.accentUrgent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.tr(
                    'deudaSimpleTitle',
                    params: {
                      'amount': formatMoney(explicacion.deudaActual),
                    },
                  ),
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (partidoLinea != null) ...[
            const SizedBox(height: 8),
            Text(
              partidoLinea!,
              style: MatchPayTokens.bodySmallStyle().copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          DeudaExplicacionLineas(
            explicacion: explicacion,
          ),
          if (onVerDetalle != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onVerDetalle,
                child: Text(l10n.tr('cobrosViewDetail')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? lineaPartidoDetalle(DetallePartido? detalle) {
  if (detalle == null) return null;
  final recinto = detalle.recintoPartido?.trim();
  if (detalle.fechaPartido != null) {
    final fecha = formatDiaCompleto(detalle.fechaPartido!);
    if (recinto != null && recinto.isNotEmpty) return '$fecha · $recinto';
    return fecha;
  }
  return null;
}

/// Fila compacta de partido por cerrar (Home jugador).
class PlayerMatchToCloseTile extends StatelessWidget {
  final DetallePartido detalle;
  final DesgloseJugador? desglose;
  final double? saldoAnteriorAlPartido;
  final VoidCallback onVerDetalle;

  const PlayerMatchToCloseTile({
    super.key,
    required this.detalle,
    this.desglose,
    this.saldoAnteriorAlPartido,
    required this.onVerDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;
    final sport = detalle.sportType;
    final palette = sport != null
        ? SportThemeConfig.paletteFor(sport)
        : null;
    final pendiente = montoMarginalPartidoCobro(
      detalle,
      desglose,
      saldoAnteriorPartido: saldoAnteriorAlPartido,
    );
    final antiguedad = antiguedadPartidoTexto(detalle.fechaPartido);
    final recinto = detalle.recintoPartido?.trim();
    final sportLabel = sport?.labelForLang(lang) ?? '';
    final subtitulo = [
      if (sportLabel.isNotEmpty) sportLabel,
      if (recinto != null && recinto.isNotEmpty) recinto,
      if (antiguedad.isNotEmpty) antiguedad,
    ].join(' · ');

    return InkWell(
      onTap: onVerDetalle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (palette?.primary ?? MatchPayTokens.inkMuted)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: sport != null
                      ? SportEmoji(sport: sport, size: 22)
                      : Icon(Icons.event_rounded, color: MatchPayTokens.inkMuted),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tituloDetallePartido(detalle, l10n),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MatchPayTokens.titleSmallStyle()
                            .copyWith(fontSize: 14),
                      ),
                      if (subtitulo.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MatchPayTokens.bodySmallStyle(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoney(pendiente),
                  style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onVerDetalle,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text(l10n.tr('cobrosViewDetail')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerMatchesToCloseList extends StatelessWidget {
  final List<DetallePartido> deudas;
  final Map<int, DesgloseJugador?> desgloses;
  final Map<int, double>? saldosAnterioresPorPartido;
  final double? saldoAcumuladoJugador;
  final void Function(DetallePartido detalle) onVerDetalle;

  const PlayerMatchesToCloseList({
    super.key,
    required this.deudas,
    required this.desgloses,
    this.saldosAnterioresPorPartido,
    this.saldoAcumuladoJugador,
    required this.onVerDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visibles = cobrosVisiblesJugador(
      deudas: deudas,
      desgloses: desgloses,
      saldosAnterioresPorPartido: saldosAnterioresPorPartido,
      saldoAcumuladoJugador: saldoAcumuladoJugador,
    );
    final tiles = <DetallePartido>[
      if (visibles.ancla != null) visibles.ancla!,
      ...visibles.otros,
    ];
    if (tiles.isEmpty) {
      final sorted = ordenarCobrosPorAtencion(
        deudas,
        saldosAnterioresPorPartido: saldosAnterioresPorPartido,
      );
      tiles.addAll(sorted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatchPaySectionHeader(
          title: l10n.tr('playerMatchesToCloseTitle'),
          count: tiles.length,
          accent: true,
        ),
        const SizedBox(height: 8),
        MatchPaySurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: MatchPayTokens.borderSubtle,
                  ),
                PlayerMatchToCloseTile(
                  detalle: tiles[i],
                  desglose: desgloses[tiles[i].partidoId],
                  saldoAnteriorAlPartido:
                      saldosAnterioresPorPartido?[tiles[i].partidoId],
                  onVerDetalle: () => onVerDetalle(tiles[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
