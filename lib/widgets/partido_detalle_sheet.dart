import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/desglose_jugador.dart';
import '../models/jugador.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'ayuda_tip.dart';
import 'comprobante_pago_tile.dart';

/// Detalle de un partido: acciones de informes arriba, desglose abajo.
class PartidoDetalleSheet extends StatefulWidget {
  final PartidoCompleto completo;
  final List<DesgloseJugador> desglose;
  final PdfService pdfService;
  final VoidCallback? onEditar;

  const PartidoDetalleSheet({
    super.key,
    required this.completo,
    required this.desglose,
    required this.pdfService,
    this.onEditar,
  });

  static Future<void> show(
    BuildContext context, {
    required PartidoCompleto completo,
    required PartidoRepository partidoRepo,
    required PdfService pdfService,
    VoidCallback? onEditar,
  }) async {
    final desglose = await partidoRepo.getDesglose(completo.partido.id!);
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PartidoDetalleSheet(
        completo: completo,
        desglose: desglose,
        pdfService: pdfService,
        onEditar: onEditar,
      ),
    );
  }

  @override
  State<PartidoDetalleSheet> createState() => _PartidoDetalleSheetState();
}

class _PartidoDetalleSheetState extends State<PartidoDetalleSheet> {
  bool _generandoPdfGeneral = false;
  int? _generandoPdfJugadorId;

  PartidoCompleto get completo => widget.completo;
  List<DesgloseJugador> get desglose => widget.desglose;
  PdfService get pdfService => widget.pdfService;

