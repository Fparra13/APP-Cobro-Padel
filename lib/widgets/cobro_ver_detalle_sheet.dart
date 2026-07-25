import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../domain/deuda_explicacion.dart';
import '../models/datos_pago_organizador.dart';
import '../models/desglose_jugador.dart';
import '../models/saldo_historico.dart';
import '../models/detalle_partido.dart';
import '../domain/cobro_logic.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/formatters.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/player_matches_to_close.dart';
import 'comprobante_historico_chip.dart';
import 'matchpay_ui.dart';
import 'sport_icon.dart';

/// Detalle de un partido pendiente — pago siempre vía cuenta global.
class CobroVerDetalleSheet extends StatelessWidget {
  final DetallePartido detalle;
  final DesgloseJugador? desglose;
  final VoidCallback? onPayTotal;
  final VoidCallback? onPayAbono;

  final double? saldoAnteriorAlPartido;
  final double? saldoAcumuladoJugador;
  final bool esAnclaCuenta;
  /// Nombre del organizador ya disponible en UI (sin fetch).
  final String? organizadorNombre;
  final List<SaldoHistorico>? historialSaldo;
  /// Inset de la barra de navegación / gesture (evita tapar botones).
  final double bottomSafeInset;

  const CobroVerDetalleSheet({
    super.key,
    required this.detalle,
    this.desglose,
    this.saldoAnteriorAlPartido,
    this.saldoAcumuladoJugador,
    this.esAnclaCuenta = false,
    this.organizadorNombre,
    this.historialSaldo,
    this.onPayTotal,
    this.onPayAbono,
    this.bottomSafeInset = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required DetallePartido detalle,
    DesgloseJugador? desglose,
    double? saldoAnteriorAlPartido,
    double? saldoAcumuladoJugador,
    bool esAnclaCuenta = false,
    String? organizadorNombre,
    List<SaldoHistorico>? historialSaldo,
    VoidCallback? onPayTotal,
    VoidCallback? onPayAbono,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MatchPayTokens.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final maxH = media.size.height * 0.92;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: CobroVerDetalleSheet(
            detalle: detalle,
            desglose: desglose,
            saldoAnteriorAlPartido: saldoAnteriorAlPartido,
            saldoAcumuladoJugador: saldoAcumuladoJugador,
            esAnclaCuenta: esAnclaCuenta,
            organizadorNombre: organizadorNombre,
            historialSaldo: historialSaldo,
            onPayTotal: onPayTotal,
            onPayAbono: onPayAbono,
            bottomSafeInset: media.viewPadding.bottom,
          ),
        );
      },
    );
  }

  String _titulo(MatchPayStrings l10n) => tituloDetallePartido(detalle, l10n);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snap = saldoAnteriorAlPartido ?? desglose?.saldoAnterior;
    final marginal = montoMarginalPartidoCobro(
      detalle,
      desglose,
      saldoAnteriorPartido: snap,
    );
    final pendiente = esAnclaCuenta && saldoAcumuladoJugador != null
        ? CobroLogic.obtenerPendienteJugador(
            saldoAcumulado: saldoAcumuladoJugador!,
          )
        : marginal;
    final explicacionCuenta = esAnclaCuenta &&
            saldoAcumuladoJugador != null &&
            historialSaldo != null
        ? explicarDeudaJugador(
            saldoAcumulado: saldoAcumuladoJugador!,
            historial: historialSaldo!,
          )
        : null;
    final antiguedad = antiguedadPartidoTexto(detalle.fechaPartido);
    final urgente = partidoRequiereAtencionUrgente(detalle);

    final showPayActions = (onPayTotal != null || onPayAbono != null) &&
        !detalle.comprobantePendienteValidacion &&
        pendiente > 0.005;
    final bottomPad = 16.0 + bottomSafeInset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MatchPayTokens.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (detalle.sportType != null)
                    SportEmoji(sport: detalle.sportType, size: 28)
                  else
                    Icon(Icons.sports, color: MatchPayTokens.inkMuted, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.tr('cobrosViewChargeTitle'),
                      style: MatchPayTokens.titleMediumStyle(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (esAnclaCuenta &&
                  (organizadorNombre?.trim().isNotEmpty ?? false)) ...[
                Text(
                  l10n.tr(
                    'cobrosOrganizerNamed',
                    params: {'name': organizadorNombre!.trim()},
                  ),
                  style: MatchPayTokens.bodySmallStyle(
                    color: MatchPayTokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                _titulo(l10n),
                style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 17),
              ),
              if (antiguedad.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  urgente
                      ? l10n.tr('cobrosAgeUrgent', params: {'when': antiguedad})
                      : antiguedad,
                  style: MatchPayTokens.bodySmallStyle(
                    color: urgente
                        ? MatchPayTokens.accentUrgent
                        : MatchPayTokens.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MatchPaySurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (desglose != null) ...[
                        Text(
                          l10n.tr('cobrosMatchBreakdownTitle'),
                          style: MatchPayTokens.sectionLabelStyle(),
                        ),
                        const SizedBox(height: 8),
                        DesgloseCalculoPanel(
                          desglose: desglose!,
                          soloPartidoActual: true,
                          showLineasPartido: true,
                        ),
                      ] else ...[
                        Text(
                          l10n.tr('breakdownMatchAmount'),
                          style: MatchPayTokens.bodySmallStyle(),
                        ),
                        Text(
                          formatMoney(detalle.total),
                          style: MatchPayTokens.titleSmallStyle(),
                        ),
                        if (!esAnclaCuenta &&
                            pendiente > 0.005 &&
                            detalle.montoPagado > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.tr(
                              'cobrosPartialPaid',
                              params: {
                                'paid': formatMoney(detalle.montoPagado),
                                'pending': formatMoney(pendiente),
                              },
                            ),
                            style: MatchPayTokens.bodySmallStyle(),
                          ),
                        ],
                      ],
                      if (explicacionCuenta != null) ...[
                        const SizedBox(height: 12),
                        Divider(height: 1, color: MatchPayTokens.borderSubtle),
                        const SizedBox(height: 12),
                        Text(
                          l10n.tr('cobrosAccountSummaryTitle'),
                          style: MatchPayTokens.sectionLabelStyle(),
                        ),
                        const SizedBox(height: 8),
                        DeudaExplicacionLineas(explicacion: explicacionCuenta),
                      ],
                    ],
                  ),
                ),
                if (detalle.organizadorId != null &&
                    detalle.organizadorId!.isNotEmpty &&
                    (pendiente > 0.005 ||
                        detalle.comprobantePendienteValidacion)) ...[
                  const SizedBox(height: 12),
                  _DatosPagoOrganizadorCard(
                    organizadorId: detalle.organizadorId!,
                  ),
                ],
                if (!esAnclaCuenta) ...[
                  const SizedBox(height: 8),
                  Text(
                    estadoTextoCobro(
                      detalle,
                      l10n,
                      saldoAnteriorAlPartido: snap,
                    ),
                    style: MatchPayTokens.bodySmallStyle(
                      color: detalle.comprobantePendienteValidacion
                          ? MatchPayTokens.accentUrgent
                          : (pendiente > 0.005
                              ? MatchPayTokens.inkMuted
                              : MatchPayTokens.accentSuccess),
                    ),
                  ),
                ],
                ComprobanteHistoricoChip(detalle: detalle),
              ],
            ),
          ),
        ),
        if (showPayActions)
          Material(
            color: MatchPayTokens.surfaceBase,
            elevation: 6,
            shadowColor: Colors.black26,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!esAnclaCuenta) ...[
                    Text(
                      l10n.tr(
                        'cobrosMatchPending',
                        params: {'amount': formatMoney(pendiente)},
                      ),
                      style:
                          MatchPayTokens.titleSmallStyle().copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (onPayTotal != null)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onPayTotal!();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: MatchPayTokens.accentUrgent,
                        ),
                        child: Text(l10n.tr('cobrosPayTotalBtn')),
                      ),
                    ),
                  if (onPayAbono != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onPayAbono!();
                        },
                        child: Text(l10n.tr('cobrosAbonoShort')),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    l10n.tr('cobrosAutoApplyHint'),
                    style:
                        MatchPayTokens.bodySmallStyle().copyWith(fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(height: bottomPad),
      ],
    );
  }
}
/// Datos de transferencia del organizador de ESTE cobro (multi-grupo = por cuenta).
class _DatosPagoOrganizadorCard extends StatefulWidget {
  final String organizadorId;

