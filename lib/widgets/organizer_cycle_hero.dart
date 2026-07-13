import 'package:flutter/material.dart';

import '../domain/estado_partido_publico.dart';
import '../domain/partido_lifecycle.dart';
import '../domain/organizer_cycle_logic.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../repositories/partido_repository.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../widgets/partido_estado_publico.dart';
import 'convocatoria_avatar_strip.dart';
import 'at_risk_convocatoria_actions.dart';
import 'matchpay_ui.dart';

enum OrganizerCyclePhase {
  empty,
  preparing,
  atRisk,
  needsResolution,
  registerExpenses,
  collecting,
  allPaid,
}

class OrganizerCycleSnapshot {
  final OrganizerCyclePhase phase;
  final ConvocatoriaCompleta? convocatoria;
  final PartidoCompleto? partidoJugado;
  /// Partidos con cobros abiertos (solo fase [collecting]).
  final int partidosCobroPendiente;
  /// Jugadores con cobro pendiente en esos partidos.
  final int jugadoresCobroPendiente;
  /// Suma pendiente en cuenta (SSOT saldo_acumulado del grupo).
  final double montoCobroPendienteTotal;
  /// Jugadores con deuda en cuenta.
  final List<ResumenJugador> deudoresGrupo;

  const OrganizerCycleSnapshot({
    required this.phase,
    this.convocatoria,
    this.partidoJugado,
    this.partidosCobroPendiente = 0,
    this.jugadoresCobroPendiente = 0,
    this.montoCobroPendienteTotal = 0,
    this.deudoresGrupo = const [],
  });

  static OrganizerCycleSnapshot resolve({
    required List<ConvocatoriaCompleta> convocatorias,
    required List<PartidoCompleto> partidosJugadosRecientes,
    List<ResumenJugador> resumenesGrupo = const [],
  }) {
    final sinResolver = convocatorias
        .where(
          (c) =>
              PartidoLifecycle.situacionOrganizador(c) ==
              ConvocatoriaOrganizadorSituacion.sinResolver,
        )
        .toList()
      ..sort((a, b) => b.partido.fecha.compareTo(a.partido.fecha));

    if (sinResolver.isNotEmpty) {
      return OrganizerCycleSnapshot(
        phase: OrganizerCyclePhase.needsResolution,
        convocatoria: sinResolver.first,
      );
    }

    final enCupoImposible = convocatorias
        .where((c) => PartidoEstadoPublicoView.resolve(c).cupoImposible)
        .toList()
      ..sort((a, b) => a.partido.fecha.compareTo(b.partido.fecha));

    if (enCupoImposible.isNotEmpty) {
      return OrganizerCycleSnapshot(
        phase: OrganizerCyclePhase.atRisk,
        convocatoria: enCupoImposible.first,
      );
    }

    final listasParaGastos = convocatorias
        .where(
          (c) =>
              PartidoLifecycle.situacionOrganizador(c) ==
              ConvocatoriaOrganizadorSituacion.listoParaGastos,
        )
        .toList()
      ..sort((a, b) => b.partido.fecha.compareTo(a.partido.fecha));

    if (listasParaGastos.isNotEmpty) {
      return OrganizerCycleSnapshot(
        phase: OrganizerCyclePhase.registerExpenses,
        convocatoria: listasParaGastos.first,
      );
    }

    var conCobrosPendientes =
        partidoConCobrosPendientes(partidosJugadosRecientes);
    final deudaGrupo = deudaTotalGrupo(resumenesGrupo);

    if (conCobrosPendientes == null && deudaGrupo > 0.005) {
      conCobrosPendientes = partidoFallbackDeudaGrupo(
        partidosJugadosRecientes,
        resumenesGrupo,
      );
    }

    if (conCobrosPendientes != null) {
      final pendientes =
          partidosConCobrosPendientes(partidosJugadosRecientes);
      final jugadoresPend =
          jugadoresPendientesUnicos(partidosJugadosRecientes);
      // SSOT grupo: saldo_acumulado (no sumar pendiente neto por partido).
      final montoPend = resumenesGrupo.isNotEmpty
          ? deudaGrupo
          : montoTotalCobrosPendientes(partidosJugadosRecientes);
      final deudores = resumenesGrupo
          .where((r) => r.tieneDeuda)
          .toList()
        ..sort((a, b) => b.deudaVisible.compareTo(a.deudaVisible));
      return OrganizerCycleSnapshot(
        phase: OrganizerCyclePhase.collecting,
        partidoJugado: conCobrosPendientes,
        partidosCobroPendiente: pendientes.isEmpty ? 1 : pendientes.length,
        jugadoresCobroPendiente: jugadoresPend > 0
            ? jugadoresPend
            : deudores.length,
        montoCobroPendienteTotal: montoPend,
        deudoresGrupo: deudores,
      );
    }

    final cerradoReciente =
        partidoCerradoReciente(partidosJugadosRecientes);
    if (cerradoReciente != null && deudaGrupo <= 0.005) {
      return OrganizerCycleSnapshot(
        phase: OrganizerCyclePhase.allPaid,
        partidoJugado: cerradoReciente,
      );
    }

    final proximas = convocatorias
        .where(
          (c) =>
              PartidoLifecycle.situacionOrganizador(c) ==
              ConvocatoriaOrganizadorSituacion.preparando,
        )
        .toList()
      ..sort((a, b) => a.partido.fecha.compareTo(b.partido.fecha));

    if (proximas.isNotEmpty) {
      return OrganizerCycleSnapshot(
        phase: OrganizerCyclePhase.preparing,
        convocatoria: proximas.first,
      );
    }

    return const OrganizerCycleSnapshot(phase: OrganizerCyclePhase.empty);
  }

