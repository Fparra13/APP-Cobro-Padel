import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/supabase_helpers.dart';
import '../models/convocatoria_jugador.dart';
import '../models/partido.dart';
import '../repositories/partido_repository.dart';
import '../repositories/ranking_repository.dart';
import '../services/pdf_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/app_navigation.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';
import '../widgets/partido_detalle_sheet.dart';
import '../utils/nav_shell_layout.dart';
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
            Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              l10n.tr('historyLoadFailed'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? l10n.tr('unknownError'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
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
      appBar: AppBar(
        title: Text('📋 ${l10n.tr('historyScreenTitle')}'),
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
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
          ? const Center(child: CircularProgressIndicator())
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
    if (_partidos.isEmpty && _convocatorias.isEmpty) {
      return _EmptyTab(
        iconWidget: SportIcon(size: 48, color: Colors.grey.shade400),
        titulo: l10n.tr('historyEmptyMatchesTitle'),
        subtitulo: l10n.tr('historyEmptyMatchesSubtitle'),
        color: Colors.green,
      );
    }

    final pendientesTotal = _partidos.fold<int>(
      0,
      (s, p) =>
          s + p.detalles.where((d) => d.asistio && !d.pagado).length,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: NavShellScope.listPadding(context, bottom: 0),
        children: [
          if (_convocatorias.isNotEmpty) ...[
            _buildStatsHeader(
              icon: Icons.campaign,
              titulo: l10n.tr(
                'historyActiveConvocatoriasTitle',
                params: {'count': '${_convocatorias.length}'},
              ),
              subtitulo: l10n.tr('historyActiveConvocatoriasSubtitle'),
              color: Colors.blue,
            ),
            ..._convocatorias.map(
              (c) => _ConvocatoriaCard(
                convocatoria: c,
                onTap: () async {
                  await abrirOrganizarPartido(context, partidoId: c.partido.id);
                  _load();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_partidos.isNotEmpty) ...[
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
              color: Colors.green,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: AyudaTip(texto: l10n.tr('historyTapMatchHelp')),
            ),
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
    if (!_rankingLoaded && !_rankingLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRanking());
    }
    if (_rankingLoading || (!_rankingLoaded && _ranking.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ranking.isEmpty) {
      return _EmptyTab(
        icon: Icons.emoji_events_rounded,
        titulo: l10n.tr('rankingEmptyTitle'),
        subtitulo: l10n.tr('rankingEmptySubtitle'),
        color: Colors.amber,
      );
    }

    final repos = context.repos;
    final mejores = repos.mejoresPagadores(_ranking).take(5).toList();
    final peores = repos.peoresPagadores(_ranking).take(5).toList();

    return RefreshIndicator(
      onRefresh: () async {
        _rankingLoaded = false;
        await _loadRanking();
      },
      child: ListView(
        padding: NavShellScope.listPadding(context, left: 12, top: 12, right: 12),
        children: [
          AyudaTip(texto: l10n.tr('rankingHelpTip')),
          const SizedBox(height: 12),
          if (mejores.isNotEmpty)
            _RankingSection(
              icono: Icons.military_tech_rounded,
              titulo: l10n.tr('rankingBestPayersTitle'),
              emoji: '🏆',
              subtitulo: l10n.tr('rankingBestPayersSubtitle'),
              color: Colors.green,
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
              color: Colors.orange,
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
    required MaterialColor color,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.shade700, color.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                Text(
                  subtitulo,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                  ),
                ),
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
  final MaterialColor color;

  const _EmptyTab({
    this.icon,
    this.iconWidget,
    required this.titulo,
    required this.subtitulo,
    required this.color,
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
                color: color.shade50,
                shape: BoxShape.circle,
              ),
              child: iconWidget ??
                  Icon(icon!, size: 64, color: color.shade700),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: convocatoria.partido.esConfirmado
          ? Colors.green.shade50
          : Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: convocatoria.partido.esConfirmado
                      ? Colors.green.shade100
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  convocatoria.partido.esConfirmado
                      ? Icons.check_circle
                      : Icons.campaign,
                  color: convocatoria.partido.esConfirmado
                      ? Colors.green.shade800
                      : Colors.blue.shade800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SportChargeChip(sport: p.sportType),
                    const SizedBox(height: 6),
                    Text(
                      convocatoria.partido.esConfirmado
                          ? l10n.tr(
                              'convocatoriaConfirmedLine',
                              params: {'date': fecha, 'time': hora},
                            )
                          : '$fecha · $hora',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      p.recinto?.isNotEmpty ?? false
                          ? p.recinto!
                          : l10n.tr('noVenue'),
                      style: TextStyle(color: Colors.grey.shade700),
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
                      style: TextStyle(
                        color: convocatoria.partido.esConfirmado
                            ? Colors.green.shade800
                            : Colors.blue.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: convocatoria.partido.esConfirmado
                    ? Colors.green.shade700
                    : Colors.blue.shade700,
              ),
            ],
          ),
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: todosPagaron
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: todosPagaron
                        ? Colors.green.shade300
                        : Colors.orange.shade300,
                  ),
                ),
                child: Icon(
                  todosPagaron
                      ? Icons.check_circle_rounded
                      : Icons.pending_actions_rounded,
                  color: todosPagaron
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SportChargeChip(sport: completo.partido.sportType),
                    const SizedBox(height: 6),
                    Text(
                      fecha,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (completo.partido.recinto != null &&
                        completo.partido.recinto!.trim().isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              completo.partido.recinto!.trim(),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          hora,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
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
                          color: Colors.blue,
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
                          color: todosPagaron ? Colors.green : Colors.orange,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final MaterialColor color;

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
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.shade800,
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
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingSection extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String emoji;
  final String subtitulo;
  final MaterialColor color;
  final List<RankingJugador> items;
  final bool esBueno;

  const _RankingSection({
    required this.icono,
    required this.titulo,
    required this.emoji,
    required this.subtitulo,
    required this.color,
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icono, color: color.shade800, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$emoji $titulo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: color.shade900,
                        ),
                      ),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: color.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.shade100),
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
                          Text(
                            r.nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                esBueno
                                    ? Icons.thumb_up_alt_rounded
                                    : Icons.schedule_rounded,
                                size: 14,
                                color: color.shade700,
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
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
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
      ),
    );
  }
}
