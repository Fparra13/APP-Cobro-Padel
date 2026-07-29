import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_repositories.dart';
import '../core/offline_status_controller.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import '../core/supabase_parse.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../utils/single_action.dart';
import '../widgets/convocatoria_avatar_strip.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/matchpay_ui.dart';
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
  bool _loading = true;
  bool _loadFailed = false;
  MiConvocatoria? _data;
  ConvocatoriaCompleta? _completa;
  String? _organizadorNombre;
  String? _organizadorFotoUrl;

  @override
  void initState() {
    super.initState();
    _data = widget.convocatoria;
    _loading = widget.convocatoria == null && widget.entry == null;
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
      final mi = fresh ?? _data ?? widget.convocatoria;
      ConvocatoriaCompleta? roster;
      if (mi != null && mi.partido.id != null) {
        roster = await repos.getConvocatoriaRosterParaJugador(
          partidoId: widget.partidoId,
          partido: mi.partido,
        );
      }
      final org = await _resolveOrganizador(repos);
      if (!mounted) return;
      setState(() {
        _data = mi;
        _completa = roster;
        _organizadorNombre = org?.nombre;
        _organizadorFotoUrl = org?.fotoUrl;
        _loadFailed = _data == null && widget.entry == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = _data ?? widget.convocatoria;
        _loadFailed = _data == null && widget.entry == null;
        _loading = false;
      });
    }
  }

  /// Resuelve identidad del organizador para UI (sin cambiar confirmación).
  Future<({String nombre, String? fotoUrl})?> _resolveOrganizador(
    AppRepositories repos,
  ) async {
    try {
      final cuentas = await repos.listarMisCuentasSaldo();
      String? orgId;
      if (SupabaseConfig.isConfigured) {
        try {
          final row = await SupabaseHelpers.client
              .from('partidos')
              .select('organizador_id')
              .eq('id', widget.partidoId)
              .maybeSingle();
          orgId = SupabaseParse.toStringOrNull(
            Map<String, dynamic>.from(row ?? {})['organizador_id'],
          );
        } catch (_) {}
      }

      if (orgId != null && orgId.isNotEmpty) {
        for (final c in cuentas) {
          if (c.organizadorId == orgId) {
            return (nombre: c.nombreOrganizador, fotoUrl: c.fotoUrl);
          }
        }
        final orgs = await repos.listarMisOrganizadores();
        for (final o in orgs) {
          if (o.id == orgId) {
            return (nombre: o.nombre, fotoUrl: o.fotoUrl);
          }
        }
        final pago = await repos.getDatosPagoOrganizador(orgId);
        final nombre = pago?.organizadorNombre.trim();
        if (nombre != null && nombre.isNotEmpty) {
          return (nombre: nombre, fotoUrl: null);
        }
      }

      if (cuentas.length == 1) {
        final c = cuentas.first;
        return (nombre: c.nombreOrganizador, fotoUrl: c.fotoUrl);
      }
      final orgs = await repos.listarMisOrganizadores();
      if (orgs.length == 1) {
        return (nombre: orgs.first.nombre, fotoUrl: orgs.first.fotoUrl);
      }
    } catch (_) {}
    return null;
  }

  ConvocatoriaJugadorEntry? get _entry => _data?.entry ?? widget.entry;

  bool get _requiereRespuesta => _data?.requiereRespuesta ?? false;

  bool get _puedeDeclinarTrasConfirmar =>
      _data?.puedeDeclinarTrasConfirmar ?? false;

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
    if (context.read<OfflineStatusController>().isReadOnly) {
      NotificationService.instance.showInAppSnack(
        context.l10n.tr('offlineWriteBlocked'),
      );
      return;
    }
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
                      params: {
                        'date': formatFechaEncuentro(
                          partido.fecha,
                          contexto: FechaEncuentroContexto.futuro,
                        ),
                      },
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
        AppRepositories.notifyDataChanged();
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

  /// Un solo aviso superior: estado personal + plazo (si aplica).
  Widget? _unifiedTopBanner(BuildContext context) {
    final l10n = context.l10n;
    final entry = _entry;
    final data = _data;
    final deadline = entry?.tiempoLimite;

    if (data?.esReprogramadoPendiente == true) {
      return _UnifiedTopBanner(
        icon: Icons.event_repeat_rounded,
        title: l10n.tr('matchStatusPlayerRescheduledConfirm'),
        subtitle: deadline != null
            ? l10n.tr(
                'respondBeforeDeadline',
                params: {'deadline': formatFechaHora(deadline)},
              )
            : l10n.tr(
                'matchStatusRescheduledBody',
                params: {
                  'date': formatFechaEncuentro(
                    data!.partido.fecha,
                    contexto: FechaEncuentroContexto.futuro,
                  ),
                },
              ),
        tone: _UnifiedBannerTone.urgent,
      );
    }

    if (_requiereRespuesta) {
      return _UnifiedTopBanner(
        icon: Icons.hourglass_top_rounded,
        title: l10n.tr('matchStatusPlayerYouPending'),
        subtitle: deadline != null
            ? l10n.tr(
                'respondBeforeDeadline',
                params: {'deadline': formatFechaHora(deadline)},
              )
            : null,
        tone: _UnifiedBannerTone.urgent,
      );
    }

    if (entry == null) return null;

    return switch (entry.estado) {
      EstadoConfirmacion.confirmado => _UnifiedTopBanner(
          icon: Icons.check_circle_rounded,
          title: l10n.tr('respondConfirmedStatus'),
          tone: _UnifiedBannerTone.success,
        ),
      EstadoConfirmacion.rechazado || EstadoConfirmacion.noRespondio =>
        _UnifiedTopBanner(
          icon: Icons.cancel_rounded,
          title: l10n.tr('respondDeclinedStatus'),
          tone: _UnifiedBannerTone.declined,
        ),
      EstadoConfirmacion.invitado => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final partido = data?.partido;
    final entry = _entry;
    final topBanner = _unifiedTopBanner(context);

    return Scaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(title: Text(context.l10n.tr('convocatoriaTitle'))),
      body: _loading && data == null && entry == null
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.tr('convocatoriaLoadError'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _loadFailed = false;
                            });
                            _load();
                          },
                          child: Text(context.l10n.tr('retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          if (topBanner != null) ...[
                            topBanner,
                            const SizedBox(height: 12),
                          ],
                          if (_organizadorNombre != null &&
                              _organizadorNombre!.trim().isNotEmpty) ...[
                            _OrganizadorHeader(
                              nombre: _organizadorNombre!.trim(),
                              fotoUrl: _organizadorFotoUrl,
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (partido != null)
                            _DetallePartidoCard(
                              partido: partido,
                              onOpenMap:
                                  partido.recinto?.trim().isNotEmpty == true
                                      ? () => _abrirMapa(partido)
                                      : null,
                              mapIsExact: partido.mapsLocation.hasExactLocation,
                            ),
                          if (_completa != null) ...[
                            const SizedBox(height: 14),
                            _BloqueSocialConfirmados(
                              titulares: _completa!.titulares,
                              cuposMax: partido?.cuposMax ??
                                  _completa!.partido.cuposMax,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_requiereRespuesta)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    _enviando ? null : () => _responder(true),
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
                                label: Text(
                                  context.l10n.tr('respondConfirmButton'),
                                ),
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
                                label: Text(
                                  context.l10n.tr('respondDeclineButton'),
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade300),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_puedeDeclinarTrasConfirmar)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: OutlinedButton.icon(
                            onPressed:
                                _enviando ? null : () => _responder(false),
                            icon: _enviando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.event_busy_outlined),
                            label: Text(
                              context.l10n.tr('respondDeclineAfterConfirm'),
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

enum _UnifiedBannerTone { urgent, success, declined }

class _UnifiedTopBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final _UnifiedBannerTone tone;

  const _UnifiedTopBanner({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color border) = switch (tone) {
      _UnifiedBannerTone.urgent => (
          MatchPayTokens.accentUrgent,
          MatchPayTokens.accentUrgentBg,
          MatchPayTokens.accentUrgentBorder.withValues(alpha: 0.45),
        ),
      _UnifiedBannerTone.success => (
          MatchPayTokens.accentSuccess,
          MatchPayTokens.accentSuccessBg,
          MatchPayTokens.accentSuccess.withValues(alpha: 0.35),
        ),
      _UnifiedBannerTone.declined => (
          MatchPayTokens.accentError,
          MatchPayTokens.accentErrorBg,
          MatchPayTokens.accentError.withValues(alpha: 0.3),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MatchPayTokens.titleSmallStyle(color: fg).copyWith(
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: MatchPayTokens.bodySmallStyle(
                      color: fg.withValues(alpha: 0.9),
                    ).copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrganizadorHeader extends StatelessWidget {
  final String nombre;
  final String? fotoUrl;

  const _OrganizadorHeader({
    required this.nombre,
    this.fotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        JugadorAvatar(
          nombre: nombre,
          fotoUrl: fotoUrl,
          size: 36,
          borderRadius: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.l10n.tr(
              'respondOrganizedBy',
              params: {'name': nombre},
            ),
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkSecondary,
            ).copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _BloqueSocialConfirmados extends StatelessWidget {
  final List<ConvocatoriaJugadorEntry> titulares;
  final int cuposMax;

  const _BloqueSocialConfirmados({
    required this.titulares,
    required this.cuposMax,
  });

  static String resumenNumerico(
    List<ConvocatoriaJugadorEntry> titulares,
    MatchPayStrings l10n,
  ) {
    var confirmados = 0;
    var pendientes = 0;
    var noVa = 0;
    for (final e in titulares) {
      switch (e.estado) {
        case EstadoConfirmacion.confirmado:
          confirmados++;
        case EstadoConfirmacion.invitado:
          pendientes++;
        case EstadoConfirmacion.rechazado:
        case EstadoConfirmacion.noRespondio:
          noVa++;
      }
    }

    if (confirmados == 0 && pendientes == 0 && noVa == 0) {
      return l10n.tr('respondNobodyConfirmedYet');
    }

    final parts = <String>[
      if (confirmados > 0)
        l10n.tr(
          'respondSummaryConfirmed',
          params: {'n': '$confirmados'},
        ),
      if (pendientes > 0)
        l10n.tr(
          pendientes == 1
              ? 'respondSummaryPendingOne'
              : 'respondSummaryPending',
          params: {'n': '$pendientes'},
        ),
      if (noVa > 0)
        l10n.tr(
          noVa == 1 ? 'respondSummaryDeclinedOne' : 'respondSummaryDeclined',
          params: {'n': '$noVa'},
        ),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasInvitees = titulares.isNotEmpty;
    return MatchPaySurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('respondWhoIsGoing'),
            style: MatchPayTokens.titleSmallStyle(),
          ),
          if (hasInvitees) ...[
            const SizedBox(height: 10),
            ConvocatoriaAvatarStrip(
              titulares: titulares,
              cuposMax: cuposMax,
              size: 56,
              overlap: 40,
              mode: ConvocatoriaAvatarStripMode.player,
              filter: ConvocatoriaAvatarStripFilter.allInvitees,
              showStatusBadges: true,
              maxVisible: 8,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            resumenNumerico(titulares, l10n),
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkSecondary,
            ).copyWith(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DetallePartidoCard extends StatelessWidget {
  final Partido partido;
  final VoidCallback? onOpenMap;
  final bool mapIsExact;

  const _DetallePartidoCard({
    required this.partido,
    this.onOpenMap,
    this.mapIsExact = false,
  });

  @override
  Widget build(BuildContext context) {
    final sport = partido.sportType;
    final palette = SportThemeConfig.paletteFor(sport);
    final lang = context.readSettings().locale.languageCode;
    final recinto = partido.recinto?.trim();
    final fecha = formatFechaEncuentro(
      partido.fecha,
      contexto: FechaEncuentroContexto.futuro,
    );

    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sport.labelForLocale(lang),
                      style: MatchPayTokens.titleMediumStyle(
                        color: palette.primaryDark,
                      ).copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fecha,
                      style: MatchPayTokens.bodySmallStyle(
                        color: MatchPayTokens.inkSecondary,
                      ).copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (recinto != null && recinto.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: MatchPayTokens.inkMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recinto,
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.ink,
                    ).copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ],
            ),
            if (onOpenMap != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onOpenMap,
                icon: Icon(
                  mapIsExact ? Icons.map : Icons.map_outlined,
                  size: 18,
                ),
                label: Text(
                  mapIsExact
                      ? context.l10n.tr('openExactVenueMap')
                      : context.l10n.tr('openVenueMapTooltip'),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (!mapIsExact)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    context.l10n.tr('venueMapSearchHint'),
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkMuted,
                    ).copyWith(fontSize: 11),
                  ),
                ),
            ],
          ],
          if (partido.notas != null && partido.notas!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 18, color: MatchPayTokens.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    partido.notas!.trim(),
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