  String phaseLabel(MatchPayStrings l10n) {
    switch (phase) {
      case OrganizerCyclePhase.empty:
        return l10n.tr('organizerCyclePhaseEmpty');
      case OrganizerCyclePhase.preparing:
        return l10n.tr('organizerCyclePhasePreparing');
      case OrganizerCyclePhase.atRisk:
        return l10n.tr('organizerCyclePhaseAtRisk');
      case OrganizerCyclePhase.needsResolution:
        return l10n.tr('organizerCyclePhaseNeedsResolution');
      case OrganizerCyclePhase.registerExpenses:
        return l10n.tr('organizerCyclePhaseRegister');
      case OrganizerCyclePhase.collecting:
        return l10n.tr('organizerCyclePhaseCollecting');
      case OrganizerCyclePhase.allPaid:
        return l10n.tr('organizerCyclePhaseDone');
    }
  }
}

/// Hero contextual: guía al organizador según la etapa del ciclo del partido.
class OrganizerCycleHero extends StatelessWidget {
  final OrganizerCycleSnapshot snapshot;
  final VoidCallback onPrimaryAction;
  final VoidCallback? onCreateMatch;
  final VoidCallback? onMarkPlayed;
  final VoidCallback? onReschedule;
  final VoidCallback? onCancel;

  /// Inyección / tests: si hay partidoId, tienen prioridad sobre CupoActions.
  final Future<void> Function(int partidoId)? rescheduleOverride;
  final Future<void> Function(int partidoId)? cancelOverride;

  const OrganizerCycleHero({
    super.key,
    required this.snapshot,
    required this.onPrimaryAction,
    this.onCreateMatch,
    this.onMarkPlayed,
    this.onReschedule,
    this.onCancel,
    this.rescheduleOverride,
    this.cancelOverride,
  });

  @override
  Widget build(BuildContext context) {
    switch (snapshot.phase) {
      case OrganizerCyclePhase.empty:
        return _EmptyHero(onCreateMatch: onCreateMatch ?? onPrimaryAction);
      case OrganizerCyclePhase.preparing:
        return _PreparingHero(
          convocatoria: snapshot.convocatoria!,
          onTap: onPrimaryAction,
        );
      case OrganizerCyclePhase.atRisk:
        return _AtRiskHero(
          convocatoria: snapshot.convocatoria!,
          rescheduleOverride: rescheduleOverride,
          cancelOverride: cancelOverride,
        );
      case OrganizerCyclePhase.needsResolution:
        return _ResolutionHero(
          convocatoria: snapshot.convocatoria!,
          onMarkPlayed: onMarkPlayed ?? onPrimaryAction,
          rescheduleOverride: rescheduleOverride,
          cancelOverride: cancelOverride,
        );
      case OrganizerCyclePhase.registerExpenses:
        return _RegisterHero(
          convocatoria: snapshot.convocatoria!,
          onTap: onPrimaryAction,
        );
      case OrganizerCyclePhase.collecting:
        return const SizedBox.shrink();
      case OrganizerCyclePhase.allPaid:
        return _AllPaidHero(completo: snapshot.partidoJugado!);
    }
  }
}

