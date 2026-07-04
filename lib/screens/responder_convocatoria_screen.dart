import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/sport_theme.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../utils/single_action.dart';
import '../widgets/sport_icon.dart';

/// Detalle de convocatoria con confirmación explícita (nunca automática).
class ResponderConvocatoriaScreen extends StatefulWidget {
  final int partidoId;
  final MiConvocatoria? convocatoria;

  /// Compatibilidad con rutas antiguas.
  final ConvocatoriaJugadorEntry? entry;

  const ResponderConvocatoriaScreen({
    super.key,
    required this.partidoId,
    this.convocatoria,
    this.entry,
  });

  @override
  State<ResponderConvocatoriaScreen> createState() =>
      _ResponderConvocatoriaScreenState();
}

class _ResponderConvocatoriaScreenState
    extends State<ResponderConvocatoriaScreen> {
  bool _enviando = false;
  MiConvocatoria? _data;

  @override
  void initState() {
    super.initState();
    _data = widget.convocatoria;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    try {
      final repos = AppRepositories.isReady
          ? AppRepositories.I
          : context.repos;
      final fresh = await repos.getMiConvocatoria(widget.partidoId);
      if (mounted) setState(() => _data = fresh ?? _data ?? widget.convocatoria);
    } catch (_) {
      if (mounted) {
        setState(() => _data = _data ?? widget.convocatoria);
      }
    }
  }

  ConvocatoriaJugadorEntry? get _entry => _data?.entry ?? widget.entry;

  bool get _requiereRespuesta => _data?.requiereRespuesta ?? false;

  bool get _yaRespondio {
    final e = _entry;
    if (e == null) return false;
    return e.estado != EstadoConfirmacion.invitado;
  }

  Future<void> _abrirMapa(Partido partido) async {
    try {
      final ok = await partido.mapsLocation.open();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('openVenueMapError'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('openVenueMapError'))),
        );
      }
    }
  }

  Future<void> _responder(bool confirmo) async {
    final partido = _data?.partido;
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
              ? ctx.l10n.tr('respondConfirmTitle')
              : ctx.l10n.tr('respondDeclineTitle'),
        ),
        content: Text(
          partido != null
              ? (confirmo
                  ? ctx.l10n.tr(
                      'respondConfirmBodyWithDate',
                      params: {'date': formatDiaCompleto(partido.fecha)},
                    )
                  : ctx.l10n.tr('respondDeclineBodyOrganizer'))
              : (confirmo
                  ? ctx.l10n.tr('respondConfirmBodyGeneric')
                  : ctx.l10n.tr('respondDeclineBodyGeneric')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  confirmo ? Colors.green.shade700 : Colors.red.shade700,
            ),
            child: Text(
              confirmo
                  ? ctx.l10n.tr('respondYesGoing')
                  : ctx.l10n.tr('respondCannotGo'),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await runOnce('conv-resp-${widget.partidoId}', () async {
      setState(() => _enviando = true);
      try {
        final repos = AppRepositories.isReady
            ? AppRepositories.I
            : context.repos;
        await repos.responderConvocatoria(
          partidoId: widget.partidoId,
          confirmo: confirmo,
        );
        await ConvocatoriaListaEsperaService().sincronizar(widget.partidoId);
        await _load();
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmo
                  ? context.l10n.tr('respondConfirmedSnack')
                  : context.l10n.tr('respondDeclinedSnack'),
            ),
          ),
        );
        if (!_requiereRespuesta) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$e'),
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
    final data = _data;
    final partido = data?.partido;
    final entry = _entry;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.tr('convocatoriaTitle'))),
      body: data == null && entry == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_requiereRespuesta)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.orange.shade800),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  context.l10n.tr('respondMustAnswerBanner'),
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_requiereRespuesta) const SizedBox(height: 16),
                      if (partido != null) _DetallePartidoCard(
                        partido: partido,
                        entry: entry,
                        onOpenMap: partido.recinto?.trim().isNotEmpty == true
                            ? () => _abrirMapa(partido)
                            : null,
                        mapIsExact: partido.mapsLocation.hasExactLocation,
                      ),
                      if (entry?.esSuplente ?? false) ...[
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              context.l10n.tr('respondWaitlistBody'),
                            ),
                          ),
                        ),
                      ] else if (_yaRespondio && entry != null) ...[
                        const SizedBox(height: 16),
                        Card(
                          color: entry.estado == EstadoConfirmacion.confirmado
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(
                                  entry.estado == EstadoConfirmacion.confirmado
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: entry.estado ==
                                          EstadoConfirmacion.confirmado
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                  size: 32,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    entry.estado ==
                                            EstadoConfirmacion.confirmado
                                        ? context.l10n.tr('respondConfirmedStatus')
                                        : context.l10n.tr('respondDeclinedStatus'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_requiereRespuesta && !(entry?.esSuplente ?? false))
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: _enviando ? null : () => _responder(true),
                            icon: _enviando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle),
                            label: Text(context.l10n.tr('respondConfirmButton')),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed:
                                _enviando ? null : () => _responder(false),
                            icon: const Icon(Icons.close),
                            label: Text(context.l10n.tr('respondDeclineButton')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DetallePartidoCard extends StatelessWidget {
  final Partido partido;
  final ConvocatoriaJugadorEntry? entry;
  final VoidCallback? onOpenMap;
  final bool mapIsExact;

  const _DetallePartidoCard({
    required this.partido,
    required this.entry,
    this.onOpenMap,
    this.mapIsExact = false,
  });

  @override
  Widget build(BuildContext context) {
    final sport = partido.sportType;
    final palette = SportThemeConfig.paletteFor(sport);
    final lang = context.readSettings().locale.languageCode;
    final recinto = partido.recinto?.trim();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SportChargeChip(sport: sport),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SportIcon(
                    sport: sport,
                    color: palette.primaryDark,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tr(
                          'respondMatchSportLine',
                          params: {
                            'sport': sport.labelForLocale(lang),
                          },
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatDiaCompleto(partido.fecha),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (recinto != null && recinto.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 20, color: Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.tr('venueLabel'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recinto,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (onOpenMap != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: onOpenMap,
                        icon: Icon(
                          mapIsExact ? Icons.map : Icons.map_outlined,
                          size: 20,
                        ),
                        label: Text(
                          mapIsExact
                              ? context.l10n.tr('openExactVenueMap')
                              : context.l10n.tr('openVenueMapTooltip'),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                        ),
                      ),
                      if (!mapIsExact)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            context.l10n.tr('venueMapSearchHint'),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
            if (partido.notas != null && partido.notas!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.notes,
                label: context.l10n.tr('notesLabel'),
                value: partido.notas!.trim(),
              ),
            ],
            if (entry?.tiempoLimite != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.timer_outlined,
                label: context.l10n.tr('respondDeadlineLabel'),
                value: context.l10n.tr(
                  'respondBeforeDeadline',
                  params: {
                    'deadline': formatFechaHora(entry!.tiempoLimite!),
                  },
                ),
                valueColor: Colors.orange.shade800,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
