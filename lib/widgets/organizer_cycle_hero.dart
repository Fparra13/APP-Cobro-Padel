import 'package:flutter/material.dart';

import '../domain/organizer_cycle_logic.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../repositories/partido_repository.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'jugador_avatar.dart';
import 'matchpay_ui.dart';

enum OrganizerCyclePhase {
  empty,
  preparing,
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
    final vencidas = convocatorias
        .where((c) => c.partido.convocatoriaFechaPasada)
        .toList()
      ..sort((a, b) => b.partido.fecha.compareTo(a.partido.fecha));

    if (vencidas.isNotEmpty) {
      return OrganizerCycleSnapshot(
        phase: OrganizerCyclePhase.registerExpenses,
        convocatoria: vencidas.first,
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
        .where((c) => !c.partido.convocatoriaFechaPasada)
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

  const OrganizerCycleHero({
    super.key,
    required this.snapshot,
    required this.onPrimaryAction,
    this.onCreateMatch,
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
  final Widget? body;
  final String? ctaLabel;
  final VoidCallback? onTap;
  final bool celebratory;

  const _CycleHeroShell({
    required this.palette,
    required this.phaseLabel,
    required this.title,
    this.subtitle,
    this.body,
    this.ctaLabel,
    this.onTap,
    this.celebratory = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
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
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -30,
              child: Opacity(
                opacity: 0.14,
                child: Text(
                  celebratory ? '✅' : palette.emoji,
                  style: const TextStyle(fontSize: 140),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    phaseLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.35,
                      height: 1.15,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
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
        ),
      ),
    );

    if (onTap == null || ctaLabel != null) return content;

    return MatchPayTapScale(onTap: onTap!, child: content);
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

    final roster = convocatoria.titulares
        .where((j) => j.estado == EstadoConfirmacion.confirmado)
        .take(5)
        .toList();

    return _CycleHeroShell(
      palette: palette,
      phaseLabel: l10n.tr('organizerCyclePhasePreparing'),
      title: title,
      subtitle: insight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          if (roster.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: Stack(
                children: [
                  for (var i = 0; i < roster.length; i++)
                    Positioned(
                      left: i * 22.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.primaryDark,
                            width: 2,
                          ),
                        ),
                        child: JugadorAvatar(
                          nombre: roster[i].jugador.nombre,
                          fotoUrl: roster[i].jugador.fotoUrl,
                          fotoPath: roster[i].jugador.fotoPath,
                          size: 30,
                          borderRadius: 15,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      ctaLabel: l10n.tr('organizerCycleViewConvocatoria'),
      onTap: onTap,
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