class _CycleHeroShell extends StatelessWidget {
  final SportThemePalette palette;
  final String phaseLabel;
  final String title;
  final String? subtitle;
  final String? contextLine;
  final Widget? body;
  final String? ctaLabel;
  final VoidCallback? onTap;
  final bool celebratory;
  final bool interactiveBody;
  final bool riskIndicator;

  const _CycleHeroShell({
    required this.palette,
    required this.phaseLabel,
    required this.title,
    this.subtitle,
    this.contextLine,
    this.body,
    this.ctaLabel,
    this.onTap,
    this.celebratory = false,
    this.interactiveBody = false,
    this.riskIndicator = false,
  });

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: celebratory
            ? [
                MatchPayTokens.accentSuccess.withValues(alpha: 0.92),
                MatchPayTokens.accentSuccess,
                const Color(0xFF2E7D52),
              ]
            : [
                palette.primaryDark,
                palette.primary,
                palette.primary.withValues(alpha: 0.88),
              ],
      ),
      boxShadow: MatchPayTokens.shadowHero(
        celebratory ? MatchPayTokens.accentSuccess : palette.primary,
      ),
    );
  }

  Widget _cardStack() {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          right: -20,
          bottom: -30,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.14,
              child: Text(
                celebratory ? '✅' : palette.emoji,
                style: const TextStyle(fontSize: 140),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPhaseHeader(),
              if (contextLine != null && contextLine!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  contextLine!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.96),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                    height: 1.25,
                  ),
                ),
              ],
              SizedBox(height: contextLine != null ? 14 : 12),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: riskIndicator ? 20 : 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                  height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: riskIndicator ? 0.84 : 0.9,
                    ),
                    fontSize: riskIndicator ? 13.5 : 14,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
              if (body != null) ...[
                const SizedBox(height: 14),
                body!,
              ],
              if (ctaLabel != null && onTap != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: celebratory
                        ? MatchPayTokens.accentSuccess
                        : palette.primaryDark,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        MatchPayTokens.radiusButton,
                      ),
                    ),
                  ),
                  child: Text(
                    ctaLabel!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseHeader() {
    final label = Text(
      phaseLabel.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: riskIndicator ? 0.9 : 0.82),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.05,
      ),
    );

    if (!riskIndicator) return label;

    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: const Color(0xFFFF4D4F),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4D4F).withValues(alpha: 0.5),
                blurRadius: 5,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: interactiveBody
          ? Container(
              decoration: _cardDecoration(),
              child: _cardStack(),
            )
          : Material(
              color: Colors.transparent,
              child: Ink(
                decoration: _cardDecoration(),
                child: _cardStack(),
              ),
            ),
    );

    // Solo envolver con tap global si no hay botón CTA ni acciones en el body.
    if (interactiveBody || onTap == null || ctaLabel != null) return card;

    return MatchPayTapScale(onTap: onTap!, child: card);
  }
}

class _EmptyHero extends StatelessWidget {
  final VoidCallback onCreateMatch;

  const _EmptyHero({required this.onCreateMatch});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return _CycleHeroShell(
      palette: palette,
      phaseLabel: l10n.tr('organizerCyclePhaseEmpty'),
      title: l10n.tr('organizerCycleEmptyTitle'),
      subtitle: l10n.tr('organizerCycleEmptyBody'),
      ctaLabel: l10n.tr('organizerCycleCreateMatch'),
      onTap: onCreateMatch,
    );
  }
}

