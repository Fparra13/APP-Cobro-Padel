import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/partido_repository.dart';
import '../repositories/ranking_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/partido_detalle_sheet.dart';

class HistorialPartidosScreen extends StatefulWidget {
  const HistorialPartidosScreen({super.key});

  @override
  State<HistorialPartidosScreen> createState() =>
      _HistorialPartidosScreenState();
}

class _HistorialPartidosScreenState extends State<HistorialPartidosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _partidoRepo = PartidoRepository();
  final _rankingRepo = RankingRepository();
  final _pdfService = PdfService();

  List<PartidoCompleto> _partidos = [];
  List<RankingJugador> _ranking = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _partidoRepo.getAll();
    final completos = <PartidoCompleto>[];
    for (final p in list) {
      final c = await _partidoRepo.getCompleto(p.id!);
      if (c != null) completos.add(c);
    }
    final ranking = await _rankingRepo.getRanking();
    if (mounted) {
      setState(() {
        _partidos = completos;
        _ranking = ranking;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Historial y Ranking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 26),
            tooltip: 'Actualizar',
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
          tabs: const [
            Tab(
              height: 52,
              icon: Icon(Icons.sports_tennis_rounded, size: 26),
              text: 'Partidos',
            ),
            Tab(
              height: 52,
              icon: Icon(Icons.emoji_events_rounded, size: 26),
              text: 'Ranking',
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
    if (_partidos.isEmpty) {
      return _EmptyTab(
        icon: Icons.sports_tennis_rounded,
        titulo: 'Sin partidos aún',
        subtitulo: 'Registra tu primer partido desde el botón\n"Nuevo partido" en Inicio.',
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
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _buildStatsHeader(
            icon: Icons.history_rounded,
            titulo: '${_partidos.length} partidos',
            subtitulo: pendientesTotal > 0
                ? '$pendientesTotal cobros pendientes en total'
                : 'Todos los cobros al día ✓',
            color: Colors.green,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: AyudaTip(
              texto:
                  'Toca un partido para ver el detalle. '
                  'Arriba: PDF general · Abajo: WhatsApp/PDF individual.',
            ),
          ),
          ..._partidos.map(
            (pc) => _PartidoCard(
              completo: pc,
              partidoRepo: _partidoRepo,
              pdfService: _pdfService,
              onChanged: _load,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRanking() {
    if (_ranking.isEmpty) {
      return _EmptyTab(
        icon: Icons.emoji_events_rounded,
        titulo: 'Ranking vacío',
        subtitulo: 'Juega algunos partidos para ver\nquién paga más rápido 🎾',
        color: Colors.amber,
      );
    }

    final mejores = _rankingRepo.mejoresPagadores(_ranking).take(5).toList();
    final peores = _rankingRepo.peoresPagadores(_ranking).take(5).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const AyudaTip(
            texto:
                'Ranking basado en pagos al día e impagos. '
                '¡Solo para diversión entre amigos! 😄',
          ),
          const SizedBox(height: 12),
          if (mejores.isNotEmpty)
            _RankingSection(
              icono: Icons.military_tech_rounded,
              titulo: 'Mejores pagadores',
              emoji: '🏆',
              subtitulo: 'Los que pagan más rápido (¡cracks!)',
              color: Colors.green,
              items: mejores,
              esBueno: true,
            )
          else
            _RankingEmptyHint(
              emoji: '🏆',
              titulo: 'Sin mejores pagadores aún',
              subtitulo: 'Aparecen quienes pagan al día sin impagos pendientes.',
            ),
          const SizedBox(height: 16),
          if (peores.isNotEmpty)
            _RankingSection(
              icono: Icons.hourglass_bottom_rounded,
              titulo: 'Peores pagadores',
              emoji: '🐢',
              subtitulo: 'Los que más demoran (sin rencores 😄)',
              color: Colors.orange,
              items: peores,
              esBueno: false,
            )
          else
            _RankingEmptyHint(
              emoji: '✅',
              titulo: '¡Nadie en la lista negra!',
              subtitulo: 'No hay jugadores con impagos ni pagos tardíos.',
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
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final MaterialColor color;

  const _EmptyTab({
    required this.icon,
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
              child: Icon(icon, size: 64, color: color.shade700),
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

class _PartidoCard extends StatelessWidget {
  final PartidoCompleto completo;
  final PartidoRepository partidoRepo;
  final PdfService pdfService;
  final VoidCallback onChanged;

  const _PartidoCard({
    required this.completo,
    required this.partidoRepo,
    required this.pdfService,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat('dd/MM/yyyy').format(completo.partido.fecha);
    final hora = DateFormat('HH:mm').format(completo.partido.fecha);
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
          partidoRepo: partidoRepo,
          pdfService: pdfService,
          onEditar: () {
            Navigator.pop(context);
            Navigator.pushNamed(
              context,
              '/editar-partido',
              arguments: completo.partido.id,
            ).then((_) => onChanged());
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
                          label: '$asistentes jugadores',
                          color: Colors.blue,
                        ),
                        _InfoChip(
                          icon: todosPagaron
                              ? Icons.verified_rounded
                              : Icons.warning_amber_rounded,
                          label: todosPagaron
                              ? 'Todos pagaron'
                              : '$pendientes sin pagar',
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
                                      ? '${r.pagosAlDia} pagos al día · ${r.porcentajePagoAlDia.toStringAsFixed(0)}%'
                                      : '${r.partidosImpagos} impagos · Deuda ${formatMoney(r.saldoActual)}',
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
