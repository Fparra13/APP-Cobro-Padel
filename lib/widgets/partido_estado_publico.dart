import 'package:flutter/material.dart';

import '../domain/estado_partido_publico.dart';
import '../l10n/matchpay_strings.dart';
import '../models/estado_partido.dart';
import '../models/mi_convocatoria.dart';
import '../utils/formatters.dart';

/// Etiqueta + mensaje del estado oficial del partido (organizador y jugador).
class PartidoEstadoPublicoBadge extends StatelessWidget {
  final PartidoEstadoPublicoView view;
  final bool compact;
  final Color? onDark;

  const PartidoEstadoPublicoBadge({
    super.key,
    required this.view,
    this.compact = false,
    this.onDark,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _title(l10n);
    final color = onDark ?? view.accentColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: onDark != null
            ? Colors.white.withValues(alpha: 0.18)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: onDark != null ? 0.35 : 0.25)),
      ),
      child: Text(
        '${view.emoji} $title',
        style: TextStyle(
          color: onDark ?? color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _title(MatchPayStrings l10n) => switch (view.estado) {
        EstadoPartidoPublico.confirmado =>
          l10n.tr('matchStatusConfirmedShort'),
        EstadoPartidoPublico.esperandoConfirmaciones =>
          l10n.tr('matchStatusWaitingShort'),
        EstadoPartidoPublico.enEvaluacion =>
          l10n.tr('matchStatusEvaluatingShort'),
        EstadoPartidoPublico.reprogramado =>
          l10n.tr('matchStatusRescheduledShort'),
        EstadoPartidoPublico.cancelado =>
          l10n.tr('matchStatusCancelledShort'),
        EstadoPartidoPublico.jugado => l10n.tr('matchStatusPlayedShort'),
      };
}

class PartidoEstadoPublicoMessage extends StatelessWidget {
  final PartidoEstadoPublicoView view;
  final DateTime? fechaPartido;
  final MiConvocatoria? jugadorConvocatoria;
  final Color? textColor;
  final double titleSize;
  final double bodySize;

  const PartidoEstadoPublicoMessage({
    super.key,
    required this.view,
    this.fechaPartido,
    this.jugadorConvocatoria,
    this.textColor,
    this.titleSize = 16,
    this.bodySize = 13.5,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = textColor ?? Theme.of(context).colorScheme.onSurface;
    final muted = color.withValues(alpha: 0.82);
    final params = {
      'confirmed': '${view.confirmados}',
      'max': '${view.cuposMax}',
      'missing': '${view.faltan}',
      'pending': '${view.pendientes}',
      'date': fechaPartido != null ? formatDiaCompleto(fechaPartido!) : '',
    };

    final title = switch (view.estado) {
      EstadoPartidoPublico.confirmado =>
        l10n.tr('matchStatusConfirmedTitle', params: params),
      EstadoPartidoPublico.esperandoConfirmaciones =>
        l10n.tr('matchStatusWaitingTitle', params: params),
      EstadoPartidoPublico.enEvaluacion =>
        l10n.tr('matchStatusEvaluatingTitle', params: params),
      EstadoPartidoPublico.reprogramado =>
        l10n.tr('matchStatusRescheduledTitle', params: params),
      EstadoPartidoPublico.cancelado =>
        l10n.tr('matchStatusCancelledTitle'),
      EstadoPartidoPublico.jugado => l10n.tr('matchStatusPlayedTitle'),
    };

    final body = switch (view.estado) {
      EstadoPartidoPublico.confirmado =>
        l10n.tr('matchStatusConfirmedBody', params: params),
      EstadoPartidoPublico.esperandoConfirmaciones =>
        l10n.tr('matchStatusWaitingBody', params: params),
      EstadoPartidoPublico.enEvaluacion =>
        l10n.tr('matchStatusEvaluatingBody', params: params),
      EstadoPartidoPublico.reprogramado =>
        l10n.tr('matchStatusRescheduledBody', params: params),
      EstadoPartidoPublico.cancelado =>
        l10n.tr('matchStatusCancelledBody'),
      EstadoPartidoPublico.jugado => l10n.tr('matchStatusPlayedBody'),
    };

    String? personal;
    final entry = jugadorConvocatoria?.entry;
    if (entry != null) {
      personal = switch (entry.estado) {
        EstadoConfirmacion.confirmado =>
          l10n.tr('matchStatusPlayerYouConfirmed'),
        EstadoConfirmacion.invitado when jugadorConvocatoria!.requiereRespuesta =>
          l10n.tr('matchStatusPlayerYouPending'),
        EstadoConfirmacion.rechazado ||
        EstadoConfirmacion.noRespondio =>
          l10n.tr('matchStatusPlayerYouDeclined'),
        _ => null,
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${view.emoji} $title',
          style: TextStyle(
            color: color,
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: TextStyle(
            color: muted,
            fontSize: bodySize,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        if (personal != null) ...[
          const SizedBox(height: 6),
          Text(
            personal,
            style: TextStyle(
              color: color,
              fontSize: bodySize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