class _ConvocatoriaRosterBody extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final PartidoEstadoPublicoView view;

  const _ConvocatoriaRosterBody({
    required this.convocatoria,
    required this.view,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final confirmados = convocatoria.confirmados;
    final pendientes = convocatoria.pendientes;
    final cupos = p.cuposMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConvocatoriaAvatarStrip(
          titulares: convocatoria.titulares,
          cuposMax: cupos,
          onDarkBackground: true,
        ),
        if (convocatoria.titulares.isNotEmpty || cupos > 0)
          const SizedBox(height: 12),
        if (convocatoria.convocatoriaEnviada) ...[
          PartidoEstadoPublicoMessage(
            view: view,
            fechaPartido: p.fecha,
            textColor: Colors.white,
            titleSize: 14,
            bodySize: 12.5,
            showBody: false,
          ),
          const SizedBox(height: 12),
        ],
        if (cupos > 0)
          Text(
            l10n.tr(
              'organizerCycleRosterFull',
              params: {
                'confirmed': '$confirmados',
                'max': '$cupos',
              },
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          Text(
            l10n.tr(
              'organizerCycleConfirmedLine',
              params: {
                'confirmed': '$confirmados',
                'pending': '$pendientes',
              },
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StatusDot(
              color: const Color(0xFF69F0AE),
              label: l10n.tr(
                'organizerCycleConfirmedBadge',
                params: {'count': '$confirmados'},
              ),
            ),
            const SizedBox(width: 12),
            if (pendientes > 0)
              _StatusDot(
                color: const Color(0xFFFFD54F),
                label: l10n.tr(
                  'organizerCyclePendingBadge',
                  params: {'count': '$pendientes'},
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PreparingHero extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final VoidCallback onTap;

  const _PreparingHero({
    required this.convocatoria,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final palette = SportThemeConfig.paletteFor(p.sportType);
    final confirmados = convocatoria.confirmados;
    final pendientes = convocatoria.pendientes;
    final cupos = p.cuposMax;
    final faltan = cupos > 0 ? (cupos - confirmados).clamp(0, cupos) : 0;

    final hoy = esMismoDia(p.fecha, DateTime.now());
    final title = hoy
        ? l10n.tr(
            'organizerCyclePreparingToday',
            params: {
              'emoji': palette.emoji,
              'time': formatHora(p.fecha),
            },
          )
        : l10n.tr(
            'organizerCyclePreparingSoon',
            params: {
              'emoji': palette.emoji,
              'when': formatEnCuanto(p.fecha),
            },
          );

    String? insight;
    if (hoy && pendientes == 0 && faltan == 0) {
      insight = l10n.tr('organizerCycleReadyTonight');
    } else if (pendientes > 0) {
      insight = l10n.tr(
        'organizerCycleNeedConfirmations',
        params: {'count': '$pendientes'},
      );
    } else if (faltan > 0) {
      insight = l10n.tr(
        'organizerCyclePlayersNeeded',
        params: {'count': '$faltan'},
      );
    }

    return _CycleHeroShell(
      palette: palette,
      phaseLabel: l10n.tr('organizerCyclePhasePreparing'),
      title: title,
      subtitle: insight,
      body: _ConvocatoriaRosterBody(
        convocatoria: convocatoria,
        view: PartidoEstadoPublicoView.resolve(convocatoria),
      ),
      ctaLabel: l10n.tr('organizerCycleViewConvocatoria'),
      onTap: onTap,
    );
  }
}

class _AtRiskHero extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final Future<void> Function(int partidoId)? rescheduleOverride;
  final Future<void> Function(int partidoId)? cancelOverride;

  const _AtRiskHero({
    required this.convocatoria,
    this.rescheduleOverride,
    this.cancelOverride,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final palette = SportThemeConfig.paletteFor(p.sportType);
    final partidoId = p.id;

    final venue = p.recinto?.trim();
    final matchLine = [
      formatDiaCompleto(p.fecha),
      if (venue != null && venue.isNotEmpty) venue,
    ].join(' · ');

    return _CycleHeroShell(
      palette: palette,
      phaseLabel: l10n.tr('organizerCyclePhaseAtRisk'),
      riskIndicator: true,
      contextLine: matchLine,
      title: l10n.tr('organizerCycleAtRiskTitle'),
      subtitle: l10n.tr('organizerCycleAtRiskBody'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.tr('organizerCycleAtRiskAction'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          if (partidoId != null) ...[
            const SizedBox(height: 16),
            AtRiskConvocatoriaActions(
              partidoId: partidoId,
              reprogramarOverride: rescheduleOverride,
              cancelarOverride: cancelOverride,
            ),
          ],
        ],
      ),
      interactiveBody: partidoId != null,
    );
  }
}

class _ResolutionHero extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final VoidCallback onMarkPlayed;
  final Future<void> Function(int partidoId)? rescheduleOverride;
  final Future<void> Function(int partidoId)? cancelOverride;

  const _ResolutionHero({
    required this.convocatoria,
    required this.onMarkPlayed,
    this.rescheduleOverride,
    this.cancelOverride,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final palette = SportThemeConfig.paletteFor(p.sportType);
    final confirmados = convocatoria.confirmados;
    final cupos = p.cuposMax;
    final partidoId = p.id;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
    );

    return _CycleHeroShell(
      palette: palette,
      phaseLabel: l10n.tr('organizerCyclePhaseNeedsResolution'),
      title: l10n.tr('organizerCycleUnresolvedTitle'),
      subtitle: l10n.tr('organizerCycleUnresolvedBody'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConvocatoriaAvatarStrip(
            titulares: convocatoria.titulares,
            cuposMax: cupos,
            onDarkBackground: true,
          ),
          const SizedBox(height: 12),
          Text(
            formatDiaCompleto(p.fecha),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr(
              'organizerCycleUnresolvedRoster',
              params: {
                'confirmed': '$confirmados',
                'slots': '$cupos',
              },
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onMarkPlayed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: palette.primaryDark,
              minimumSize: const Size.fromHeight(44),
              elevation: 0,
              shape: shape,
            ),
            icon: const Icon(Icons.sports, size: 18),
            label: Text(
              l10n.tr('organizerCycleUnresolvedMarkPlayed'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (partidoId != null) ...[
            const SizedBox(height: 8),
            // Mismo flujo que la ficha «en riesgo»: CupoActions + navigator raíz.
            AtRiskConvocatoriaActions(
              partidoId: partidoId,
              rescheduleFilled: false,
              rescheduleLabel:
                  l10n.tr('organizerCycleUnresolvedReschedule'),
              cancelLabel: l10n.tr('organizerCycleUnresolvedCancel'),
              reprogramarOverride: rescheduleOverride,
              cancelarOverride: cancelOverride,
            ),
          ],
        ],
      ),
      interactiveBody: partidoId != null,
    );
  }
}

class _RegisterHero extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final VoidCallback onTap;

  const _RegisterHero({
    required this.convocatoria,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final palette = SportThemeConfig.paletteFor(p.sportType);
    final cuando = formatTiempoRelativo(p.fecha);

    return _CycleHeroShell(
      palette: palette,
      phaseLabel: l10n.tr('organizerCyclePhaseRegister'),
      title: l10n.tr('organizerCycleRegisterTitle'),
      subtitle: l10n.tr(
        'organizerCycleRegisterBody',
        params: {'when': cuando},
      ),
      body: Text(
        formatDiaCompleto(p.fecha),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      ctaLabel: l10n.tr('organizerCycleRegisterCta'),
      onTap: onTap,
    );
  }
}

class _AllPaidHero extends StatelessWidget {
  final PartidoCompleto completo;

  const _AllPaidHero({required this.completo});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = completo.partido;
    final recinto = p.recinto?.trim();
    final fecha = formatDiaMensaje(p.fecha);
    final matchRef = recinto != null && recinto.isNotEmpty
        ? l10n.tr(
            'organizerCycleAllPaidMatchRef',
            params: {'date': fecha, 'place': recinto},
          )
        : l10n.tr(
            'organizerCycleAllPaidMatchDate',
            params: {'date': fecha},
          );

    return _CycleHeroShell(
      palette: context.sportPalette,
      phaseLabel: l10n.tr('organizerCyclePhaseDone'),
      title: l10n.tr('organizerCycleAllPaidTitle'),
      subtitle: l10n.tr('organizerCycleAllPaidBody'),
      body: Text(
        matchRef,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      celebratory: true,
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
