import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'recordatorio_deudores_sheet.dart';

class QuickActionsPanel extends StatelessWidget {
  final AppRepositories repos;
  final PdfService pdfService;
  final List<ResumenJugador> resumenes;
  final VoidCallback onRefresh;
  final void Function(int tabIndex)? onNavigateTab;

  const QuickActionsPanel({
    super.key,
    required this.repos,
    required this.pdfService,
    required this.resumenes,
    required this.onRefresh,
    this.onNavigateTab,
  });

  int get _conDeuda => resumenes.where((r) => r.tieneDeuda).length;

  @override
  Widget build(BuildContext context) {
    final acciones = <_AccionRapida>[
      _AccionRapida(
        icon: Icons.history_rounded,
        label: context.tr('lastMatch'),
        subtitulo: context.tr('viewPaymentStatus'),
        color: Colors.blue,
        onTap: () => _abrirUltimoPartido(context),
      ),
      if (_conDeuda > 0)
        _AccionRapida(
          icon: Icons.chat_rounded,
          label: context.tr('remindDebtors'),
          subtitulo: context.tr(
            'remindDebtorsPush',
            params: {'count': '$_conDeuda'},
          ),
          color: Colors.green.shade700,
          onTap: () => RecordatorioDeudoresSheet.show(
            context,
            resumenes: resumenes,
          ),
        ),
      _AccionRapida(
        icon: Icons.people_rounded,
        label: context.tr('navPlayers'),
        subtitulo: context.tr('manageGroup'),
        color: Colors.teal,
        onTap: () => onNavigateTab?.call(2),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            context.tr('toolsTitle'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Color(0xFF111827),
              letterSpacing: -0.2,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
          ),
          itemCount: acciones.length,
          itemBuilder: (_, i) => _AccionCard(accion: acciones[i]),
        ),
      ],
    );
  }

  Future<void> _abrirUltimoPartido(BuildContext context) async {
    final ultimo = await repos.getUltimoPartido();
    if (!context.mounted) return;

    if (ultimo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('noMatchesYet'))),
      );
      return;
    }

    final desglose = await repos.getDesglose(ultimo.partido.id!);
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
  final Color color;
  final VoidCallback onTap;

  const _AccionRapida({
    required this.icon,
    required this.label,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });
}

class _AccionCard extends StatelessWidget {
  final _AccionRapida accion;

  const _AccionCard({required this.accion});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: accion.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8E6E1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accion.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(accion.icon, color: accion.color, size: 22),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accion.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    accion.subtitulo,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  fecha,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (recinto != null && recinto.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_rounded,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          recinto,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
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
                      colors: [Colors.blue.shade700, Colors.blue.shade500],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey.shade800,
                  ),
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
        borderRadius: BorderRadius.circular(14),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (estado.detalle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      estado.detalle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
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

