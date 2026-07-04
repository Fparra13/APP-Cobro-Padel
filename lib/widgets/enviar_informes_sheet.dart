import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'ayuda_tip.dart';

/// Bottom sheet para enviar informe individual (PDF) a cada jugador.
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
    final repos = AppRepositories.I;
    final completo = await repos.getPartidoCompleto(widget.partidoId);
    final desglose = await repos.getDesglose(widget.partidoId);
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
                        Text(
                          context.tr('sendMatchReportsTitle'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (fecha.isNotEmpty)
                          Text(
                            context.tr('matchDateLine', params: {'date': fecha}),
                            style: TextStyle(color: Colors.grey.shade600),
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
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AyudaTip(texto: context.tr('sendReportsHelpTip')),
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
                              ? context.tr('generating')
                              : context.tr('generalPdf'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  context.tr('tapPdfPerPlayer'),
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
                                  ? context.tr('paidCheck')
                                  : d.pagoParcial
                                      ? context.tr(
                                          'partialOwesLine',
                                          params: {
                                            'paid': formatMoney(d.montoPagado),
                                            'remaining':
                                                formatMoney(d.saldoRestante),
                                          },
                                        )
                                      : context.tr(
                                          'owesColon',
                                          params: {
                                            'amount':
                                                formatMoney(d.saldoRestante),
                                          },
                                        ),
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
                        trailing: _ActionBtn(
                          icon: Icons.picture_as_pdf,
                          color: Colors.deepOrange,
                          tooltip: context.tr('pdfLabel'),
                          loading: _generandoPdfJugadorId == d.jugadorId,
                          onTap: () => _pdf(d),
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
                  child: Text(context.tr('doneBtn')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pdfGeneral() async {
    if (_completo == null) return;
    setState(() => _generandoPdfGeneral = true);
    try {
      await _pdfService.generarReportePartido(_completo!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('pdfMatchReady'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('pdfGenerateError', params: {'error': '$e'}),
            ),
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
      final jugador = await AppRepositories.I.getJugador(d.jugadorKeyId);
      await _pdfService.generarReportePersonal(
        completo: _completo!,
        desglose: d,
        jugador: jugador,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('pdfPlayerReady', params: {'name': d.nombre}),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('pdfGenerateError', params: {'error': '$e'}),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoPdfJugadorId = null);
    }
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
