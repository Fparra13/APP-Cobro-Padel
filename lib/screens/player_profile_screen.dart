import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/sport_type.dart';
import '../domain/player_home_stats.dart';
import '../domain/player_invite_response.dart';
import '../domain/player_profile_badges.dart';
import '../domain/player_profile_pride.dart';
import '../domain/story_models.dart';
import '../l10n/matchpay_strings.dart';
import '../models/detalle_partido.dart';
import '../models/jugador.dart';
import '../models/mi_convocatoria.dart';
import '../services/local_narrative_engine.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/badges/badge_showcase_board.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/narrative/story_card_view.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/sport_icon.dart';

/// Perfil privado del jugador: identidad, orgullo y insignias (sin finanzas).
class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  Jugador? _perfil;
  PlayerProfilePrideData? _pride;
  List<PlayerBehaviorBadgeView> _badges = const [];
  List<_ProfileActivityPoint> _activities = const [];
  StoryCard? _todayStory;
  int _companeros = 0;
  bool _loading = true;
  String? _error;
  final _narrativeEngine = LocalNarrativeEngine();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    AppRepositories.dataRevision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    AppRepositories.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final uid = AuthService.instance.currentUser?.id;
      final results = await Future.wait([
        if (uid != null) repos.getJugador(uid) else Future<Jugador?>.value(null),
        repos.getMisConvocatoriasComoJugador(),
        repos.getMisPartidosJugados(limit: 80),
        repos.getMisResumenInvitaciones(),
      ]);
      final perfil = results[0] as Jugador?;
      final convocatorias = results[1] as List<MiConvocatoria>;
      final partidos = results[2] as List<DetallePartido>;
      final invitaciones = results[3] as MisInvitacionesResumen;

      final stats = buildMisEstadisticasDesdeHome(
        uid: uid,
        perfil: perfil,
        partidosJugados: partidos,
        convocatorias: convocatorias,
        confirmacionesHistoricas: invitaciones.confirmadas,
      );

      final pride = buildPlayerProfilePride(
        stats: stats,
        invitaciones: invitaciones,
        partidos: partidos,
        convocatorias: convocatorias,
      );
      final badges = buildPlayerBehaviorBadges(
        partidos: partidos,
        convocatorias: convocatorias,
        invitaciones: invitaciones,
        accountCreatedAt: perfil?.createdAt,
      );
      final companeros = _countCompaneros(partidos, uid);
      final activities = _buildActivityPoints(partidos);
      final fechas = activities.map((a) => a.date).toList();
      final mensual = pride.actividadMensual;
      final mesActual = mensual.isNotEmpty ? mensual.last : 0;
      final mesAnterior =
          mensual.length >= 2 ? mensual[mensual.length - 2] : 0;

      bool badgeUnlocked(PlayerBehaviorBadge id) =>
          badges.any((b) => b.id == id && b.unlocked);

      final storyInput = StoryEngineInput(
        encuentrosTotal: pride.encuentrosTotal,
        rachaSemanas: pride.rachaSemanasConsecutivas,
        porcentajeAsistencia: pride.porcentajeAsistencia,
        deportesCount: pride.deportesJugados.length,
        companeros: companeros,
        actividadMesActual: mesActual,
        actividadMesAnterior: mesAnterior,
        badgeAlwaysPresent:
            badgeUnlocked(PlayerBehaviorBadge.alwaysPresent),
        badgeExplorer: badgeUnlocked(PlayerBehaviorBadge.explorer),
        badgeEarlyBird: badgeUnlocked(PlayerBehaviorBadge.earlyBird),
        badgeNightOwl: badgeUnlocked(PlayerBehaviorBadge.nightOwl),
        primeraActividad: fechas.isEmpty ? null : fechas.first,
        fechasActividad: fechas,
      );

      final playerId = uid ?? perfil?.keyId ?? 'local';
      final log = await _narrativeEngine.loadSightingLog(playerId);
      final story = await _narrativeEngine.fetchStoryOfTheDay(
        playerId: playerId,
        input: storyInput,
      );

      // Silencio fértil: bienvenida suave sin hueco vacío.
      final dailyStory = story ??
          LocalNarrativeEngine.enrichCandidate(
            const StoryCard(
              id: 'identidad_welcome',
              category: StoryCategory.identidad,
              priority: 10,
              title: 'playerTodayWelcomeTitle',
              subtitle: 'playerTodayWelcomeBody',
              emoji: '✨',
            ),
          );

      final today = NarrativeSightingLog.calendarDay(DateTime.now());
      final alreadyShownToday =
          log.hasStickyFor(today) && log.stickyStoryId == dailyStory.id;

      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _pride = pride;
        _badges = badges;
        _activities = activities;
        _companeros = companeros;
        _todayStory = dailyStory;
        _loading = false;
        _error = null;
      });

      // Mutación del log solo cuando la historia se expone por primera vez hoy.
      if (!alreadyShownToday && story != null) {
        await _narrativeEngine.markStoryAsSeen(
          playerId: playerId,
          storyId: dailyStory.id,
          family: dailyStory.family,
          intensity: dailyStory.intensity,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.userError(e);
      });
    }
  }

  static int _countCompaneros(List<DetallePartido> partidos, String? uid) {
    final ids = <String>{};
    for (final p in partidos) {
      final organizer = p.organizadorId?.trim();
      if (organizer == null || organizer.isEmpty) continue;
      if (uid != null && organizer == uid) continue;
      ids.add(organizer);
    }
    return ids.length;
  }

  static List<_ProfileActivityPoint> _buildActivityPoints(
    List<DetallePartido> partidos,
  ) {
    final list = <_ProfileActivityPoint>[];
    for (final p in partidos) {
      final fecha = p.fechaPartido;
      if (!p.asistio || fecha == null) continue;
      list.add(
        _ProfileActivityPoint(
          date: fecha,
          sport: p.sportType ?? SportType.other,
        ),
      );
    }
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final pride = _pride;

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(title: Text(l10n.tr('playerProfileTitle'))),
      body: _loading && _perfil == null && _error == null
          ? ListView(
              padding: NavShellScope.listPadding(context),
              children: const [
                ShimmerLoading(
                  height: 220,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                SizedBox(height: 16),
                ShimmerLoading(
                  height: 160,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ],
            )
          : _error != null
              ? FriendlyErrorPanel(message: _error!, onRetry: () => _load())
              : RefreshIndicator(
                  color: palette.primary,
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: NavShellScope.listPadding(context),
                    children: [
                      if (pride != null)
                        _SportsIdentityHero(
                          perfil: _perfil,
                          pride: pride,
                        ),
                      if (pride != null) ...[
                        const SizedBox(height: 28),
                        if (_todayStory != null)
                          StoryCardView(
                            card: _todayStory!,
                            sectionLabel: l10n.tr('playerTodayTitle'),
                          ),
                        const SizedBox(height: 14),
                        _PrideMetricsStrip(
                          pride: pride,
                          companions: _companeros,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          l10n.tr('playerProfileStreakTitle'),
                          style: MatchPayTokens.titleSmallStyle(),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.tr('playerProfileChartPastWeeks'),
                          style: MatchPayTokens.bodySmallStyle(
                            color: MatchPayTokens.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ActivityProgressChart(
                          activities: _activities,
                          tint: palette.primary,
                        ),
                      ],
                      const SizedBox(height: 28),
                      BadgeShowcaseBoard(badges: _badges),
                    ],
                  ),
                ),
    );
  }
}

class _SportsIdentityHero extends StatelessWidget {
  final Jugador? perfil;
  final PlayerProfilePrideData pride;

  const _SportsIdentityHero({
    required this.perfil,
    required this.pride,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final archetype = pride.archetype;
    final nombre = perfil?.nombre.trim().isNotEmpty == true
        ? perfil!.nombre.trim()
        : l10n.tr('playerDefaultName');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.primaryDark,
            palette.primary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        boxShadow: MatchPayTokens.shadowCard(elevated: true),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              JugadorAvatar(
                nombre: nombre,
                fotoUrl: perfil?.fotoUrl,
                fotoPath: perfil?.fotoPath,
                size: 64,
                borderRadius: 32,
                showBorder: true,
                borderColor: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: MatchPayTokens.titleMediumStyle(
                        color: Colors.white,
                      ).copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.tr(archetypeTitleKey(archetype)),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l10n.tr(archetypeHeadlineKey(archetype)),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.tr(archetypeBodyKey(archetype)),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Métricas compactas en una sola fila scrolleable (sin wraps/overflow).
class _PrideMetricsStrip extends StatelessWidget {
  final PlayerProfilePrideData pride;
  final int companions;

  const _PrideMetricsStrip({
    required this.pride,
    required this.companions,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sports = pride.deportesJugados.take(3).toList();

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _MetricChip(
            value: '${pride.encuentrosTotal}',
            label: l10n.tr('playerProfileMetricEncounters'),
          ),
          const SizedBox(width: 8),
          _MetricChip(
            value: '${pride.porcentajeAsistencia}%',
            label: l10n.tr('playerProfileMetricAttendance'),
          ),
          const SizedBox(width: 8),
          _MetricChip(
            value: sports.isEmpty ? '—' : '${sports.length}',
            label: l10n.tr('playerProfileMetricSports'),
            trailing: sports.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final sport in sports) ...[
                        const SizedBox(width: 3),
                        SportIcon(
                          sport: sport,
                          size: 12,
                          color: MatchPayTokens.inkSecondary,
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          _MetricChip(
            value: companions > 0 ? '$companions' : '—',
            label: l10n.tr('playerProfileMetricCompanions'),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String value;
  final String label;
  final Widget? trailing;

  const _MetricChip({
    required this.value,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: MatchPayTokens.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MatchPayTokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: MatchPayTokens.titleSmallStyle().copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkMuted,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ProfileActivityPoint {
  final DateTime date;
  final SportType sport;

  const _ProfileActivityPoint({
    required this.date,
    required this.sport,
  });
}

class _DayActivityMilestone {
  final DateTime day;
  final List<_ProfileActivityPoint> sessions;
  /// Valor actual del eje Y (placeholder de Momentum; ver docs del chart).
  final double momentum;

  const _DayActivityMilestone({
    required this.day,
    required this.sessions,
    required this.momentum,
  });
}

/// Gráfica "Tu ritmo" — timeline de actividad del perfil (período ~3 meses).
///
/// ## Eje Y — Índice continuo de actividad ("Momentum") [definición conceptual]
///
/// El eje Y representa un **índice continuo de actividad** llamado Momentum.
/// No es un conteo independiente por punto ni una métrica de rendimiento.
///
/// Comportamiento objetivo (evolución continua y orgánica):
/// - Cada encuentro **aumenta** el nivel actual de Momentum.
/// - Cada día sin encuentros provoca un **decaimiento progresivo**.
/// - El valor es **acumulativo** a lo largo del tiempo (estado continuo),
///   no un valor aislado recalculado solo con el día tocado.
/// - El gráfico debe leerse como una **evolución continua y orgánica**
///   del ritmo de juego.
///
/// El eje Y **NUNCA** representa:
/// - rendimiento deportivo (nivel, ranking, calidad de juego), ni
/// - cantidad bruta de encuentros como eje independiente.
///
/// Nota de implementación: el cálculo activo de `momentum` puede sustituirse
/// más adelante por el índice acumulativo completo sin cambiar X, selección,
/// tooltips, colores ni navegación.
class _ActivityProgressChart extends StatefulWidget {
  final List<_ProfileActivityPoint> activities;
  final Color tint;

  const _ActivityProgressChart({
    required this.activities,
    required this.tint,
  });

  @override
  State<_ActivityProgressChart> createState() => _ActivityProgressChartState();
}

class _ActivityProgressChartState extends State<_ActivityProgressChart> {
  /// Ventana analizada: ~3 meses (84 días). No cambiar sin acuerdo de producto.
  static const int _lookbackDays = 84;
  /// Vida media del decaimiento: gaps largos bajan la onda con suavidad.
  static const double _momentumHalfLifeDays = 6.0;
  /// Ritmo “ideal” (días); gaps más cortos refuerzan, más largos frenan.
  static const double _idealGapDays = 4.0;
  static const double _xEdgePadding = 0.65;
  int? _selectedIndex;
  int _sessionPage = 0;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _formatShortDate(DateTime day) {
    final dd = day.day.toString().padLeft(2, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final yy = (day.year % 100).toString().padLeft(2, '0');
    return '$dd / $mm / $yy';
  }

  /// Cálculo actual del valor Y (Momentum).
  ///
  /// Preparado para sustituirse por un índice acumulativo día-a-día donde:
  /// encuentros suben el nivel y los días sin actividad lo hacen decaer,
  /// sin alterar el eje X ni la selección de puntos.
  static double _momentumForDay({
    required DateTime day,
    required List<_ProfileActivityPoint> all,
    required DateTime? previousActivityDay,
    required int sessionsThisDay,
  }) {
    // Eco de actividad pasada (incluye el día): cercanía → más inercia.
    var echo = 0.0;
    for (final a in all) {
      final other = _dateOnly(a.date);
      final daysBefore = day.difference(other).inDays;
      if (daysBefore < 0) continue;
      echo += math.exp(-daysBefore / _momentumHalfLifeDays);
    }

    // Impulso extra por varios encuentros el mismo día.
    final volumeBoost = math.max(0, sessionsThisDay - 1) * 0.55;

    // Refuerzo de racha vs. decaimiento por gap respecto al ritmo ideal.
    var cadence = 1.0;
    if (previousActivityDay != null) {
      final gap = day.difference(previousActivityDay).inDays.toDouble();
      final delta = (_idealGapDays - gap) / _idealGapDays;
      cadence = (1.0 + delta * 0.42).clamp(0.55, 1.45);
    }

    return (echo + volumeBoost) * cadence;
  }

  List<_DayActivityMilestone> _buildMilestones() {
    final today = _dateOnly(DateTime.now());
    final earliest = today.subtract(const Duration(days: _lookbackDays - 1));

    final inRange = widget.activities.where((a) {
      final day = _dateOnly(a.date);
      return !day.isBefore(earliest) && !day.isAfter(today);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final byDay = <DateTime, List<_ProfileActivityPoint>>{};
    for (final a in inRange) {
      final day = _dateOnly(a.date);
      (byDay[day] ??= []).add(a);
    }

    final days = byDay.keys.toList()..sort();
    return [
      for (var i = 0; i < days.length; i++)
        _DayActivityMilestone(
          day: days[i],
          sessions: byDay[days[i]]!,
          momentum: _momentumForDay(
            day: days[i],
            all: inRange,
            previousActivityDay: i > 0 ? days[i - 1] : null,
            sessionsThisDay: byDay[days[i]]!.length,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final milestones = _buildMilestones();

    if (milestones.isEmpty) {
      return MatchPaySurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Text(
          l10n.tr('playerProfileChartNoActivity'),
          style: MatchPayTokens.bodySmallStyle(
            color: MatchPayTokens.inkSecondary,
          ),
        ),
      );
    }

    final selectedIndex = (_selectedIndex == null ||
            _selectedIndex! < 0 ||
            _selectedIndex! >= milestones.length)
        ? milestones.length - 1
        : _selectedIndex!;
    final selected = milestones[selectedIndex];
    final sessions = selected.sessions;
    final sessionPage =
        sessions.isEmpty ? 0 : _sessionPage.clamp(0, sessions.length - 1);
    final activeSession = sessions.isEmpty ? null : sessions[sessionPage];
    final activeSport = activeSession?.sport;
    final sportLabel = activeSport == null
        ? l10n.tr('playerProfileChartNoActivity')
        : activeSport.labelForLang(lang);
    final dateLabel = activeSession != null
        ? _formatShortDate(_dateOnly(activeSession.date))
        : _formatShortDate(selected.day);

    final intensities = milestones.map((m) => m.momentum).toList();
    final maxIntensity =
        intensities.fold<double>(1, (a, b) => a > b ? a : b);
    final minIntensity =
        intensities.fold<double>(maxIntensity, (a, b) => a < b ? a : b);
    // Aire arriba; si todos son casi iguales, ampliar escala para no “aplanar”.
    final span = (maxIntensity - minIntensity).abs();
    final chartMaxY = span < 0.35
        ? (maxIntensity * 1.8).clamp(2.5, 16.0)
        : (maxIntensity * 1.35).clamp(2.0, 16.0);
    final yInterval = (chartMaxY / 3).clamp(0.5, 4).toDouble();

    final spots = <FlSpot>[
      for (var i = 0; i < milestones.length; i++)
        FlSpot(i.toDouble(), milestones[i].momentum),
    ];

    final monthLabelAt = <int, String>{};
    for (var i = 0; i < milestones.length; i++) {
      final day = milestones[i].day;
      final shown = monthLabelAt.entries.any((e) {
        final other = milestones[e.key].day;
        return other.year == day.year && other.month == day.month;
      });
      if (!shown) monthLabelAt[i] = formatMesAbrev(day);
    }

    final tint = widget.tint;
    final lastX = (milestones.length - 1).toDouble();
    final minX = -_xEdgePadding;
    final maxX = lastX + _xEdgePadding;

    return MatchPaySurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActivityDetailBadge(
            tint: tint,
            sport: activeSport,
            sportLabel: sportLabel,
            dateLabel: dateLabel,
            sportPage: sessionPage,
            sportCount: sessions.length,
            onCycleSport: sessions.length > 1
                ? () {
                    setState(() {
                      _sessionPage = (sessionPage + 1) % sessions.length;
                    });
                  }
                : null,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 176,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: 0,
                maxY: chartMaxY,
                clipData: const FlClipData.all(),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: selectedIndex.toDouble(),
                      color: MatchPayTokens.ink.withValues(alpha: 0.75),
                      strokeWidth: 1.1,
                    ),
                  ],
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: MatchPayTokens.borderSubtle.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: yInterval,
                      getTitlesWidget: (value, _) {
                        if (value <= 0) return const SizedBox.shrink();
                        if (value % 1 > 0.05 && value % 1 < 0.95) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          value.round().toString(),
                          style: MatchPayTokens.bodySmallStyle(
                            color: MatchPayTokens.inkMuted,
                          ).copyWith(fontSize: 10),
                          textAlign: TextAlign.right,
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final i = value.round();
                        if ((value - i).abs() > 0.01) {
                          return const SizedBox.shrink();
                        }
                        if (i < 0 || i >= milestones.length) {
                          return const SizedBox.shrink();
                        }
                        final label = monthLabelAt[i];
                        if (label == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            label,
                            style: MatchPayTokens.bodySmallStyle(
                              color: MatchPayTokens.inkMuted,
                            ).copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  getTouchLineStart: (_, _) => 0,
                  getTouchLineEnd: (_, _) => chartMaxY,
                  getTouchedSpotIndicator: (barData, spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        FlLine(
                          color: MatchPayTokens.ink.withValues(alpha: 0.55),
                          strokeWidth: 1,
                        ),
                        FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, idx) {
                            return FlDotCirclePainter(
                              radius: 5,
                              color: Colors.white,
                              strokeWidth: 2.5,
                              strokeColor: tint,
                            );
                          },
                        ),
                      );
                    }).toList();
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) =>
                        List<LineTooltipItem?>.filled(
                      touchedSpots.length,
                      null,
                    ),
                  ),
                  touchCallback: (event, response) {
                    if (!mounted) return;
                    if (!event.isInterestedForInteractions) return;
                    final spotsTouched = response?.lineBarSpots;
                    if (spotsTouched == null || spotsTouched.isEmpty) return;
                    final next = spotsTouched.first.x
                        .round()
                        .clamp(0, milestones.length - 1);
                    setState(() {
                      if (next != selectedIndex) {
                        _selectedIndex = next;
                        _sessionPage = 0;
                      }
                    });
                  },
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    preventCurveOverShooting: true,
                    isStrokeCapRound: true,
                    barWidth: 2.6,
                    color: tint,
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          tint.withValues(alpha: 0.38),
                          tint.withValues(alpha: 0.12),
                          tint.withValues(alpha: 0.02),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        final i = spot.x.round();
                        final selected = i == selectedIndex;
                        return FlDotCirclePainter(
                          radius: selected ? 4.2 : 2.6,
                          color: Colors.white,
                          strokeWidth: selected ? 2.4 : 1.7,
                          strokeColor: tint,
                        );
                      },
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

/// Cabecera flotante de actividad: deporte + fecha unificados (sin labels clínicos).
class _ActivityDetailBadge extends StatelessWidget {
  final Color tint;
  final SportType? sport;
  final String sportLabel;
  final String dateLabel;
  final int sportPage;
  final int sportCount;
  final VoidCallback? onCycleSport;

  const _ActivityDetailBadge({
    required this.tint,
    required this.sport,
    required this.sportLabel,
    required this.dateLabel,
    required this.sportPage,
    required this.sportCount,
    this.onCycleSport,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: sport == null
              ? Icon(Icons.sports, size: 20, color: tint)
              : SportIcon(sport: sport!, size: 22, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sportLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MatchPayTokens.titleSmallStyle().copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dateLabel,
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkSecondary,
                ).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        if (sportCount > 1) ...[
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${sportPage + 1}/$sportCount',
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkMuted,
                    ).copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: tint.withValues(alpha: 0.9),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(sportCount, (i) {
                  final active = i == sportPage;
                  return Container(
                    width: active ? 11 : 5,
                    height: 5,
                    margin: const EdgeInsets.only(left: 3),
                    decoration: BoxDecoration(
                      color: active
                          ? tint
                          : MatchPayTokens.inkMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
            ],
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCycleSport,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                tint.withValues(alpha: 0.12),
                tint.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tint.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}
