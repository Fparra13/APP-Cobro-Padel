import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../repositories/partido_repository.dart';
import '../utils/formatters.dart';
import 'matchpay_ui.dart';
import 'recordatorio_deudores_sheet.dart';

/// Acciones rápidas del organizador: último partido, recordar deudores, jugadores.
class QuickActionsPanel extends StatelessWidget {
  final List<ResumenJugador> resumenes;
  final PartidoCompleto? ultimoPartido;
  final List<DesgloseJugador>? ultimoPartidoDesglose;
  final VoidCallback onRefresh;
  final void Function(int tabIndex)? onNavigateTab;
  final bool readOnly;
  final VoidCallback? onReadOnlyTap;

  const QuickActionsPanel({
    super.key,
    required this.resumenes,
    required this.onRefresh,
    this.ultimoPartido,
    this.ultimoPartidoDesglose,
    this.onNavigateTab,
    this.readOnly = false,
    this.onReadOnlyTap,
  });

  int get _conDeuda => resumenes.where((r) => r.tieneDeuda).length;

  String _ultimoPartidoLineas(MatchPayStrings l10n) {
    final p = ultimoPartido;
    if (p == null) return l10n.tr('lastMatchEmptyHint');
    return formatFechaCorta(p.partido.fecha);
  }

  String? _ultimoPartidoRecinto(MatchPayStrings l10n) {
    final p = ultimoPartido;
    if (p == null) return null;
    final recinto = p.partido.recinto?.trim();
    if (recinto == null || recinto.isEmpty) return l10n.tr('noVenue');
    return recinto;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final acciones = <_AccionRapida>[
      _AccionRapida(
        icon: Icons.history_rounded,
        label: l10n.tr('lastMatch'),
        linea1: _ultimoPartidoLineas(l10n),
        linea2: _ultimoPartidoRecinto(l10n),
        accent: MatchPayTokens.accentCredit,
        onTap: () => _abrirUltimoPartido(context),
      ),
      if (_conDeuda > 0)
        _AccionRapida(
          icon: Icons.chat_rounded,
          label: l10n.tr('remindDebtors'),
          linea1: l10n.tr(
            'remindDebtorsPush',
            params: {'count': '$_conDeuda'},
          ),
          linea2: '',
          accent: MatchPayTokens.accentSuccess,
          onTap: () {
            if (readOnly) {
              onReadOnlyTap?.call();
              return;
            }
            RecordatorioDeudoresSheet.show(
              context,
              resumenes: resumenes,
            );
          },
        ),
      _AccionRapida(
        icon: Icons.people_rounded,
        label: l10n.tr('navPlayers'),
        linea1: l10n.tr('manageGroup'),
        linea2: '',
        accent: MatchPayTokens.inkSecondary,
        onTap: () => onNavigateTab?.call(2),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatchPaySectionHeader(title: l10n.tr('homeQuickActions')),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;
            if (wide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < acciones.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: _AccionCard(accion: acciones[i])),
                    ],
                  ],
                ),
              );
            }
            return _AccionesGrid(
              acciones: acciones,
              maxWidth: constraints.maxWidth,
            );
          },
        ),
      ],
    );
  }

  Future<void> _abrirUltimoPartido(BuildContext context) async {
    if (readOnly && (ultimoPartidoDesglose == null || ultimoPartidoDesglose!.isEmpty)) {
      onReadOnlyTap?.call();
      return;
    }
    final ultimo =
        ultimoPartido ?? await context.repos.getUltimoPartido();
    if (!context.mounted) return;

    if (ultimo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('noMatchesYet'))),
      );
      return;
    }

    final partidoId = ultimo.partido.id;
    if (partidoId == null) return;

    final cached = ultimoPartidoDesglose;
    if (cached != null && cached.isNotEmpty) {
      await _mostrarUltimoPartidoSheet(context, ultimo, cached);
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final desglose = await context.repos.getDesglose(
        partidoId,
        reconciliar: false,
        repararCuenta: false,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await _mostrarUltimoPartidoSheet(context, ultimo, desglose);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.userError(e))),
      );
    }
  }

  Future<void> _mostrarUltimoPartidoSheet(
    BuildContext context,
    PartidoCompleto ultimo,
    List<DesgloseJugador> desglose,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _UltimoPartidoSheet(
        completo: ultimo,
        desglose: desglose,
        onEditar: () {
          Navigator.pop(ctx);
          Navigator.pushNamed(
            context,
            '/editar-partido',
            arguments: ultimo.partido.id,
          ).then((_) => onRefresh());
        },
      ),
    );
  }
}

