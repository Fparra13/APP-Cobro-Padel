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
  final VoidCallback onRefresh;
  final void Function(int tabIndex)? onNavigateTab;

  const QuickActionsPanel({
    super.key,
    required this.resumenes,
    required this.onRefresh,
    this.ultimoPartido,
    this.onNavigateTab,
  });

  int get _conDeuda => resumenes.where((r) => r.tieneDeuda).length;

  String _ultimoPartidoSubtitulo(MatchPayStrings l10n) {
    final p = ultimoPartido;
    if (p == null) return l10n.tr('viewPaymentStatus');
    final fecha = formatDiaCorto(p.partido.fecha);
    final recinto = p.partido.recinto?.trim();
    if (recinto != null && recinto.isNotEmpty) {
      return '$fecha · $recinto';
    }
    return fecha;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final acciones = <_AccionRapida>[
      _AccionRapida(
        icon: Icons.history_rounded,
        label: l10n.tr('lastMatch'),
        subtitulo: _ultimoPartidoSubtitulo(l10n),
        accent: MatchPayTokens.accentCredit,
        onTap: () => _abrirUltimoPartido(context),
      ),
      if (_conDeuda > 0)
        _AccionRapida(
          icon: Icons.chat_rounded,
          label: l10n.tr('remindDebtors'),
          subtitulo: l10n.tr(
            'remindDebtorsPush',
            params: {'count': '$_conDeuda'},
          ),
          accent: MatchPayTokens.accentSuccess,
          onTap: () => RecordatorioDeudoresSheet.show(
            context,
            resumenes: resumenes,
          ),
        ),
      _AccionRapida(
        icon: Icons.people_rounded,
        label: l10n.tr('navPlayers'),
        subtitulo: l10n.tr('manageGroup'),
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
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: acciones.length >= 3 ? 2 : acciones.length,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: acciones.length == 1 ? 2.4 : 1.55,
              ),
              itemCount: acciones.length,
              itemBuilder: (_, i) => _AccionCard(accion: acciones[i]),
            );
          },
        ),
      ],
    );
  }

  Future<void> _abrirUltimoPartido(BuildContext context) async {
    final ultimo =
        ultimoPartido ?? await context.repos.getUltimoPartido();
    if (!context.mounted) return;

    if (ultimo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('noMatchesYet'))),
      );
      return;
    }

    final desglose = await context.repos.getDesglose(ultimo.partido.id!);
    if (!context.mounted) return;

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

class _AccionRapida {
  final IconData icon;
  final String label;
  final String subtitulo;
  final Color accent;
  final VoidCallback onTap;

  const _AccionRapida({
    required this.icon,
    required this.label,
    required this.subtitulo,
    required this.accent,
    required this.onTap,
  });
}

class _AccionCard extends StatelessWidget {
  final _AccionRapida accion;

  const _AccionCard({required this.accion});

  @override
  Widget build(BuildContext context) {
    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: accion.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accion.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(accion.icon, color: accion.accent, size: 22),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accion.label,
                style: MatchPayTokens.titleSmallStyle(),
              ),
              const SizedBox(height: 2),
              Text(
                accion.subtitulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 11),
              ),
            ],
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