  const _DatosPagoOrganizadorCard({required this.organizadorId});

  @override
  State<_DatosPagoOrganizadorCard> createState() =>
      _DatosPagoOrganizadorCardState();
}

class _DatosPagoOrganizadorCardState extends State<_DatosPagoOrganizadorCard> {
  DatosPagoOrganizador? _pago;
  String? _orgNombre;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!AppRepositories.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final result = await AppRepositories.I.getDatosPagoOrganizador(
        widget.organizadorId,
      );
      if (!mounted) return;
      setState(() {
        _pago = result?.pago;
        _orgNombre = result?.organizadorNombre;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copiar() async {
    final pago = _pago;
    if (pago == null || !pago.tieneDatos) return;
    final buf = StringBuffer();
    if (pago.titularTrim.isNotEmpty) {
      buf.writeln(pago.titularTrim);
    }
    if (pago.detalleTrim.isNotEmpty) buf.writeln(pago.detalleTrim);
    if (pago.notaTrim.isNotEmpty) buf.writeln(pago.notaTrim);
    await Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('paymentInfoCopied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return MatchPaySurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MatchPayTokens.inkMuted,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.tr('paymentInfoLoading'),
              style: MatchPayTokens.bodySmallStyle(),
            ),
          ],
        ),
      );
    }

    final pago = _pago;
    if (pago == null || !pago.tieneDatos) {
      return MatchPaySurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: MatchPayTokens.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.tr('paymentInfoMissingOrganizer'),
                style: MatchPayTokens.bodySmallStyle(),
              ),
            ),
          ],
        ),
      );
    }

    final titulo = (_orgNombre != null && _orgNombre!.trim().isNotEmpty)
        ? l10n.tr(
            'paymentInfoPayToNamed',
            params: {'name': _orgNombre!.trim()},
          )
        : l10n.tr('paymentInfoPayToOrganizer');

    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: MatchPayTokens.accentCredit),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 14),
                ),
              ),
              IconButton(
                onPressed: _copiar,
                tooltip: l10n.tr('copyPaymentInfoTooltip'),
                icon: const Icon(Icons.copy_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (pago.titularTrim.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              pago.titularTrim,
              style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 14),
            ),
          ],
          if (pago.detalleTrim.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              pago.detalleTrim,
              style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 14),
            ),
          ],
          if (pago.notaTrim.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              pago.notaTrim,
              style: MatchPayTokens.bodySmallStyle(),
            ),
          ],
        ],
      ),
    );
  }
}