class _AccionesGrid extends StatelessWidget {
  final List<_AccionRapida> acciones;
  final double maxWidth;

  const _AccionesGrid({
    required this.acciones,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (acciones.length == 1) {
      return _AccionCard(accion: acciones.first);
    }

    final half = (maxWidth - 10) / 2;

    if (acciones.length == 2) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _AccionCard(accion: acciones[0])),
            const SizedBox(width: 10),
            Expanded(child: _AccionCard(accion: acciones[1])),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _AccionCard(accion: acciones[0])),
              const SizedBox(width: 10),
              Expanded(child: _AccionCard(accion: acciones[1])),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: half,
          child: _AccionCard(accion: acciones[2]),
        ),
      ],
    );
  }
}

class _AccionRapida {
  final IconData icon;
  final String label;
  final String linea1;
  final String? linea2;
  final Color accent;
  final VoidCallback onTap;

  const _AccionRapida({
    required this.icon,
    required this.label,
    required this.linea1,
    this.linea2,
    required this.accent,
    required this.onTap,
  });
}

class _AccionCard extends StatelessWidget {
  static const _slotLinea2 = 14.0;

  final _AccionRapida accion;

  const _AccionCard({required this.accion});

  @override
  Widget build(BuildContext context) {
    final subtituloStyle = MatchPayTokens.bodySmallStyle().copyWith(fontSize: 11);
    final linea2 = accion.linea2?.trim() ?? '';

    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(12),
      onTap: accion.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accion.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(accion.icon, color: accion.accent, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            accion.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MatchPayTokens.titleSmallStyle(),
          ),
          const SizedBox(height: 2),
          Text(
            accion.linea1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subtituloStyle,
          ),
          SizedBox(
            height: _slotLinea2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                linea2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtituloStyle.copyWith(
                  color: linea2.isEmpty
                      ? Colors.transparent
                      : MatchPayTokens.inkMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UltimoPartidoSheet extends StatelessWidget {
  final PartidoCompleto completo;
  final List<DesgloseJugador> desglose;
  final VoidCallback onEditar;

  const _UltimoPartidoSheet({
    required this.completo,
    required this.desglose,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final partido = completo.partido;
    final fecha = formatFecha(partido.fecha);
    final recinto = partido.recinto?.trim();
    final pagados = desglose.where((d) => d.pagado).length;
    final parciales = desglose.where((d) => d.pagoParcial).length;
    final deben = desglose.length - pagados;

    final ordenados = List<DesgloseJugador>.from(desglose)
      ..sort((a, b) {
        int prio(DesgloseJugador d) {
          if (d.pagoParcial) return 1;
          if (!d.pagado) return 0;
          return 2;
        }

        final cmp = prio(a).compareTo(prio(b));
        if (cmp != 0) return cmp;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                Text(
                  context.tr('lastMatch'),
                  style: MatchPayTokens.titleMediumStyle().copyWith(
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(fecha, style: MatchPayTokens.bodySmallStyle()),
                if (recinto != null && recinto.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 16,
                        color: MatchPayTokens.inkMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          recinto,
                          style: MatchPayTokens.bodySmallStyle(),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        MatchPayTokens.accentCredit,
                        MatchPayTokens.accentCredit.withValues(alpha: 0.82),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius:
                        BorderRadius.circular(MatchPayTokens.radiusChip),
                  ),
                  child: Row(
                    children: [
                      _ResumenChip(
                        valor: '${desglose.length}',
                        label: context.tr('navPlayers'),
                      ),
                      _ResumenChip(
                        valor: '$pagados',
                        label: context.tr('paidPlayersLabel'),
                      ),
                      if (parciales > 0)
                        _ResumenChip(
                          valor: '$parciales',
                          label: context.tr('partialLabel'),
                        ),
                      _ResumenChip(
                        valor: '$deben',
                        label: context.tr('pendingLabel'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('paymentStatusTitle'),
                  style: MatchPayTokens.titleSmallStyle(),
                ),
                const SizedBox(height: 8),
                ...ordenados.map((d) => _JugadorPagoTile(desglose: d)),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onEditar,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.tr('editMatchTitle')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumenChip extends StatelessWidget {
  final String valor;
  final String label;

  const _ResumenChip({required this.valor, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _JugadorPagoTile extends StatelessWidget {
  final DesgloseJugador desglose;

  const _JugadorPagoTile({required this.desglose});

  @override
  Widget build(BuildContext context) {
    final estado = _estadoPago(context, desglose);
    final inicial = desglose.nombre.trim().isNotEmpty
        ? desglose.nombre.trim()[0].toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: estado.color.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
        border: Border.all(color: estado.color.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: estado.color.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  inicial,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: estado.color.shade800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desglose.nombre,
                    style: MatchPayTokens.titleSmallStyle(),
                  ),
                  if (estado.detalle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      estado.detalle!,
                      style: MatchPayTokens.bodySmallStyle().copyWith(
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: estado.color.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(estado.icon, size: 13, color: estado.color.shade800),
                      const SizedBox(width: 4),
                      Text(
                        estado.etiqueta,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: estado.color.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  estado.monto,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: estado.color.shade900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoPagoVisual {
  final String etiqueta;
  final String monto;
  final String? detalle;
  final MaterialColor color;
  final IconData icon;

  const _EstadoPagoVisual({
    required this.etiqueta,
    required this.monto,
    required this.color,
    required this.icon,
    this.detalle,
  });
}

_EstadoPagoVisual _estadoPago(BuildContext context, DesgloseJugador d) {
  if (d.pagado) {
    if (d.generaSaldoAFavor) {
      return _EstadoPagoVisual(
        etiqueta: context.tr('paidStatus'),
        monto: context.tr(
          'creditAmountLabel',
          params: {'amount': formatMoney(-d.saldoRestante)},
        ),
        detalle: d.montoPagado > 0
            ? context.tr(
                'paidDetailLine',
                params: {
                  'paid': formatMoney(d.montoPagado),
                  'match': formatMoney(d.totalPartido),
                },
              )
            : context.tr(
                'matchAmountShort',
                params: {'amount': formatMoney(d.totalPartido)},
              ),
        color: Colors.blue,
        icon: Icons.savings_rounded,
      );
    }
    if (d.saldoFavorAplicado > 0 && d.montoPagado == 0) {
      return _EstadoPagoVisual(
        etiqueta: context.tr('paidStatus'),
        monto: context.tr('creditBalanceLabel'),
        detalle: context.tr(
          'creditAppliedLine',
          params: {'amount': formatMoney(d.saldoFavorAplicado)},
        ),
        color: Colors.green,
        icon: Icons.check_circle_rounded,
      );
    }
    return _EstadoPagoVisual(
      etiqueta: context.tr('paidStatus'),
      monto: d.montoPagado > 0
          ? formatMoney(d.montoPagado)
          : context.tr('statusUpToDate'),
      detalle: context.tr(
            'matchAmountShort',
            params: {'amount': formatMoney(d.totalPartido)},
          ) +
          (d.saldoAnterior > 0
              ? ' · ${context.tr('oldDebtShort', params: {'amount': formatMoney(d.saldoAnterior)})}'
              : ''),
      color: Colors.green,
      icon: Icons.check_circle_rounded,
    );
  }

  if (d.pagoParcial) {
    return _EstadoPagoVisual(
      etiqueta: context.tr('partialLabel'),
      monto: context.tr(
        'owesAmountLabel',
        params: {'amount': formatMoney(d.saldoRestante)},
      ),
      detalle: context.tr(
        'paidPartialDetail',
        params: {
          'paid': formatMoney(d.montoPagado),
          'total': formatMoney(d.totalDebido),
        },
      ),
      color: Colors.orange,
      icon: Icons.payments_rounded,
    );
  }

  final debe = d.saldoRestante > 0 ? d.saldoRestante : d.totalDebido;
  final detalle = StringBuffer(
    context.tr(
      'matchAmountShort',
      params: {'amount': formatMoney(d.totalPartido)},
    ),
  );
  if (d.saldoAnterior > 0) {
    detalle.write(
      ' · ${context.tr('oldDebtShort', params: {'amount': formatMoney(d.saldoAnterior)})}',
    );
  } else if (d.saldoAnterior < 0) {
    detalle.write(
      ' · ${context.tr('hadCreditShort', params: {'amount': formatMoney(-d.saldoAnterior)})}',
    );
  }

  return _EstadoPagoVisual(
    etiqueta: context.tr('owesStatusLabel'),
    monto: formatMoney(debe > 0 ? debe : d.totalPartido),
    detalle: detalle.toString(),
    color: Colors.red,
    icon: Icons.warning_amber_rounded,
  );
}
