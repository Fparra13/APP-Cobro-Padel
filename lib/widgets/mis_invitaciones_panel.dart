import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/mi_convocatoria.dart';
import '../utils/formatters.dart';
import 'convocatoria_respuesta_obligatoria_card.dart';
import 'matchpay_ui.dart';

/// Tarjetas de convocatorias para jugadores con acciones claras.
class MisInvitacionesPanel extends StatelessWidget {
  final List<MiConvocatoria> convocatorias;
  final VoidCallback? onRespondido;
  final bool compact;
  final bool readOnly;
  final VoidCallback? onReadOnlyTap;

  const MisInvitacionesPanel({
    super.key,
    required this.convocatorias,
    this.onRespondido,
    this.compact = false,
    this.readOnly = false,
    this.onReadOnlyTap,
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
              child: ConvocatoriaRespuestaObligatoriaCard(
                convocatoria: c,
                readOnly: readOnly,
                onReadOnlyTap: onReadOnlyTap,
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

class _ProximoPartidoTile extends StatelessWidget {
  final MiConvocatoria convocatoria;

  const _ProximoPartidoTile({required this.convocatoria});

  @override
  Widget build(BuildContext context) {
    final p = convocatoria.partido;
    final confirmado = convocatoria.estaConfirmado;
    final palette = SportThemeConfig.paletteFor(p.sportType);

    return MatchPayTapScale(
      onTap: () => _mostrarDetalleProximo(context, convocatoria),
      child: MatchPaySurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: confirmado
                    ? MatchPayTokens.accentSuccess.withValues(alpha: 0.12)
                    : palette.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                confirmado ? Icons.check_rounded : Icons.schedule_rounded,
                color: confirmado
                    ? MatchPayTokens.accentSuccess
                    : palette.primaryDark,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDiaCompleto(p.fecha),
                    style: MatchPayTokens.titleSmallStyle(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (p.recinto != null && p.recinto!.isNotEmpty) p.recinto!,
                      confirmado
                          ? context.tr('statusConfirmed')
                          : p.estado.name,
                    ].join(' · '),
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: MatchPayTokens.inkMuted,
            ),
          ],
        ),
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
