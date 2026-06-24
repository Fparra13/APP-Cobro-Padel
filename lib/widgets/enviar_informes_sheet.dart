import 'package:flutter/material.dart';
import '../models/desglose_jugador.dart';
import '../models/jugador.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'ayuda_tip.dart';

/// Bottom sheet para enviar informe individual (WhatsApp / PDF) a cada jugador.
class EnviarInformesSheet extends StatefulWidget {
  final int partidoId;

  const EnviarInformesSheet({super.key, required this.partidoId});

  static Future<void> show(BuildContext context, {required int partidoId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => EnviarInformesSheet(partidoId: partidoId),
    );
  }

  @override
  State<EnviarInformesSheet> createState() => _EnviarInformesSheetState();
}

class _EnviarInformesSheetState extends State<EnviarInformesSheet> {
  final _partidoRepo = PartidoRepository();
  final _jugadorRepo = JugadorRepository();
  final _pdfService = PdfService();

  PartidoCompleto? _completo;
  List<DesgloseJugador> _desglose = [];
  bool _loading = true;
  bool _generandoPdfGeneral = false;
  int? _generandoPdfJugadorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final completo = await _partidoRepo.getCompleto(widget.partidoId);
    final desglose = await _partidoRepo.getDesglose(widget.partidoId);
    if (mounted) {
      setState(() {
        _completo = completo;
        _desglose = desglose;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fecha = _completo != null
        ? formatFecha(_completo!.partido.fecha)
        : '';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scroll) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enviar informes del partido',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (fecha.isNotEmpty)
                          Text('Partido $fecha',
                              style: TextStyle(color: Colors.grey.shade600)),
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
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: AyudaTip(
                  texto:
                      'PDF general = partido completo. '
                      'WhatsApp/PDF junto a cada jugador = informe privado.',
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _completo == null || _generandoPdfGeneral
                            ? null
                            : _pdfGeneral,
                        icon: _generandoPdfGeneral
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(
                          _generandoPdfGeneral
                              ? 'Generando...'
                              : 'PDF general',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _enviarWhatsAppDeudores,
                        icon: const Icon(Icons.message, color: Colors.green),
                        label: const Text('WA deudores'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Toca WhatsApp o PDF junto a cada jugador:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _desglose.length,
                  itemBuilder: (_, i) {
                    final d = _desglose[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(d.nombre,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...d.lineas.map(
                              (l) => Text(
                                '${l.concepto}: ${formatMoney(l.monto)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              d.pagado
                                  ? 'PAGADO ✓'
                                  : d.pagoParcial
                                      ? 'Parcial ${formatMoney(d.montoPagado)} · Debe ${formatMoney(d.saldoRestante)}'
                                      : 'Debe: ${formatMoney(d.saldoRestante)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: d.pagado
                                    ? Colors.green
                                    : d.pagoParcial
                                        ? Colors.orange
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ActionBtn(
                              icon: Icons.message,
                              color: Colors.green,
                              tooltip: 'WhatsApp',
                              onTap: () => _whatsapp(d),
                            ),
                            _ActionBtn(
                              icon: Icons.picture_as_pdf,
                              color: Colors.deepOrange,
                              tooltip: 'PDF',
                              loading: _generandoPdfJugadorId == d.jugadorId,
                              onTap: () => _pdf(d),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Listo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _whatsapp(DesgloseJugador d) async {
    if (_completo == null) return;
    final jugador = await _jugadorRepo.getById(d.jugadorId);
    try {
      await _pdfService.enviarWhatsAppPersonal(
        completo: _completo!,
        desglose: d,
        jugador: jugador,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error WhatsApp: $e')),
        );
      }
    }
  }

  Future<void> _pdfGeneral() async {
    if (_completo == null) return;
    setState(() => _generandoPdfGeneral = true);
    try {
      await _pdfService.generarReportePartido(_completo!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF del partido listo para compartir')),
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
    } finally {
      if (mounted) setState(() => _generandoPdfGeneral = false);
    }
  }

  Future<void> _pdf(DesgloseJugador d) async {
    if (_completo == null) return;
    setState(() => _generandoPdfJugadorId = d.jugadorId);
    try {
      final jugador = await _jugadorRepo.getById(d.jugadorId);
      await _pdfService.generarReportePersonal(
        completo: _completo!,
        desglose: d,
        jugador: jugador,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF de ${d.nombre} listo para compartir')),
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
    } finally {
      if (mounted) setState(() => _generandoPdfJugadorId = null);
    }
  }

  Future<void> _enviarWhatsAppDeudores() async {
    if (_completo == null) return;
    final deudores = _desglose.where((d) => !d.pagado).toList();
    if (deudores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todos pagaron, no hay deudores')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _WaDeudoresPartidoSheet(
        deudores: deudores,
        onEnviar: (d) async {
          await _whatsapp(d);
        },
      ),
    );
  }
}

class _WaDeudoresPartidoSheet extends StatefulWidget {
  final List<DesgloseJugador> deudores;
  final Future<void> Function(DesgloseJugador) onEnviar;

  const _WaDeudoresPartidoSheet({
    required this.deudores,
    required this.onEnviar,
  });

  @override
  State<_WaDeudoresPartidoSheet> createState() =>
      _WaDeudoresPartidoSheetState();
}

class _WaDeudoresPartidoSheetState extends State<_WaDeudoresPartidoSheet> {
  final _jugadorRepo = JugadorRepository();
  final Map<int, Jugador?> _jugadores = {};
  bool _loading = true;
  int? _enviandoId;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    for (final d in widget.deudores) {
      _jugadores[d.jugadorId] = await _jugadorRepo.getById(d.jugadorId);
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _conWhatsApp => widget.deudores
      .where((d) => (_jugadores[d.jugadorId]?.telefono?.trim().isNotEmpty ?? false))
      .length;

  Future<void> _enviarUno(DesgloseJugador d) async {
    final tel = _jugadores[d.jugadorId]?.telefono?.trim() ?? '';
    if (tel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${d.nombre} no tiene WhatsApp. Agrégalo en Jugadores.'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }
    setState(() => _enviandoId = d.jugadorId);
    try {
      await widget.onEnviar(d);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WhatsApp abierto para ${d.nombre}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      builder: (_, scroll) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.message, color: Colors.green.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WhatsApp a deudores',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          '${widget.deudores.length} jugadores · $_conWhatsApp con teléfono',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Envía uno a uno: toca el botón de cada jugador, '
                  'confirma en WhatsApp y vuelve aquí para el siguiente.',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: widget.deudores.length,
                      itemBuilder: (_, i) {
                        final d = widget.deudores[i];
                        final jugador = _jugadores[d.jugadorId];
                        final tieneWa =
                            jugador?.telefono?.trim().isNotEmpty ?? false;
                        final enviando = _enviandoId == d.jugadorId;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: tieneWa
                                  ? Colors.green.shade100
                                  : Colors.orange.shade100,
                              child: Icon(
                                tieneWa ? Icons.phone_android : Icons.phone_disabled,
                                color: tieneWa
                                    ? Colors.green.shade700
                                    : Colors.orange.shade800,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              d.nombre,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              tieneWa
                                  ? 'Debe ${formatMoney(d.saldoRestante)}'
                                  : 'Sin WhatsApp · ${formatMoney(d.saldoRestante)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: tieneWa
                                    ? Colors.red.shade700
                                    : Colors.orange.shade800,
                              ),
                            ),
                            trailing: IconButton.filledTonal(
                              icon: enviando
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(
                                      Icons.message,
                                      color: tieneWa ? Colors.green : Colors.grey,
                                    ),
                              onPressed:
                                  enviando || !tieneWa ? null : () => _enviarUno(d),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final bool loading;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      icon: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          : Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: loading ? null : onTap,
    );
  }
}
