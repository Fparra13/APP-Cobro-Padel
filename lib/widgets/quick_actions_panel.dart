import 'package:flutter/material.dart';

import '../models/desglose_jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'recordatorio_deudores_sheet.dart';

class QuickActionsPanel extends StatelessWidget {
  final PartidoRepository partidoRepo;
  final PdfService pdfService;
  final List<ResumenJugador> resumenes;
  final VoidCallback onRefresh;
  final void Function(int tabIndex)? onNavigateTab;

  const QuickActionsPanel({
    super.key,
    required this.partidoRepo,
    required this.pdfService,
    required this.resumenes,
    required this.onRefresh,
    this.onNavigateTab,
  });

  int get _conDeuda => resumenes.where((r) => r.saldoActual > 0).length;

  @override
  Widget build(BuildContext context) {
    final acciones = <_AccionRapida>[
      _AccionRapida(
        icon: Icons.picture_as_pdf_rounded,
        label: 'PDF saldos',
        subtitulo: 'Informe del grupo',
        color: Colors.deepOrange,
        onTap: () => pdfService.generarReporteSaldos(resumenes),
      ),
      _AccionRapida(
        icon: Icons.history_rounded,
        label: 'Último partido',
        subtitulo: 'Ver o editar',
        color: Colors.blue,
        onTap: () => _abrirUltimoPartido(context),
      ),
      if (_conDeuda > 0)
        _AccionRapida(
          icon: Icons.chat_rounded,
          label: 'Recordar deudores',
          subtitulo: '$_conDeuda por WhatsApp',
          color: Colors.green.shade700,
          onTap: () => RecordatorioDeudoresSheet.show(
            context,
            resumenes: resumenes,
          ),
        ),
      _AccionRapida(
        icon: Icons.people_rounded,
        label: 'Jugadores',
        subtitulo: 'Gestionar grupo',
        color: Colors.teal,
        onTap: () => onNavigateTab?.call(1),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Herramientas',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
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
    final ultimo = await partidoRepo.getUltimoPartido();
    if (!context.mounted) return;

    if (ultimo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aún no hay partidos registrados')),
      );
      return;
    }

    final desglose = await partidoRepo.getDesglose(ultimo.partido.id!);
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
        onPdf: () {
          Navigator.pop(ctx);
          pdfService.generarReportePartido(ultimo);
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
      color: accion.color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: accion.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accion.color.withValues(alpha: 0.18)),
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
  final VoidCallback onPdf;

  const _UltimoPartidoSheet({
    required this.completo,
    required this.desglose,
    required this.onEditar,
    required this.onPdf,
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
                  'Último partido',
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
                        label: 'Jugadores',
                      ),
                      _ResumenChip(
                        valor: '$pagados',
                        label: 'Pagaron',
                      ),
                      if (parciales > 0)
                        _ResumenChip(
                          valor: '$parciales',
                          label: 'Parcial',
                        ),
                      _ResumenChip(
                        valor: '$deben',
                        label: 'Pendientes',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Estado de pagos',
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
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEditar,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'),
                    ),
                  ),
                ],
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
    final estado = _estadoPago(desglose);
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

_EstadoPagoVisual _estadoPago(DesgloseJugador d) {
  if (d.pagado) {
    if (d.generaSaldoAFavor) {
      return _EstadoPagoVisual(
        etiqueta: 'Pagado',
        monto: 'A favor ${formatMoney(-d.saldoRestante)}',
        detalle: d.montoPagado > 0
            ? 'Abonó ${formatMoney(d.montoPagado)} · Partido ${formatMoney(d.totalPartido)}'
            : 'Partido ${formatMoney(d.totalPartido)}',
        color: Colors.blue,
        icon: Icons.savings_rounded,
      );
    }
    if (d.saldoFavorAplicado > 0 && d.montoPagado == 0) {
      return _EstadoPagoVisual(
        etiqueta: 'Pagado',
        monto: 'Saldo a favor',
        detalle:
            '−${formatMoney(d.saldoFavorAplicado)} aplicado al partido',
        color: Colors.green,
        icon: Icons.check_circle_rounded,
      );
    }
    return _EstadoPagoVisual(
      etiqueta: 'Pagado',
      monto: d.montoPagado > 0 ? formatMoney(d.montoPagado) : 'Al día',
      detalle: 'Partido ${formatMoney(d.totalPartido)}'
          '${d.saldoAnterior > 0 ? ' · Deuda ant. ${formatMoney(d.saldoAnterior)}' : ''}',
      color: Colors.green,
      icon: Icons.check_circle_rounded,
    );
  }

  if (d.pagoParcial) {
    return _EstadoPagoVisual(
      etiqueta: 'Parcial',
      monto: 'Debe ${formatMoney(d.saldoRestante)}',
      detalle:
          'Abonó ${formatMoney(d.montoPagado)} de ${formatMoney(d.totalDebido)}',
      color: Colors.orange,
      icon: Icons.payments_rounded,
    );
  }

  final debe = d.saldoRestante > 0 ? d.saldoRestante : d.totalDebido;
  final detalle = StringBuffer('Partido ${formatMoney(d.totalPartido)}');
  if (d.saldoAnterior > 0) {
    detalle.write(' · Deuda ant. ${formatMoney(d.saldoAnterior)}');
  } else if (d.saldoAnterior < 0) {
    detalle.write(' · Tenía a favor ${formatMoney(-d.saldoAnterior)}');
  }

  return _EstadoPagoVisual(
    etiqueta: 'Debe',
    monto: formatMoney(debe > 0 ? debe : d.totalPartido),
    detalle: detalle.toString(),
    color: Colors.red,
    icon: Icons.warning_amber_rounded,
  );
}

