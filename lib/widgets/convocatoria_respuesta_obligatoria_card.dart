import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../l10n/matchpay_strings.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../utils/single_action.dart';
import 'matchpay_ui.dart';
import 'sport_icon.dart';

/// Tarjeta obligatoria: countdown sobre [tiempo_limite] + Va / No puedo.
class ConvocatoriaRespuestaObligatoriaCard extends StatefulWidget {
  final MiConvocatoria convocatoria;
  final VoidCallback? onRespondido;
  final bool readOnly;
  final VoidCallback? onReadOnlyTap;

  const ConvocatoriaRespuestaObligatoriaCard({
    super.key,
    required this.convocatoria,
    this.onRespondido,
    this.readOnly = false,
    this.onReadOnlyTap,
  });

  @override
  State<ConvocatoriaRespuestaObligatoriaCard> createState() =>
      _ConvocatoriaRespuestaObligatoriaCardState();
}

class _ConvocatoriaRespuestaObligatoriaCardState
    extends State<ConvocatoriaRespuestaObligatoriaCard> {
  Timer? _timer;
  bool _enviando = false;

  MiConvocatoria get c => widget.convocatoria;
  Partido get partido => c.partido;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(covariant ConvocatoriaRespuestaObligatoriaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.convocatoria.entry.tiempoLimite !=
        widget.convocatoria.entry.tiempoLimite) {
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleTick() {
    _timer?.cancel();
    final limite = c.entry.tiempoLimite;
    if (limite == null) return;
    final remaining = limite.difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    final interval = remaining < const Duration(hours: 1)
        ? const Duration(seconds: 30)
        : const Duration(minutes: 1);
    _timer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      final left = limite.difference(DateTime.now());
      if (left <= Duration.zero) {
        _timer?.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _responder(bool confirmo) async {
    if (widget.readOnly) {
      widget.onReadOnlyTap?.call();
      return;
    }
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
                  ? context.tr('inviteRespondGoing')
                  : context.tr('inviteRespondCantGo'),
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
              content: Text(context.userError(e)),
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

  @override
  Widget build(BuildContext context) {
    final limite = c.entry.tiempoLimite;
    final now = DateTime.now();
    final remaining =
        limite != null ? limite.difference(now) : const Duration(hours: 24);
    final urgente = remaining < const Duration(hours: 1);
    final palette = SportThemeConfig.paletteFor(partido.sportType);
    final recinto = partido.recinto?.trim();
    final lang = context.readSettings().locale.languageCode;
    final sportLabel = partido.sportType.labelForLocale(lang);

    final countdownLabel = limite == null
        ? null
        : urgente
            ? context.tr('inviteRespondCountdownUrgent')
            : context.tr(
                'inviteRespondCountdown',
                params: {'time': formatPlazoRestante(remaining)},
              );

    return MatchPaySurfaceCard(
      urgent: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MatchPayTokens.accentUrgent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SportIcon(
                  sport: partido.sportType,
                  size: 22,
                  color: MatchPayTokens.accentUrgent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('inviteRespondEyebrow'),
                  style: MatchPayTokens.sectionLabelStyle(
                    color: MatchPayTokens.accentUrgent,
                  ).copyWith(letterSpacing: 0.3, fontSize: 12),
                ),
              ),
              if (countdownLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: urgente
                        ? MatchPayTokens.accentUrgent.withValues(alpha: 0.14)
                        : palette.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: urgente
                          ? MatchPayTokens.accentUrgent.withValues(alpha: 0.35)
                          : palette.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: urgente
                            ? MatchPayTokens.accentUrgent
                            : palette.primaryDark,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        countdownLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: urgente
                              ? MatchPayTokens.accentUrgent
                              : palette.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            formatDiaCompleto(partido.fecha),
            style: MatchPayTokens.headlineStyle().copyWith(fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            [
              sportLabel,
              if (recinto != null && recinto.isNotEmpty) recinto,
            ].join(' · '),
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkSecondary,
            ),
          ),
          if (limite != null) ...[
            const SizedBox(height: 12),
            Text(
              context.tr(
                'inviteRespondDeadline',
                params: {'deadline': formatFechaHora(limite)},
              ),
              style: MatchPayTokens.bodySmallStyle().copyWith(
                fontWeight: FontWeight.w600,
                color: urgente
                    ? MatchPayTokens.accentUrgent
                    : MatchPayTokens.inkSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _enviando ? null : () => _responder(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          context.tr('inviteRespondGoing'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _enviando ? null : () => _responder(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    context.tr('inviteRespondCantGo'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
