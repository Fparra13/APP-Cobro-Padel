import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/supabase_helpers.dart';
import '../models/convocatoria_jugador.dart';
import '../models/partido.dart';
import '../repositories/partido_repository.dart';
import '../repositories/ranking_repository.dart';
import '../services/pdf_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/app_navigation.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';
import '../widgets/partido_detalle_sheet.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/sport_icon.dart';

class HistorialPartidosScreen extends StatefulWidget {
  const HistorialPartidosScreen({super.key});

  @override
  State<HistorialPartidosScreen> createState() =>
      _HistorialPartidosScreenState();
}

class _HistorialPartidosScreenState extends State<HistorialPartidosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _pdfService = PdfService();

  List<PartidoCompleto> _partidos = [];
  List<ConvocatoriaCompleta> _convocatorias = [];
  List<RankingJugador> _ranking = [];
  bool _loading = true;
  bool _rankingLoading = false;
  bool _rankingLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onTabChanged() {
    if (_tabs.index == 1 && !_rankingLoaded && !_rankingLoading) {
      _loadRanking();
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadRanking() async {
    if (_rankingLoading) return;
    setState(() => _rankingLoading = true);
    try {
      final ranking = await context.repos.getRanking();
      if (mounted) {
        setState(() {
          _ranking = ranking;
          _rankingLoaded = true;
          _rankingLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rankingLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SupabaseHelpers.describeError(e, operacion: 'Ranking'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repos = context.repos;
      final results = await Future.wait([
        repos.getPartidosJugados(),
        repos.getConvocatoriasActivas(),
      ]);
      final list = results[0] as List<Partido>;
      final convocatorias = results[1] as List<ConvocatoriaCompleta>;
      final ids = list.map((p) => p.id).whereType<int>().toList();
      final completos = await repos.getPartidosCompletosListaResumen(ids);
      if (mounted) {
        setState(() {
          _partidos = completos;
          _convocatorias = convocatorias;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = SupabaseHelpers.describeError(
            e,
            operacion: 'Historial de partidos',
          );
        });
      }
    }
  }

  Widget _buildErrorState() {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: MatchPayTokens.inkMuted,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.tr('historyLoadFailed'),
              style: MatchPayTokens.titleMediumStyle(),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? l10n.tr('unknownError'),
              textAlign: TextAlign.center,
              style: MatchPayTokens.bodySmallStyle(),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(
        title: Text(l10n.tr('historyScreenTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 26),
            tooltip: l10n.tr('refreshTooltip'),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
          labelStyle: MatchPayTokens.titleSmallStyle(color: Colors.white)
              .copyWith(fontSize: 13),
          tabs: [
            Tab(
              height: 52,
              icon: SportIcon(size: 26),
              text: l10n.tr('tabMatches'),
            ),
            Tab(
              height: 52,
              icon: const Icon(Icons.emoji_events_rounded, size: 26),
              text: l10n.tr('tabRanking'),
            ),
          ],
        ),
      ),
      body: _loading
          ? const _HistorialShimmer()
          : _error != null && _partidos.isEmpty && _convocatorias.isEmpty
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildHistorial(),
                    _buildRanking(),
                  ],
                ),
    );
  }

  Widget _buildHistorial() {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    if (_partidos.isEmpty && _convocatorias.isEmpty) {
      return _EmptyTab(
        iconWidget: SportIcon(size: 48, color: MatchPayTokens.inkMuted),
        titulo: l10n.tr('historyEmptyMatchesTitle'),
        subtitulo: l10n.tr('historyEmptyMatchesSubtitle'),
        accent: MatchPayTokens.accentSuccess,
      );
    }

    final pendientesTotal = _partidos.fold<int>(
      0,
      (s, p) =>
          s + p.detalles.where((d) => d.asistio && !d.pagado).length,
    );
    final hayConvocatoriasVencidas =
        _convocatorias.any((c) => c.partido.convocatoriaFechaPasada);

    return RefreshIndicator(
      color: palette.primary,
      onRefresh: _load,
      child: ListView(
        padding: NavShellScope.listPadding(context, left: 16, top: 16, right: 16),
        children: [
          if (_convocatorias.isNotEmpty) ...[
            MatchPaySectionHeader(
              title: l10n.tr('homeActiveConvocatorias'),
              count: _convocatorias.length,
              accent: hayConvocatoriasVencidas,
            ),
            const SizedBox(height: 10),
            _buildStatsHeader(
              icon: hayConvocatoriasVencidas
                  ? Icons.event_busy_rounded
                  : Icons.campaign_rounded,
              titulo: l10n.tr(
                'historyActiveConvocatoriasTitle',
                params: {'count': '${_convocatorias.length}'},
              ),
              subtitulo: l10n.tr(
                hayConvocatoriasVencidas
                    ? 'historyPastConvocatoriasSubtitle'
                    : 'historyActiveConvocatoriasSubtitle',
              ),
              accent: hayConvocatoriasVencidas
                  ? MatchPayTokens.accentUrgent
                  : MatchPayTokens.accentCredit,
            ),
            const SizedBox(height: 10),
            ..._convocatorias.map(
              (c) => _ConvocatoriaCard(
                convocatoria: c,
                onTap: () async {
                  await abrirOrganizarPartido(context, partidoId: c.partido.id);
                  _load();
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_partidos.isNotEmpty) ...[
            MatchPaySectionHeader(
              title: l10n.tr('tabMatches'),
              count: _partidos.length,
            ),
            const SizedBox(height: 10),
            _buildStatsHeader(
              icon: Icons.history_rounded,
              titulo: l10n.tr(
                'historyMatchesCountTitle',
                params: {'count': '${_partidos.length}'},
              ),
              subtitulo: pendientesTotal > 0
                  ? l10n.tr(
                      'historyPendingChargesSubtitle',
                      params: {'count': '$pendientesTotal'},
                    )
                  : l10n.tr('historyAllChargesPaid'),
              accent: pendientesTotal > 0
                  ? MatchPayTokens.accentUrgent
                  : MatchPayTokens.accentSuccess,
            ),
            const SizedBox(height: 10),
            AyudaTip(texto: l10n.tr('historyTapMatchHelp')),
            const SizedBox(height: 10),
            ..._partidos.map(
              (pc) => _PartidoCard(
                completo: pc,
                repos: context.repos,
                pdfService: _pdfService,
                onChanged: _load,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRanking() {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    if (!_rankingLoaded && !_rankingLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRanking());
    }
    if (_rankingLoading || (!_rankingLoaded && _ranking.isEmpty)) {
      return const _HistorialShimmer(showTabs: false);
    }
    if (_ranking.isEmpty) {
      return _EmptyTab(
        icon: Icons.emoji_events_rounded,
        titulo: l10n.tr('rankingEmptyTitle'),
        subtitulo: l10n.tr('rankingEmptySubtitle'),
        accent: MatchPayTokens.accentUrgent,
      );
    }

    final repos = context.repos;
    final mejores = repos.mejoresPagadores(_ranking).take(5).toList();
    final peores = repos.peoresPagadores(_ranking).take(5).toList();

    return RefreshIndicator(
      color: palette.primary,
      onRefresh: () async {
        _rankingLoaded = false;
        await _loadRanking();
      },
      child: ListView(
        padding: NavShellScope.listPadding(context, left: 16, top: 16, right: 16),
        children: [
          AyudaTip(texto: l10n.tr('rankingHelpTip')),
          const SizedBox(height: 16),
          if (mejores.isNotEmpty)
            _RankingSection(
              icono: Icons.military_tech_rounded,
              titulo: l10n.tr('rankingBestPayersTitle'),
              emoji: '🏆',
              subtitulo: l10n.tr('rankingBestPayersSubtitle'),
              accent: MatchPayTokens.accentSuccess,
              items: mejores,
              esBueno: true,
            )
          else
            _RankingEmptyHint(
              emoji: '🏆',
              titulo: l10n.tr('rankingNoBestYetTitle'),
              subtitulo: l10n.tr('rankingNoBestYetSubtitle'),
            ),
          const SizedBox(height: 16),
          if (peores.isNotEmpty)
            _RankingSection(
              icono: Icons.hourglass_bottom_rounded,
              titulo: l10n.tr('rankingWorstPayersTitle'),
              emoji: '🐢',
              subtitulo: l10n.tr('rankingWorstPayersSubtitle'),
              accent: MatchPayTokens.accentUrgent,
              items: peores,
              esBueno: false,
            )
          else
            _RankingEmptyHint(
              emoji: '✅',
              titulo: l10n.tr('rankingNoWorstTitle'),
              subtitulo: l10n.tr('rankingNoWorstSubtitle'),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color accent,
  }) {
    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: MatchPayTokens.titleSmallStyle()),
                Text(subtitulo, style: MatchPayTokens.bodySmallStyle()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String titulo;
  final String subtitulo;
  final Color accent;

  const _EmptyTab({
    this.icon,
    this.iconWidget,
    required this.titulo,
    required this.subtitulo,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: iconWidget ??
                  Icon(icon!, size: 64, color: accent),
            ),
            const SizedBox(height: 20),
            Text(titulo, style: MatchPayTokens.titleMediumStyle()),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: MatchPayTokens.bodySmallStyle(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConvocatoriaCard extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final VoidCallback onTap;

  const _ConvocatoriaCard({
    required this.convocatoria,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final fecha = formatFecha(p.fecha);
    final hora = formatHora(p.fecha);
    final fechaPasada = p.convocatoriaFechaPasada;
    final accent = fechaPasada
        ? MatchPayTokens.accentUrgent
        : convocatoria.partido.esConfirmado
            ? MatchPayTokens.accentSuccess
            : MatchPayTokens.accentCredit;
    final iconData = fechaPasada
        ? Icons.event_busy_rounded
        : convocatoria.partido.esConfirmado
            ? Icons.check_circle_rounded
            : Icons.campaign_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MatchPaySurfaceCard(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
              ),
              child: Icon(iconData, color: accent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SportChargeChip(sport: p.sportType),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          convocatoria.partido.esConfirmado
                              ? l10n.tr(
                                  'convocatoriaConfirmedLine',
                                  params: {'date': fecha, 'time': hora},
                                )
                              : '$fecha · $hora',
                          style: MatchPayTokens.titleSmallStyle(),
                        ),
                      ),
                      if (fechaPasada)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MatchPayTokens.accentUrgentBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: MatchPayTokens.accentUrgentBorder
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            l10n.tr('convocatoriaPastDateBadge'),
                            style: MatchPayTokens.sectionLabelStyle(
                              color: MatchPayTokens.accentUrgent,
                            ).copyWith(fontSize: 10, letterSpacing: 0),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    p.recinto?.isNotEmpty ?? false
                        ? p.recinto!
                        : l10n.tr('noVenue'),
                    style: MatchPayTokens.bodySmallStyle(),
                  ),
                  Text(
                    l10n.tr(
                      'convocatoriaConfirmedCount',
                      params: {
                        'confirmed': '${convocatoria.confirmados}',
                        'max': '${p.cuposMax}',
                        'invited': '${convocatoria.invitados}',
                      },
                    ),
                    style: MatchPayTokens.titleSmallStyle(color: accent)
                        .copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: accent),
          ],
        ),
      ),
    );
  }
}

class _PartidoCard extends StatelessWidget {
  final PartidoCompleto completo;
  final AppRepositories repos;
  final PdfService pdfService;
  final VoidCallback onChanged;

  const _PartidoCard({
    required this.completo,
    required this.repos,
    required this.pdfService,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fecha = formatFecha(completo.partido.fecha);
    final hora = formatHora(completo.partido.fecha);
    final asistentes = completo.detalles.where((d) => d.asistio).length;
    final pendientes =
        completo.detalles.where((d) => d.asistio && !d.pagado).length;
    final todosPagaron = pendientes == 0;
    final estadoColor = todosPagaron
        ? MatchPayTokens.accentSuccess
        : MatchPayTokens.accentUrgent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MatchPaySurfaceCard(
        padding: const EdgeInsets.all(14),
        urgent: !todosPagaron,
        onTap: () => PartidoDetalleSheet.show(
          context,
          completo: completo,
          repos: repos,
          pdfService: pdfService,
          onEditar: () {
            Navigator.pop(context);
            Navigator.pushNamed(
              context,
              '/editar-partido',
              arguments: completo.partido.id,
            ).then((_) => onChanged());
          },
          onEliminar: () async {
            final fecha = formatFecha(completo.partido.fecha);
            final recinto = completo.partido.recinto?.trim();
            final ok = await confirmarEliminarPartido(
              context,
              titulo: l10n.tr('deleteMatchTitle'),
              mensaje: recinto != null && recinto.isNotEmpty
                  ? l10n.tr(
                      'deleteMatchMessageWithVenue',
                      params: {'date': fecha, 'venue': recinto},
                    )
                  : l10n.tr(
                      'deleteMatchMessage',
                      params: {'date': fecha},
                    ),
            );
            if (!ok || !context.mounted) return;
            await repos.eliminarPartido(completo.partido.id!);
            if (!context.mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.tr('matchDeleted'))),
            );
            onChanged();
          },
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: estadoColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
                border: Border.all(color: estadoColor.withValues(alpha: 0.35)),
              ),
              child: Icon(
                todosPagaron
                    ? Icons.check_circle_rounded
                    : Icons.pending_actions_rounded,
                color: estadoColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SportChargeChip(sport: completo.partido.sportType),
                  const SizedBox(height: 6),
                  Text(fecha, style: MatchPayTokens.titleSmallStyle()),
                  if (completo.partido.recinto != null &&
                      completo.partido.recinto!.trim().isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: MatchPayTokens.accentSuccess,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            completo.partido.recinto!.trim(),
                            style: MatchPayTokens.bodySmallStyle(
                              color: MatchPayTokens.accentSuccess,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: MatchPayTokens.inkMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(hora, style: MatchPayTokens.bodySmallStyle()),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _InfoChip(
                        icon: Icons.people_alt_rounded,
                        label: l10n.tr(
                          'matchPlayersCount',
                          params: {'count': '$asistentes'},
                        ),
                        color: MatchPayTokens.accentCredit,
                      ),
                      _InfoChip(
                        icon: todosPagaron
                            ? Icons.verified_rounded
                            : Icons.warning_amber_rounded,
                        label: todosPagaron
                            ? l10n.tr('matchAllPaid')
                            : l10n.tr(
                                'matchUnpaidCount',
                                params: {'count': '$pendientes'},
                              ),
                        color: estadoColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: MatchPayTokens.inkMuted,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: MatchPayTokens.sectionLabelStyle(color: color).copyWith(
              letterSpacing: 0,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingEmptyHint extends StatelessWidget {
  final String emoji;
  final String titulo;
  final String subtitulo;

  const _RankingEmptyHint({
    required this.emoji,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return MatchPaySurfaceCard(
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: MatchPayTokens.titleSmallStyle()),
                const SizedBox(height: 4),
                Text(subtitulo, style: MatchPayTokens.bodySmallStyle()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingSection extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String emoji;
  final String subtitulo;
  final Color accent;
  final List<RankingJugador> items;
  final bool esBueno;

  const _RankingSection({
    required this.icono,
    required this.titulo,
    required this.emoji,
    required this.subtitulo,
    required this.accent,
    required this.items,
    required this.esBueno,
  });

  static const _medallas = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];
  static const _medallaColors = [
    Color(0xFFFFD700),
    Color(0xFFC0C0C0),
    Color(0xFFCD7F32),
    Color(0xFF78909C),
    Color(0xFF78909C),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MatchPaySurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(MatchPayTokens.radiusChip),
                ),
                child: Icon(icono, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$emoji $titulo',
                      style: MatchPayTokens.titleSmallStyle(color: accent),
                    ),
                    Text(subtitulo, style: MatchPayTokens.bodySmallStyle()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MatchPayTokens.surfaceInset,
                borderRadius:
                    BorderRadius.circular(MatchPayTokens.radiusChip),
                border: Border.all(color: MatchPayTokens.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _medallaColors[i].withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _medallaColors[i].withValues(alpha: 0.6),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _medallas[i],
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.nombre, style: MatchPayTokens.titleSmallStyle()),
                        Row(
                          children: [
                            Icon(
                              esBueno
                                  ? Icons.thumb_up_alt_rounded
                                  : Icons.schedule_rounded,
                              size: 14,
                              color: accent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                esBueno
                                    ? l10n.tr(
                                        'rankingBestStat',
                                        params: {
                                          'onTime': '${r.pagosAlDia}',
                                          'percent': r.porcentajePagoAlDia
                                              .toStringAsFixed(0),
                                        },
                                      )
                                    : l10n.tr(
                                        'rankingWorstStat',
                                        params: {
                                          'unpaid': '${r.partidosImpagos}',
                                          'amount':
                                              formatMoney(r.saldoActual),
                                        },
                                      ),
                                style: MatchPayTokens.bodySmallStyle(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HistorialShimmer extends StatelessWidget {
  final bool showTabs;

  const _HistorialShimmer({this.showTabs = true});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: NavShellScope.listPadding(context, left: 16, top: 16, right: 16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (showTabs) ...[
          ShimmerLoading(
            height: 14,
            width: 140,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 10),
        ],
        ShimmerLoading(
          height: 72,
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        ),
        const SizedBox(height: 16),
        ShimmerLoading(
          height: 56,
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ShimmerLoading(
              height: 110,
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
            ),
          ),
        ),
      ],
    );
  }
}
