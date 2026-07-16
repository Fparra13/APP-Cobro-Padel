import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../domain/cobro_logic.dart';
import '../l10n/matchpay_strings.dart';
import '../models/datos_pago_organizador.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/mensaje_cobro_service.dart';
import '../services/pdf_service.dart';
import '../services/preferences_service.dart';
import '../services/recordatorio_service.dart';
import '../services/whatsapp_share_service.dart';
import '../utils/formatters.dart';
import '../utils/single_action.dart';
import 'ayuda_tip.dart';
import 'comprobante_historico_chip.dart';
import 'comprobante_pago_tile.dart';
import 'desglose_cobro_panel.dart';
import 'jugador_app_badge.dart';
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
      // Una sola carga completa + desglose en lectura (sin reparación N×jugador).
      final full = await repos.getPartidoCompleto(partidoId) ?? completo;
      final desglose = await repos.getDesglose(
        partidoId,
        reconciliar: false,
        repararCuenta: false,
        completo: full,
      );

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
          content: Text(context.userError(e)),
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
  String? _enviandoWhatsAppKey;
  String? _feedback;
  bool _feedbackError = false;
  Map<String, Jugador> _jugadoresPorId = {};
  late PartidoCompleto _completo;
  late List<DesgloseJugador> _desglose;
  bool _recargando = false;

  @override
  void initState() {
    super.initState();
    _completo = widget.completo;
    _desglose = widget.desglose;
    _cargarJugadores();
  }

  PartidoCompleto get completo => _completo;
  List<DesgloseJugador> get desglose => _desglose;
  PdfService get pdfService => widget.pdfService;

  List<DesgloseJugador> get _deudores =>
      desglose.where((d) => d.tieneCobroPendienteOrganizador).toList();

  Jugador? _jugadorDe(DesgloseJugador d) =>
      d.jugadorKeyId.isEmpty ? null : _jugadoresPorId[d.jugadorKeyId];

  List<DesgloseJugador> get _deudoresConApp => _deudores
      .where((d) => _jugadorDe(d)?.tieneMatchPayApp ?? false)
      .toList();

  List<DesgloseJugador> get _deudoresSinApp => _deudores.where((d) {
        final j = _jugadorDe(d);
        return j != null && !j.tieneMatchPayApp;
      }).toList();

  Future<void> _recargarTrasPago() async {
    final partidoId = _completo.partido.id;
    if (partidoId == null || _recargando) return;
    setState(() => _recargando = true);
    try {
      final full =
          await AppRepositories.I.getPartidoCompleto(partidoId) ?? _completo;
      final desglose = await AppRepositories.I.getDesglose(
        partidoId,
        reconciliar: false,
        repararCuenta: false,
        completo: full,
      );
      if (!mounted) return;
      setState(() {
        _completo = full;
        _desglose = desglose;
      });
      await _cargarJugadores();
    } finally {
      if (mounted) setState(() => _recargando = false);
    }
  }

  Future<void> _cargarJugadores() async {
    final ids = desglose
        .map((d) => d.jugadorKeyId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    final repos = AppRepositories.I;
    // Un listado del roster + filtro local (evita N getJugador).
    // getJugadores ya trae oj.saldo_acumulado de ESTE organizador.
    final todos = await repos.getJugadores(incluirUsuarioActual: true);
    final map = <String, Jugador>{
      for (final j in todos)
        if (ids.contains(j.keyId)) j.keyId: j,
    };
    final faltantes = ids.where((id) => !map.containsKey(id));
    final orgId = AuthService.instance.currentUser?.id;
    await Future.wait([
      for (final id in faltantes)
        repos.getJugador(id, organizadorId: orgId).then((j) {
          if (j != null) map[id] = j;
        }),
    ]);
    if (mounted) setState(() => _jugadoresPorId = map);
  }

  double get _totalPendiente =>
      _deudores.fold(0.0, (s, d) => s + d.pendienteOrganizador);

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
        _mostrarFeedback(context.userError(e), error: true);
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
            ? await repos.getJugador(
                d.jugadorKeyId,
                organizadorId: AuthService.instance.currentUser?.id,
              )
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

  Future<DatosPagoOrganizador> _datosTransferencia() => _prefs.datosPago;

  Future<void> _copiarMensaje(DesgloseJugador d) async {
    await runOnce('copy-${d.jugadorKeyId}', () async {
      try {
        final pago = await _datosTransferencia();
        final msg = MensajeCobroService.construirDetallePartido(
          partido: completo.partido,
          desglose: d,
          deudasAnteriores: const [],
          pago: pago,
        );
        await Clipboard.setData(ClipboardData(text: msg));
        if (mounted) {
          _mostrarFeedback(context.tr('chargeMessageCopied'));
        }
      } catch (e) {
        if (mounted) _mostrarFeedback(context.userError(e), error: true);
      }
      return null;
    });
  }

  Future<void> _avisarEnApp(DesgloseJugador d) async {
    final key = d.jugadorKeyId;
    final jugador = _jugadorDe(d);
    if (key.isEmpty || jugador == null || !jugador.tieneMatchPayApp) {
      _mostrarFeedback(context.tr('noAppUseCopyMessage'), error: true);
      return;
    }

    final nombre = d.nombre;
    final saldo = d.pendienteOrganizador;

    await runOnce('push-$key', () async {
      setState(() => _enviandoPushKey = key);
      try {
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
        if (mounted) _mostrarFeedback(context.userError(e), error: true);
      } finally {
        if (mounted) setState(() => _enviandoPushKey = null);
      }
      return null;
    });
  }

  Future<void> _enviarCobroWhatsApp(DesgloseJugador d) async {
    final jugador = _jugadorDe(d);
    if (jugador == null || jugador.tieneMatchPayApp) return;
    if (!jugador.puedeEnviarWhatsApp) {
      _mostrarFeedback(context.tr('whatsappNoNumber'), error: true);
      return;
    }

    final key = d.jugadorKeyId;
    await runOnce('wa-$key', () async {
      setState(() => _enviandoWhatsAppKey = key);
      try {
        final pago = await _datosTransferencia();
        final msg = MensajeCobroService.construirDetallePartido(
          partido: completo.partido,
          desglose: d,
          deudasAnteriores: const [],
          pago: pago,
        );
        final ok = await WhatsAppShareService.enviar(
          mensaje: msg,
          telefono: jugador.contactWhatsApp,
        );
        if (mounted) {
          _mostrarFeedback(
            ok
                ? context.tr('whatsappOpening')
                : context.tr('whatsappOpenFailed'),
            error: !ok,
          );
        }
      } catch (e) {
        if (mounted) _mostrarFeedback(context.userError(e), error: true);
      } finally {
        if (mounted) setState(() => _enviandoWhatsAppKey = null);
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
          Jugador? jugador = await AppRepositories.I.getJugador(
            d.jugadorKeyId,
            organizadorId: AuthService.instance.currentUser?.id,
          );
          if (jugador == null) {
            fail++;
            continue;
          }
          await _recordatorio.enviarIndividual(
            jugador: jugador,
            saldo: d.pendienteOrganizador,
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
    final fecha = formatFechaLegible(completo.partido.fecha);
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
                              style: MatchPayTokens.titleSmallStyle(
                                color: MatchPayTokens.ink,
                              ),
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
                      if (_deudoresSinApp.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _enviandoWhatsAppKey != null
                              ? null
                              : () => _enviarCobroWhatsApp(_deudoresSinApp.first),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                          ),
                          icon: _enviandoWhatsAppKey != null
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.chat_outlined),
                          label: Text(
                            context.tr(
                              'sendChargeWhatsAppBulk',
                              params: {
                                'count': '${_deudoresSinApp.length}',
                              },
                            ),
                          ),
                        ),
                        if (_deudoresSinApp.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              context.tr('sendChargeWhatsAppBulkHint'),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
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
                        DetallePartido? detalleCobro;
                        for (final det in completo.detalles) {
                          if (det.jugadorKeyId == d.jugadorKeyId) {
                            detalleCobro = det;
                            break;
                          }
                        }
                        return _JugadorCobroCard(
                          desglose: d,
                          jugador: _jugadorDe(d),
                          detalleCobro: detalleCobro,
                          generandoPdf: _generandoPdfKey == key,
                          enviandoPush: _enviandoPushKey == d.jugadorKeyId,
                          enviandoWhatsApp:
                              _enviandoWhatsAppKey == d.jugadorKeyId,
                          onAvisarApp: d.tieneCobroPendienteOrganizador &&
                                  (_jugadorDe(d)?.tieneMatchPayApp ?? false)
                              ? () => _avisarEnApp(d)
                              : null,
                          onEnviarWhatsApp: d.tieneCobroPendienteOrganizador &&
                                  (_jugadorDe(d) != null &&
                                      !(_jugadorDe(d)!.tieneMatchPayApp))
                              ? () => _enviarCobroWhatsApp(d)
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
                        onValidado: _recargarTrasPago,
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
  final Jugador? jugador;
  final DetallePartido? detalleCobro;
  final bool generandoPdf;
  final bool enviandoPush;
  final bool enviandoWhatsApp;
  final VoidCallback? onAvisarApp;
  final VoidCallback? onEnviarWhatsApp;
  final VoidCallback onCopiarMensaje;
  final VoidCallback onPdf;

  const _JugadorCobroCard({
    required this.desglose,
    this.jugador,
    this.detalleCobro,
    required this.generandoPdf,
    required this.enviandoPush,
    required this.enviandoWhatsApp,
    required this.onAvisarApp,
    required this.onEnviarWhatsApp,
    required this.onCopiarMensaje,
    required this.onPdf,
  });

  String? _notaCreditoCuenta(BuildContext context) {
    final credito = desglose.creditoCuenta > 0.005
        ? desglose.creditoCuenta
        : (jugador != null
            ? CobroLogic.obtenerCreditoJugador(
                saldoAcumulado: jugador!.saldoAcumulado,
              )
            : 0.0);
    if (credito <= 0.005) return null;
    // Si ya se muestra como resultado a favor en el estado, no repetir.
    if (desglose.alDiaOrganizador && desglose.creditoCuenta > 0.005) {
      return null;
    }
    if (!desglose.pagadoEnPartido && !desglose.alDiaOrganizador) {
      return null;
    }
    return context.tr(
      'accountCreditAfterMatchNote',
      params: {'amount': formatMoney(credito)},
    );
  }

  String _estado(BuildContext context) {
    if (desglose.saldoAcumuladoCuenta != null) {
      if (desglose.creditoCuenta > 0.005) {
        return context.tr(
          'creditedAmountLabel',
          params: {'amount': formatMoney(desglose.creditoCuenta)},
        );
      }
      if (desglose.alDiaOrganizador) {
        return context.tr('paidOk');
      }
      if (desglose.montoPagado > 0.005) {
        return context.tr(
          'partialOwesShort',
          params: {'amount': formatMoney(desglose.pendienteOrganizador)},
        );
      }
      return context.tr(
        'owesAmountLabel',
        params: {'amount': formatMoney(desglose.pendienteOrganizador)},
      );
    }
    if (desglose.pagadoEnPartido) {
      return desglose.generaSaldoAFavorPartido
          ? context.tr(
              'creditedAmountLabel',
              params: {
                'amount': formatMoney(-desglose.saldoRestantePartido),
              },
            )
          : context.tr('paidOk');
    }
    if (desglose.pagoParcial) {
      return context.tr(
        'partialOwesShort',
        params: {'amount': formatMoney(desglose.pendientePartido)},
      );
    }
    return context.tr(
      'owesAmountLabel',
      params: {'amount': formatMoney(desglose.pendientePartido)},
    );
  }

  @override
  Widget build(BuildContext context) {
    final debe = desglose.tieneCobroPendienteOrganizador;
    final notaCredito = _notaCreditoCuenta(context);
    final estadoColor = desglose.alDiaOrganizador
        ? Colors.green.shade800
        : Colors.red.shade700;

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
                      if (jugador != null) ...[
                        const SizedBox(height: 4),
                        JugadorAppBadge(jugador: jugador!, compact: true),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        _estado(context),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: estadoColor,
                        ),
                      ),
                      if (notaCredito != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          notaCredito,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (detalleCobro != null)
                        ComprobanteHistoricoChip(detalle: detalleCobro!),
                    ],
                  ),
                ),
                if (debe)
                  Text(
                    formatMoney(desglose.pendienteOrganizador),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red.shade700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DesgloseCalculoPanel(
              desglose: desglose,
              compact: true,
              showLineasPartido: true,
              // Solo el cargo de ESTE encuentro: la deuda anterior se liquida
              // en los partidos más viejos (FIFO), no se vuelve a sumar aquí.
              soloPartidoActual: true,
            ),
            if (desglose.saldoAcumuladoCuenta != null) ...[
              const SizedBox(height: 8),
              _CuentaSaldoLinea(desglose: desglose),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (onEnviarWhatsApp != null)
                  IconButton.filledTonal(
                    onPressed: enviandoWhatsApp ? null : onEnviarWhatsApp,
                    tooltip: context.tr('sendChargeWhatsApp'),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF25D366).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFF1B8F4E),
                    ),
                    icon: enviandoWhatsApp
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chat_outlined),
                  ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CuentaSaldoLinea extends StatelessWidget {
  final DesgloseJugador desglose;

  const _CuentaSaldoLinea({required this.desglose});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final credito = desglose.creditoCuenta;
    final deuda = desglose.pendienteCuenta;
    final String texto;
    final Color color;
    if (credito > 0.005) {
      texto = l10n.tr(
        'matchDetailAccountCredit',
        params: {'amount': formatMoney(credito)},
      );
      color = Colors.green.shade800;
    } else if (deuda > 0.005) {
      texto = l10n.tr(
        'matchDetailAccountDebt',
        params: {'amount': formatMoney(deuda)},
      );
      color = Colors.orange.shade900;
    } else {
      texto = l10n.tr('matchDetailAccountSettled');
      color = Colors.green.shade800;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
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
