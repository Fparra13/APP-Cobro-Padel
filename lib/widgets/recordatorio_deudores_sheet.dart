import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/matchpay_strings.dart';
import '../repositories/partido_repository.dart';
import '../services/recordatorio_service.dart';
import '../utils/formatters.dart';
import '../utils/single_action.dart';

class RecordatorioDeudoresSheet extends StatefulWidget {
  final List<ResumenJugador> deudores;
  final String? titulo;
  final String? subtitulo;

  const RecordatorioDeudoresSheet({
    super.key,
    required this.deudores,
    this.titulo,
    this.subtitulo,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ResumenJugador> resumenes,
    String? titulo,
    String? subtitulo,
  }) {
    final deudores = resumenes.where((r) => r.tieneDeuda).toList();
    if (deudores.isEmpty) {
      return Future.value();
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordatorioDeudoresSheet(
        deudores: deudores,
        titulo: titulo,
        subtitulo: subtitulo,
      ),
    );
  }

  @override
  State<RecordatorioDeudoresSheet> createState() =>
      _RecordatorioDeudoresSheetState();
}

class _RecordatorioDeudoresSheetState extends State<RecordatorioDeudoresSheet> {
  final _service = RecordatorioService();
  final _sheetMessengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _enviando = false;
  String? _enviandoJugadorKey;
  String? _feedback;
  bool _feedbackError = false;

  int get _conApp => widget.deudores
      .where((r) => r.jugador.keyId.isNotEmpty)
      .length;

  double get _totalDeuda =>
      widget.deudores.fold(0.0, (s, r) => s + r.deudaVisible);

  String _remindersSummary(BuildContext context, dynamic resultado) {
    final noApp = resultado.sinApp > 0
        ? context.tr(
            'remindersNoAppSuffix',
            params: {'count': '${resultado.sinApp}'},
          )
        : '';
    final errors = resultado.errores > 0
        ? context.tr(
            'remindersErrorsSuffix',
            params: {'count': '${resultado.errores}'},
          )
        : '';
    return context.tr(
      'remindersSentSummary',
      params: {
        'sent': '${resultado.enviados}',
        'noApp': noApp,
        'errors': errors,
      },
    );
  }

  Future<void> _enviarTodos() async {
    if (_conApp == 0) {
      _mostrarFeedback(context.tr('noDebtorWithApp'), error: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active, color: Colors.blue),
        title: Text(ctx.tr('sendRemindersTitle')),
        content: Text(
          ctx.tr('sendRemindersBody', params: {'count': '$_conApp'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send),
            label: Text(ctx.tr('sendBtn')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await runOnce('recordatorio-todos', () async {
      setState(() => _enviando = true);
      final resultado = await _service.enviarATodos(widget.deudores);
      if (!mounted) return null;
      setState(() => _enviando = false);
      _mostrarFeedback(
        _remindersSummary(context, resultado),
        error: resultado.enviados == 0,
      );
      return null;
    });
  }

  Future<void> _enviarUno(ResumenJugador r) async {
    final key = r.jugador.keyId;
    if (key.isEmpty) {
      _mostrarFeedback(
        context.tr('noAppUseCopy', params: {'name': r.jugador.nombre}),
        error: true,
      );
      return;
    }

    await runOnce('recordatorio-$key', () async {
      setState(() => _enviandoJugadorKey = key);
      try {
        await _service.enviarIndividual(
          jugador: r.jugador,
          saldo: r.deudaVisible,
        );
        if (mounted) {
          _mostrarFeedback(
            context.tr(
              'reminderSentTo',
              params: {'name': r.jugador.nombre},
            ),
          );
        }
      } catch (e) {
        if (mounted) _mostrarFeedback('$e', error: true);
      } finally {
        if (mounted) setState(() => _enviandoJugadorKey = null);
      }
      return null;
    });
  }

  Future<void> _copiarMensaje(ResumenJugador r) async {
    try {
      final msg = await _service.construirMensaje(
        jugador: r.jugador,
        saldo: r.deudaVisible,
      );
      await Clipboard.setData(ClipboardData(text: msg));
      if (mounted) {
        _mostrarFeedback(context.tr('messageCopied'));
      }
    } catch (e) {
      if (mounted) _mostrarFeedback('$e', error: true);
    }
  }

  /// Feedback dentro del sheet: el SnackBar del home queda detrás del modal.
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

  @override
  Widget build(BuildContext context) {
    final titulo = widget.titulo ?? context.tr('reminderDebtorsTitle');
    final subtitulo = widget.subtitulo ??
        context.tr(
          'debtorsSummaryLine',
          params: {
            'count': '${widget.deudores.length}',
            'amount': formatMoney(_totalDeuda),
          },
        );

    return ScaffoldMessenger(
      key: _sheetMessengerKey,
      child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (_, scroll) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.notifications_active,
                        color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          subtitulo,
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
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  color: _feedbackError
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          _feedbackError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: _feedbackError
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                        ),
                        const SizedBox(width: 10),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Text(
                  context.tr('reminderPushHint'),
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.deudores.length,
                itemBuilder: (_, i) {
                  final r = widget.deudores[i];
                  final tieneApp = r.jugador.keyId.isNotEmpty;
                  final enviando = _enviandoJugadorKey == r.jugador.keyId;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: tieneApp
                            ? Colors.blue.shade100
                            : Colors.orange.shade100,
                        child: Text(
                          r.jugador.nombre.isNotEmpty
                              ? r.jugador.nombre[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: tieneApp
                                ? Colors.blue.shade800
                                : Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        r.jugador.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        tieneApp
                            ? context.tr(
                                'owesAmountLabel',
                                params: {
                                  'amount': formatMoney(r.deudaVisible),
                                },
                              )
                            : context.tr(
                                'owesNoAppLine',
                                params: {
                                  'amount': formatMoney(r.deudaVisible),
                                },
                              ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 20),
                            tooltip: context.tr('copyMessageTooltip'),
                            onPressed: _enviando ? null : () => _copiarMensaje(r),
                          ),
                          IconButton.filledTonal(
                            icon: enviando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    Icons.notifications_active,
                                    color: tieneApp ? Colors.blue : Colors.grey,
                                  ),
                            tooltip: context.tr('sendPushTooltip'),
                            onPressed: enviando || _enviando || !tieneApp
                                ? null
                                : () => _enviarUno(r),
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
              child: FilledButton.icon(
                onPressed: _enviando || _conApp == 0 ? null : _enviarTodos,
                icon: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _enviando
                      ? context.tr('sendingReminders')
                      : context.tr(
                          'sendToAll',
                          params: {'count': '$_conApp'},
                        ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  minimumSize: const Size.fromHeight(48),
                ),
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
