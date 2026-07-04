import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../utils/formatters.dart';
import '../screens/responder_convocatoria_screen.dart';
import '../utils/single_action.dart';
import 'sport_icon.dart';

/// Tarjetas de convocatorias para jugadores con acciones claras.
class MisInvitacionesPanel extends StatelessWidget {
  final List<MiConvocatoria> convocatorias;
  final VoidCallback? onRespondido;
  final bool compact;

  const MisInvitacionesPanel({
    super.key,
    required this.convocatorias,
    this.onRespondido,
    this.compact = false,
  });

  static Future<List<MiConvocatoria>> cargarPendientes(
    AppRepositories repos,
  ) async {
    final convs = await repos.getMisConvocatoriasComoJugador();
    return convs.where((c) => c.requiereRespuesta).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (convocatorias.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: convocatorias
          .map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ConvocatoriaAccionCard(
                convocatoria: c,
                compact: compact,
                onRespondido: onRespondido,
              ),
            ),
          )
          .toList(),
    );
  }
}

class ProximosPartidosPanel extends StatelessWidget {
  final List<MiConvocatoria> convocatorias;

  const ProximosPartidosPanel({super.key, required this.convocatorias});

  @override
  Widget build(BuildContext context) {
    if (convocatorias.isEmpty) return const SizedBox.shrink();

    return Column(
      children: convocatorias
          .map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProximoPartidoTile(convocatoria: c),
            ),
          )
          .toList(),
    );
  }
}

class _ConvocatoriaAccionCard extends StatefulWidget {
  final MiConvocatoria convocatoria;
  final bool compact;
  final VoidCallback? onRespondido;

  const _ConvocatoriaAccionCard({
    required this.convocatoria,
    this.compact = false,
    this.onRespondido,
  });

  @override
  State<_ConvocatoriaAccionCard> createState() =>
      _ConvocatoriaAccionCardState();
}

class _ConvocatoriaAccionCardState extends State<_ConvocatoriaAccionCard> {
  bool _enviando = false;

  MiConvocatoria get c => widget.convocatoria;
  Partido get partido => c.partido;

  Future<void> _responder(bool confirmo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          confirmo ? Icons.check_circle_outline : Icons.event_busy_outlined,
          color: confirmo ? Colors.green.shade700 : Colors.red.shade700,
          size: 36,
        ),
        title: Text(
          confirmo
              ? context.tr('respondConfirmTitle')
              : context.tr('respondDeclineTitle'),
        ),
        content: Text(
          confirmo
              ? context.tr(
                  'respondConfirmBodyMarked',
                  params: {'date': formatDiaCompleto(partido.fecha)},
                )
              : context.tr('respondDeclineBodyConvocate'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  confirmo ? Colors.green.shade700 : Colors.red.shade700,
            ),
            child: Text(
              confirmo
                  ? context.tr('respondYesGoing')
                  : context.tr('respondCannotGo'),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await runOnce('conv-resp-${c.entry.partidoId}', () async {
      setState(() => _enviando = true);
      try {
        await context.repos.responderConvocatoria(
          partidoId: c.entry.partidoId,
          confirmo: confirmo,
        );
        await ConvocatoriaListaEsperaService().sincronizar(c.entry.partidoId);
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmo
                  ? context.tr('attendanceConfirmedSnack')
                  : context.tr('responseSentOrganizer'),
            ),
          ),
        );
        widget.onRespondido?.call();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr('backupError', params: {'error': '$e'}),
              ),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _enviando = false);
      }
      return null;
    });
  }

  Future<void> _abrirDetalle() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResponderConvocatoriaScreen(
          partidoId: c.entry.partidoId,
          convocatoria: c,
        ),
      ),
    );
    widget.onRespondido?.call();
  }

  @override
  Widget build(BuildContext context) {
    final limite = c.entry.tiempoLimite;
    final theme = Theme.of(context);

    return Material(
      elevation: 0,
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _enviando ? null : _abrirDetalle,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.shade300, width: 1.5),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SportIcon(
                      size: 22,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('pendingConvocatoria'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        Text(
                          formatDiaCompleto(partido.fecha),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.compact)
                    Icon(Icons.open_in_new, color: Colors.orange.shade700),
                ],
              ),
              if (partido.recinto != null && partido.recinto!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 16, color: Colors.grey.shade700),
                    const SizedBox(width: 4),
                    Expanded(child: Text(partido.recinto!)),
                  ],
                ),
              ],
              if (partido.notas != null && partido.notas!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  partido.notas!,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
              if (limite != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 16, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.tr(
                            'respondBeforeDeadline',
                            params: {'deadline': formatFechaHora(limite)},
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: _enviando ? null : () => _responder(true),
                      icon: _enviando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(context.tr('confirmShort')),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: _enviando ? null : () => _responder(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                      child: Text(context.tr('respondCannotGo')),
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

class _ProximoPartidoTile extends StatelessWidget {
  final MiConvocatoria convocatoria;

  const _ProximoPartidoTile({required this.convocatoria});

  @override
  Widget build(BuildContext context) {
    final p = convocatoria.partido;
    final confirmado = convocatoria.estaConfirmado;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              confirmado ? Colors.green.shade100 : Colors.blue.shade100,
          child: Icon(
            confirmado ? Icons.check : Icons.schedule,
            color: confirmado ? Colors.green.shade800 : Colors.blue.shade800,
          ),
        ),
        title: Text(
          formatDiaCompleto(p.fecha),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (p.recinto != null && p.recinto!.isNotEmpty) p.recinto!,
            confirmado ? context.tr('statusConfirmed') : p.estado.name,
          ].join(' · '),
        ),
        trailing: Icon(Icons.info_outline, color: Colors.grey.shade500),
        onTap: () => _mostrarDetalleProximo(context, convocatoria),
      ),
    );
  }

  void _mostrarDetalleProximo(BuildContext context, MiConvocatoria c) {
    final p = c.partido;
    final recinto = p.recinto?.trim();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ctx.tr('playerUpcomingTitle'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text(
                formatDiaCompleto(p.fecha),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              if (recinto != null && recinto.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 18, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(recinto)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                ctx.tr('respondConfirmedStatus'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tr('close')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
