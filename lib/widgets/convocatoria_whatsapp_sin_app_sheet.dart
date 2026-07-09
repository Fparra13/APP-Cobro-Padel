import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../services/convocatoria_message_service.dart';
import '../services/whatsapp_share_service.dart';
import '../utils/single_action.dart';
import '../widgets/jugador_app_badge.dart';

class ConvocatoriaWhatsAppSinAppSheet extends StatefulWidget {
  final int partidoId;
  final List<Jugador> jugadores;
  final Map<String, EstadoConfirmacion> estados;

  const ConvocatoriaWhatsAppSinAppSheet({
    super.key,
    required this.partidoId,
    required this.jugadores,
    this.estados = const {},
  });

  static Future<void> show(
    BuildContext context, {
    required int partidoId,
    required List<Jugador> jugadores,
    Map<String, EstadoConfirmacion> estados = const {},
  }) {
    final sinApp = jugadores.where((j) => !j.tieneMatchPayApp).toList();
    if (sinApp.isEmpty) return Future.value();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConvocatoriaWhatsAppSinAppSheet(
        partidoId: partidoId,
        jugadores: sinApp,
        estados: estados,
      ),
    );
  }

  @override
  State<ConvocatoriaWhatsAppSinAppSheet> createState() =>
      _ConvocatoriaWhatsAppSinAppSheetState();
}

class _ConvocatoriaWhatsAppSinAppSheetState
    extends State<ConvocatoriaWhatsAppSinAppSheet> {
  final _sheetMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String? _enviandoJugadorKey;

  String _estadoLabel(BuildContext context, EstadoConfirmacion estado) {
    return switch (estado) {
      EstadoConfirmacion.confirmado => context.tr('statusConfirmed'),
      EstadoConfirmacion.rechazado => context.tr('statusDeclined'),
      EstadoConfirmacion.noRespondio => context.tr('statusNoResponse'),
      EstadoConfirmacion.invitado => context.tr('statusPending'),
    };
  }

  Future<void> _enviarWhatsApp(Jugador jugador) async {
    if (jugador.tieneMatchPayApp) return;
    if (!jugador.puedeEnviarWhatsApp) {
      _mostrarFeedback(context.tr('whatsappNoNumber'), error: true);
      return;
    }

    final key = jugador.keyId;
    await runOnce('wa-convocatoria-$key', () async {
      setState(() => _enviandoJugadorKey = key);
      try {
        final conv =
            await context.repos.getConvocatoriaCompleta(widget.partidoId);
        if (conv == null) {
          throw Exception(context.tr('convocatoriaNotFoundSnack'));
        }
        final msg = ConvocatoriaMessageService().construirMensajePersonal(
          convocatoria: conv,
          nombreJugador: jugador.nombre,
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
        if (mounted) setState(() => _enviandoJugadorKey = null);
      }
      return null;
    });
  }

  void _mostrarFeedback(String msg, {bool error = false}) {
    if (!mounted) return;
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
    final conWhatsApp =
        widget.jugadores.where((j) => j.puedeEnviarWhatsApp).length;

    return ScaffoldMessenger(
      key: _sheetMessengerKey,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (_, scroll) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.chat_outlined,
                          color: Color(0xFF1B8F4E),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('organizeWhatsAppNoAppTitle'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              context.tr(
                                'organizeWhatsAppNoAppSubtitle',
                                params: {
                                  'count': '${widget.jugadores.length}',
                                  'withWhatsApp': '$conWhatsApp',
                                },
                              ),
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
                      color: const Color(0xFF25D366).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF25D366).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      context.tr('organizeWhatsAppNoAppHint'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1B8F4E),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: widget.jugadores.length,
                    itemBuilder: (_, i) {
                      final j = widget.jugadores[i];
                      final estado = widget.estados[j.keyId] ??
                          EstadoConfirmacion.invitado;
                      final enviando = _enviandoJugadorKey == j.keyId;
                      final puedeWhatsApp = j.puedeEnviarWhatsApp;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.orange.shade100,
                                    child: Text(
                                      j.nombre.isNotEmpty
                                          ? j.nombre[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                j.nombre,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            JugadorAppBadge(
                                              jugador: j,
                                              compact: true,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          puedeWhatsApp
                                              ? context.tr(
                                                  'organizeWhatsAppNoAppPlayerStatus',
                                                  params: {
                                                    'status': _estadoLabel(
                                                      context,
                                                      estado,
                                                    ),
                                                  },
                                                )
                                              : context.tr('whatsappNoNumber'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: puedeWhatsApp
                                                ? Colors.grey.shade700
                                                : Colors.orange.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: !puedeWhatsApp || enviando
                                      ? null
                                      : () => _enviarWhatsApp(j),
                                  icon: enviando
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.send_rounded, size: 18),
                                  label: Text(
                                    context.tr('sendConvocatoriaWhatsApp'),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366)
                                        .withValues(alpha: 0.15),
                                    foregroundColor: const Color(0xFF1B8F4E),
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
