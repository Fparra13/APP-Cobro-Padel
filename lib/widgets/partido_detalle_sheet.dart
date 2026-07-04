import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_repositories.dart';
import '../core/supabase_helpers.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../models/jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/mensaje_cobro_service.dart';
import '../services/pdf_service.dart';
import '../services/preferences_service.dart';
import '../services/recordatorio_service.dart';
import '../utils/formatters.dart';
import '../utils/single_action.dart';
import 'ayuda_tip.dart';
import 'comprobante_pago_tile.dart';
import 'desglose_cobro_panel.dart';
import 'pagos_por_validar_panel.dart';

/// Detalle de un partido: cobros y avisos primero; PDF/mensaje para fuera de la app.
class PartidoDetalleSheet extends StatefulWidget {
  final PartidoCompleto completo;
  final List<DesgloseJugador> desglose;
  final PdfService pdfService;
  final VoidCallback? onEditar;
  final VoidCallback? onEliminar;

  const PartidoDetalleSheet({
    super.key,
    required this.completo,
    required this.desglose,
    required this.pdfService,
    this.onEditar,
    this.onEliminar,
  });

  static Future<void> show(
    BuildContext context, {
    required PartidoCompleto completo,
    required AppRepositories repos,
    required PdfService pdfService,
    VoidCallback? onEditar,
    VoidCallback? onEliminar,
  }) async {
    final partidoId = completo.partido.id;
    if (partidoId == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final results = await Future.wait([
        repos.getPartidoCompleto(partidoId),
        repos.getDesglose(partidoId, reconciliar: false),
      ]);
      final full = results[0] as PartidoCompleto? ?? completo;
      final desglose = results[1] as List<DesgloseJugador>;

      if (!context.mounted) return;
      Navigator.of(context).pop();

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => PartidoDetalleSheet(
          completo: full,
          desglose: desglose,
          pdfService: pdfService,
          onEditar: onEditar,
          onEliminar: onEliminar,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SupabaseHelpers.describeError(e, operacion: 'Detalle del partido'),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  State<PartidoDetalleSheet> createState() => _PartidoDetalleSheetState();
}

class _PartidoDetalleSheetState extends State<PartidoDetalleSheet> {
  final _sheetMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _recordatorio = RecordatorioService();
  final _prefs = PreferencesService();

  bool _generandoPdfGeneral = false;
  String? _generandoPdfKey;
  String? _enviandoPushKey;
  String? _feedback;
  bool _feedbackError = false;

  PartidoCompleto get completo => widget.completo;
  List<DesgloseJugador> get desglose => widget.desglose;
  PdfService get pdfService => widget.pdfService;

  List<DesgloseJugador> get _deudores =>
      desglose.where((d) => d.saldoRestante > 0.005).toList();

  List<DesgloseJugador> get _deudoresConApp =>
      _deudores.where((d) => d.jugadorKeyId.isNotEmpty).toList();

  double get _totalPendiente =>
      _deudores.fold(0.0, (s, d) => s + d.saldoRestante);

  void _mostrarFeedback(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _feedback = msg;
      _feedbackError = error;
    });
    _sheetMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  Future<void> _conFeedback(
    Future<void> Function() accion, {
    required String exitoKey,
    Map<String, String> exitoParams = const {},
  }) async {
    try {
      await accion();
      if (mounted) {
        _mostrarFeedback(context.tr(exitoKey, params: exitoParams));
      }
    } catch (e) {
      if (mounted) {
        _mostrarFeedback(
          context.tr('pdfGenerateError', params: {'error': '$e'}),
          error: true,
        );
      }
    }
  }

  Future<void> _pdfGeneral() async {
    setState(() => _generandoPdfGeneral = true);
    await _conFeedback(
      () => pdfService.generarReportePartido(completo),
      exitoKey: 'pdfMatchReady',
    );
    if (mounted) setState(() => _generandoPdfGeneral = false);
  }

  Future<void> _pdfIndividual(DesgloseJugador d) async {
    final key = d.jugadorKeyId.isNotEmpty ? d.jugadorKeyId : d.nombre;
    setState(() => _generandoPdfKey = key);
    final repos = AppRepositories.I;
    await _conFeedback(
      () async {
        final jugador = d.jugadorKeyId.isNotEmpty
            ? await repos.getJugador(d.jugadorKeyId)
            : null;
        await pdfService.generarReportePersonal(
          completo: completo,
          desglose: d,
          jugador: jugador,
        );
      },
      exitoKey: 'pdfPlayerReady',
      exitoParams: {'name': d.nombre},
    );
    if (mounted) setState(() => _generandoPdfKey = null);
  }

  Future<({String titular, String banco, String cuenta})> _datosTransferencia() async {
    final data = await Future.wait<String>([
      _prefs.titularNombre,
      _prefs.bancoNombre,
      _prefs.cuentaNumero,
    ]);
    return (titular: data[0], banco: data[1], cuenta: data[2]);
  }

  Future<void> _copiarMensaje(DesgloseJugador d) async {
    await runOnce('copy-${d.jugadorKeyId}', () async {
      try {
        final datos = await _datosTransferencia();
        final msg = MensajeCobroService.construirDetallePartido(
          partido: completo.partido,
          desglose: d,
          deudasAnteriores: const [],
          titular: datos.titular,
          banco: datos.banco,
          cuenta: datos.cuenta,
        );
        await Clipboard.setData(ClipboardData(text: msg));
        if (mounted) {
          _mostrarFeedback(context.tr('chargeMessageCopied'));
        }
      } catch (e) {
        if (mounted) _mostrarFeedback('$e', error: true);
      }
      return null;
    });
  }

  Future<void> _avisarEnApp(DesgloseJugador d) async {
    final key = d.jugadorKeyId;
    if (key.isEmpty) {
      _mostrarFeedback(context.tr('noAppUseCopyMessage'), error: true);
      return;
    }

    final sinAppMsg = context.tr('noAppUseCopyMessage');
    final nombre = d.nombre;
    final saldo = d.saldoRestante;

    await runOnce('push-$key', () async {
      setState(() => _enviandoPushKey = key);
      try {
        final jugador = await AppRepositories.I.getJugador(key);
        if (jugador == null) {
          throw Exception(sinAppMsg);
        }
        await _recordatorio.enviarIndividual(
          jugador: jugador,
          saldo: saldo,
        );
        if (mounted) {
          _mostrarFeedback(
            context.tr(
              'reminderSentTo',
              params: {'name': nombre},
            ),
          );
        }
      } catch (e) {
        if (mounted) _mostrarFeedback('$e', error: true);
      } finally {
        if (mounted) setState(() => _enviandoPushKey = null);
      }
      return null;
    });
  }

  Future<void> _avisarDeudoresConApp() async {
    final conApp = _deudoresConApp;
    if (conApp.isEmpty) {
      _mostrarFeedback(context.tr('noDebtorWithApp'), error: true);
      return;
    }

    await runOnce('push-all-match', () async {
      setState(() => _enviandoPushKey = '__all__');
      var ok = 0;
      var fail = 0;
      for (final d in conApp) {
        try {
          Jugador? jugador = await AppRepositories.I.getJugador(d.jugadorKeyId);
          if (jugador == null) {
            fail++;
            continue;
          }
          await _recordatorio.enviarIndividual(
            jugador: jugador,
            saldo: d.saldoRestante,
          );
          ok++;
        } catch (_) {
          fail++;
        }
      }
      if (!mounted) return null;
      setState(() => _enviandoPushKey = null);
      if (ok > 0) {
        _mostrarFeedback(
          context.tr(
            'matchRemindersSent',
            params: {'count': '$ok'},
          ),
          error: fail > 0,
        );
      } else {
        _mostrarFeedback(context.tr('noDebtorWithApp'), error: true);
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fecha = formatFechaHora(completo.partido.fecha);
    final pendientes = _deudores.length;

    return ScaffoldMessenger(
      key: _sheetMessengerKey,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        builder: (_, scroll) => Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
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
                            Text(
                              context.tr('matchDetailTitle'),
                              style: const TextStyle(
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
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Material(
                      color: _feedbackError
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(
                              _feedbackError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              color: _feedbackError
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _feedback!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _feedbackError
                                      ? Colors.red.shade900
                                      : Colors.green.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      AyudaTip(texto: context.tr('matchDetailHelpTip')),
                      const SizedBox(height: 12),
                      _ResumenCobros(
                        jugadores: desglose.length,
                        pendientes: pendientes,
                        totalPendiente: _totalPendiente,
                      ),
                      if (_deudoresConApp.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _enviandoPushKey != null
                              ? null
                              : _avisarDeudoresConApp,
                          icon: _enviandoPushKey == '__all__'
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.notifications_active_outlined),
                          label: Text(
                            context.tr(
                              'remindDebtorsWithApp',
                              params: {'count': '${_deudoresConApp.length}'},
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _SeccionTitulo(
                        icono: Icons.groups_rounded,
                        titulo: context.tr('playersChargesTitle'),
                        subtitulo: context.tr('playersChargesSubtitle'),
                      ),
                      const SizedBox(height: 8),
                      ...desglose.map((d) {
                        final key = d.jugadorKeyId.isNotEmpty
                            ? d.jugadorKeyId
                            : d.nombre;
                        return _JugadorCobroCard(
                          desglose: d,
                          generandoPdf: _generandoPdfKey == key,
                          enviandoPush: _enviandoPushKey == d.jugadorKeyId,
                          onAvisarApp: d.saldoRestante > 0.005 &&
                                  d.jugadorKeyId.isNotEmpty
                              ? () => _avisarEnApp(d)
                              : null,
                          onCopiarMensaje: () => _copiarMensaje(d),
                          onPdf: () => _pdfIndividual(d),
                        );
                      }),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        initiallyExpanded: false,
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        leading: Icon(
                          Icons.ios_share_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          context.tr('shareOutsideAppTitle'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          context.tr('shareOutsideAppSubtitle'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              context.tr('shareOutsideAppHint'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed:
                                _generandoPdfGeneral ? null : _pdfGeneral,
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
                                  ? context.tr('generatingPdf')
                                  : context.tr('generateMatchPdf'),
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (widget.onEditar != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: widget.onEditar,
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(context.tr('editTooltip')),
                              ),
                            ),
                          if (widget.onEditar != null &&
                              widget.onEliminar != null)
                            const SizedBox(width: 10),
                          if (widget.onEliminar != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: widget.onEliminar,
                                icon: Icon(
                                  Icons.delete_forever_rounded,
                                  color: Colors.red.shade700,
                                ),
                                label: Text(
                                  context.tr('deleteTooltip'),
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.red.shade300,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SeccionComprobantesGastos(completo: completo),
                      const SizedBox(height: 20),
                      _SeccionComprobantesPago(
                        completo: completo,
                        onValidado: () {
                          if (mounted) Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResumenCobros extends StatelessWidget {
  final int jugadores;
  final int pendientes;
  final double totalPendiente;

  const _ResumenCobros({
    required this.jugadores,
    required this.pendientes,
    required this.totalPendiente,
  });

  @override
  Widget build(BuildContext context) {
    final alDia = pendientes == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alDia ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alDia ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            alDia ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
            color: alDia ? Colors.green.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alDia
                  ? context.tr(
                      'matchSummaryAllPaid',
                      params: {'count': '$jugadores'},
                    )
                  : context.tr(
                      'matchSummaryPending',
                      params: {
                        'pending': '$pendientes',
                        'total': '$jugadores',
                        'amount': formatMoney(totalPendiente),
                      },
                    ),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: alDia ? Colors.green.shade900 : Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
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

class _JugadorCobroCard extends StatelessWidget {
  final DesgloseJugador desglose;
  final bool generandoPdf;
  final bool enviandoPush;
  final VoidCallback? onAvisarApp;
  final VoidCallback onCopiarMensaje;
  final VoidCallback onPdf;

  const _JugadorCobroCard({
    required this.desglose,
    required this.generandoPdf,
    required this.enviandoPush,
    required this.onAvisarApp,
    required this.onCopiarMensaje,
    required this.onPdf,
  });

  String _estado(BuildContext context) {
    if (desglose.pagado) {
      return desglose.generaSaldoAFavor
          ? context.tr(
              'creditedAmountLabel',
              params: {'amount': formatMoney(-desglose.saldoRestante)},
            )
          : context.tr('paidOk');
    }
    if (desglose.pagoParcial) {
      return context.tr(
        'partialOwesShort',
        params: {'amount': formatMoney(desglose.saldoRestante)},
      );
    }
    return context.tr(
      'owesAmountLabel',
      params: {'amount': formatMoney(desglose.saldoRestante)},
    );
  }

  @override
  Widget build(BuildContext context) {
    final debe = desglose.saldoRestante > 0.005;
    final estadoColor =
        desglose.pagado ? Colors.green.shade800 : Colors.red.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        desglose.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _estado(context),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: estadoColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (debe)
                  Text(
                    formatMoney(desglose.saldoRestante),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red.shade700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DesgloseCalculoPanel(desglose: desglose, compact: true),
            const SizedBox(height: 10),
            Row(
              children: [
                if (onAvisarApp != null)
                  IconButton.filledTonal(
                    onPressed: enviandoPush ? null : onAvisarApp,
                    tooltip: context.tr('notifyInAppTooltip'),
                    icon: enviandoPush
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active_outlined),
                  ),
                IconButton.filledTonal(
                  onPressed: onCopiarMensaje,
                  tooltip: context.tr('copyChargeMessageTooltip'),
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton.filledTonal(
                  onPressed: generandoPdf ? null : onPdf,
                  tooltip: context.tr('individualPdfTooltip'),
                  icon: generandoPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                ),
                const Spacer(),
                if (debe && desglose.jugadorKeyId.isEmpty)
                  Text(
                    context.tr('noAppShort'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
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

class _SeccionComprobantesGastos extends StatelessWidget {
  final PartidoCompleto completo;

  const _SeccionComprobantesGastos({required this.completo});

  List<({String label, String path})> _items(BuildContext context) {
    final p = completo.partido;
    final items = <({String label, String path})>[];

    if (p.costoCancha > 0 && p.comprobanteCancha != null) {
      items.add((label: context.tr('courtLabel'), path: p.comprobanteCancha!));
    }
    if (p.costoPelotas > 0 && p.comprobantePelotas != null) {
      items.add((label: context.tr('ballsLabel'), path: p.comprobantePelotas!));
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
    final items = _items(context);
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SeccionTitulo(
          icono: Icons.receipt_long,
          titulo: context.tr('expenseReceiptsTitle'),
          subtitulo: context.tr('expenseReceiptsSubtitle'),
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

class _SeccionComprobantesPago extends StatelessWidget {
  final PartidoCompleto completo;
  final VoidCallback? onValidado;

  const _SeccionComprobantesPago({
    required this.completo,
    this.onValidado,
  });

  @override
  Widget build(BuildContext context) {
    return PagosPorValidarPanel(
      pagos: completo.detalles,
      onValidado: onValidado,
    );
  }
}