  Future<void> _conFeedback(
    Future<void> Function() accion, {
    required String exito,
  }) async {
    try {
      await accion();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exito)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _pdfGeneral() async {
    setState(() => _generandoPdfGeneral = true);
    await _conFeedback(
      () => pdfService.generarReportePartido(completo),
      exito: 'PDF del partido listo para compartir',
    );
    if (mounted) setState(() => _generandoPdfGeneral = false);
  }

  Future<void> _pdfIndividual(DesgloseJugador d) async {
    setState(() => _generandoPdfJugadorId = d.jugadorId);
    final jugadorRepo = JugadorRepository();
    await _conFeedback(
      () async {
        final jugador = await jugadorRepo.getById(d.jugadorId);
        await pdfService.generarReportePersonal(
          completo: completo,
          desglose: d,
          jugador: jugador,
        );
      },
      exito: 'PDF de ${d.nombre} listo para compartir',
    );
    if (mounted) setState(() => _generandoPdfJugadorId = null);
  }

  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat('dd/MM/yyyy HH:mm').format(completo.partido.fecha);
    final jugadorRepo = JugadorRepository();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (_, scroll) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detalle del partido',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          fecha,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        if (completo.partido.recinto != null &&
                            completo.partido.recinto!.trim().isNotEmpty)
                          Text(
                            '📍 ${completo.partido.recinto!.trim()}',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  const AyudaTip(
                    texto:
                        '1) Genera el PDF general para ver o compartir el partido completo.\n'
                        '2) Usa WhatsApp o PDF individual junto a cada jugador (mas privado).\n'
                        '3) Abajo puedes revisar el desglose de cobros.',
                  ),
                  const SizedBox(height: 16),
                  const _SeccionTitulo(
                    icono: Icons.groups,
                    titulo: 'Informe general',
                    subtitulo: 'Todos los jugadores en un solo PDF',
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _generandoPdfGeneral ? null : _pdfGeneral,
                    icon: _generandoPdfGeneral
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(
                      _generandoPdfGeneral
                          ? 'Generando PDF...'
                          : 'Generar PDF del partido',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SeccionTitulo(
                    icono: Icons.lock_outline,
                    titulo: 'Informes individuales',
                    subtitulo: 'Envia uno a uno para mayor privacidad',
                  ),
                  const SizedBox(height: 8),
                  ...desglose.map(
                    (d) => _FilaInformeIndividual(
                      desglose: d,
                      generandoPdf: _generandoPdfJugadorId == d.jugadorId,
                      onWhatsApp: () => _enviarWhatsApp(context, jugadorRepo, d),
                      onPdf: () => _pdfIndividual(d),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onEditar,
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar partido'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SeccionComprobantesGastos(completo: completo),
                  const SizedBox(height: 20),
                  const _SeccionTitulo(
                    icono: Icons.receipt_long,
                    titulo: 'Desglose de cobros',
                    subtitulo: 'Detalle por jugador',
                  ),
                  const SizedBox(height: 8),
                  ...desglose.map((d) => _DesgloseCard(desglose: d)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviarWhatsApp(
    BuildContext context,
    JugadorRepository jugadorRepo,
    DesgloseJugador d,
  ) async {
    final Jugador? jugador = await jugadorRepo.getById(d.jugadorId);
    try {
      await pdfService.enviarWhatsAppPersonal(
        completo: completo,
        desglose: d,
        jugador: jugador,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error WhatsApp: $e')),
        );
      }
    }
  }
}

class _SeccionTitulo extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;

  const _SeccionTitulo({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                subtitulo,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilaInformeIndividual extends StatelessWidget {
  final DesgloseJugador desglose;
  final bool generandoPdf;
  final VoidCallback onWhatsApp;
  final VoidCallback onPdf;

  const _FilaInformeIndividual({
    required this.desglose,
    required this.generandoPdf,
    required this.onWhatsApp,
    required this.onPdf,
  });

  @override
  Widget build(BuildContext context) {
    final estado = desglose.pagado
        ? 'Pagado OK'
        : desglose.pagoParcial
            ? 'Parcial - debe ${formatMoney(desglose.saldoRestante)}'
            : 'Debe ${formatMoney(desglose.saldoRestante)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        title: Text(
          desglose.nombre,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(estado, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.message, color: Colors.green),
              tooltip: 'WhatsApp individual',
              onPressed: onWhatsApp,
            ),
            IconButton.filledTonal(
              icon: generandoPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf, color: Colors.deepOrange),
              tooltip: 'PDF individual',
              onPressed: generandoPdf ? null : onPdf,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesgloseCard extends StatelessWidget {
  final DesgloseJugador desglose;

  const _DesgloseCard({required this.desglose});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  desglose.nombre,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  desglose.pagado
                      ? (desglose.generaSaldoAFavor
                          ? 'A FAVOR ${formatMoney(-desglose.saldoRestante)}'
                          : 'PAGO OK')
                      : desglose.pagoParcial
                          ? 'Parcial ${formatMoney(desglose.montoPagado)}'
                          : formatMoney(desglose.totalATransferir),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: desglose.pagado ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            if (desglose.saldoAnterior > 0)
              Text(
                'Deuda ant.: ${formatMoney(desglose.saldoAnterior)}',
                style: const TextStyle(fontSize: 12),
              ),
            if (desglose.saldoAnterior < 0)
              Text(
                'Saldo a favor ant.: ${formatMoney(-desglose.saldoAnterior)}',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
            if (desglose.saldoFavorAplicado > 0)
              Text(
                'Saldo a favor aplicado: −${formatMoney(desglose.saldoFavorAplicado)}',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
            ...desglose.lineas.map(
              (l) => Text(
                '${l.concepto}: ${formatMoney(l.monto)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeccionComprobantesGastos extends StatelessWidget {
  final PartidoCompleto completo;

  const _SeccionComprobantesGastos({required this.completo});

  List<({String label, String path})> get _items {
    final p = completo.partido;
    final items = <({String label, String path})>[];

    if (p.costoCancha > 0 && p.comprobanteCancha != null) {
      items.add((label: 'Cancha', path: p.comprobanteCancha!));
    }
    if (p.costoPelotas > 0 && p.comprobantePelotas != null) {
      items.add((label: 'Pelotas', path: p.comprobantePelotas!));
    }
    for (final cv in completo.costosVariables) {
      if (cv.comprobantePath != null) {
        items.add((label: cv.concepto, path: cv.comprobantePath!));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SeccionTitulo(
          icono: Icons.receipt_long,
          titulo: 'Comprobantes de gastos',
          subtitulo: 'Boletas o transferencias de cancha, asado, etc.',
        ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ComprobantePagoTile(
                    comprobantePath: item.path,
                    onChanged: (_) {},
                    compact: true,
                    readOnly: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
