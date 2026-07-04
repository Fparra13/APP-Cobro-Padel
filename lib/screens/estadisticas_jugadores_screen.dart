import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/supabase_helpers.dart';
import '../l10n/matchpay_strings.dart';
import '../models/estadisticas_jugador.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/jugador_avatar.dart';

enum _MetricaEstadistica {
  participacion(
    'statsMetricParticipation',
    'statsMetricParticipationDesc',
    Icons.groups_rounded,
    Colors.blue,
  ),
  buenPagador(
    'statsMetricGoodPayer',
    'statsMetricGoodPayerDesc',
    Icons.verified_rounded,
    Colors.green,
  ),
  rapido(
    'statsMetricFastPayer',
    'statsMetricFastPayerDesc',
    Icons.bolt_rounded,
    Colors.amber,
  ),
  activoReciente(
    'statsMetricActive90',
    'statsMetricActive90Desc',
    Icons.trending_up_rounded,
    Colors.teal,
  ),
  convocatoria(
    'statsMetricConvocatoria',
    'statsMetricConvocatoriaDesc',
    Icons.campaign_rounded,
    Colors.indigo,
  ),
  aportado(
    'statsMetricContributed',
    'statsMetricContributedDesc',
    Icons.payments_rounded,
    Colors.deepPurple,
  ),
  deuda(
    'statsMetricDebt',
    'statsMetricDebtDesc',
    Icons.account_balance_wallet_rounded,
    Colors.red,
  );

  final String labelKey;
  final String descKey;
  final IconData icon;
  final MaterialColor color;

  const _MetricaEstadistica(
    this.labelKey,
    this.descKey,
    this.icon,
    this.color,
  );
}

class EstadisticasJugadoresScreen extends StatefulWidget {
  const EstadisticasJugadoresScreen({super.key});

  @override
  State<EstadisticasJugadoresScreen> createState() =>
      _EstadisticasJugadoresScreenState();
}

class _EstadisticasJugadoresScreenState
    extends State<EstadisticasJugadoresScreen> {
  static const _metricas = _MetricaEstadistica.values;

  List<EstadisticasJugador> _stats = [];
  late final PageController _pageController;
  late final Map<_MetricaEstadistica, GlobalKey> _chipKeys;
  int _pageIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _chipKeys = {
      for (final m in _metricas) m: GlobalKey(),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await context.repos.getEstadisticas();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = SupabaseHelpers.describeError(
            e,
            operacion: 'Estadísticas',
          );
        });
      }
    }
  }

  List<EstadisticasJugador> _rankingPara(_MetricaEstadistica metrica) {
    final repos = context.repos;
    return switch (metrica) {
      _MetricaEstadistica.participacion => repos.masParticipacion(_stats),
      _MetricaEstadistica.buenPagador => repos.mejoresPagadoresStats(_stats),
      _MetricaEstadistica.rapido => repos.pagadoresRapidos(_stats),
      _MetricaEstadistica.activoReciente => repos.masActivosRecientes(_stats),
      _MetricaEstadistica.convocatoria => repos.reyConvocatoria(_stats),
      _MetricaEstadistica.aportado => repos.masAportado(_stats),
      _MetricaEstadistica.deuda => repos.mayorDeuda(_stats),
    };
  }

  void _irAMetrica(int index) {
    if (index < 0 || index >= _metricas.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _pageIndex = index);
    final ctx = _chipKeys[_metricas[index]]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.4,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('statsScreenTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('refreshTooltip'),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_outlined,
                            size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(context.tr('retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: AyudaTip(texto: context.tr('statsHelpTip')),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          for (var i = 0; i < _metricas.length; i++)
                            Padding(
                              key: _chipKeys[_metricas[i]],
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(
                                  context.tr(_metricas[i].labelKey),
                                ),
                                selected: _pageIndex == i,
                                avatar: Icon(
                                  _metricas[i].icon,
                                  size: 18,
                                  color: _pageIndex == i
                                      ? Colors.white
                                      : _metricas[i].color.shade700,
                                ),
                                selectedColor: _metricas[i].color,
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: _pageIndex == i ? Colors.white : null,
                                  fontWeight: _pageIndex == i
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _irAMetrica(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.swipe_rounded,
                            size: 16,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            context.tr('statsSwipeHint'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _metricas.length,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, index) {
                          final m = _metricas[index];
                          final ranking = _rankingPara(m).take(10).toList();
                          return RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                _MetricaHeader(metrica: m),
                                const SizedBox(height: 12),
                                if (ranking.isEmpty)
                                  _EmptyRanking(metrica: m)
                                else
                                  ...ranking.asMap().entries.map(
                                        (e) => _RankingTile(
                                          posicion: e.key + 1,
                                          stat: e.value,
                                          metrica: m,
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            '/historial',
                                            arguments:
                                                e.value.jugadorKeyId.isNotEmpty
                                                    ? e.value.jugadorKeyId
                                                    : e.value.jugadorId
                                                        .toString(),
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _MetricaHeader extends StatelessWidget {
  final _MetricaEstadistica metrica;

  const _MetricaHeader({required this.metrica});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [metrica.color.shade700, metrica.color.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(metrica.icon, color: Colors.white, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(metrica.labelKey),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(metrica.descKey),
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

class _EmptyRanking extends StatelessWidget {
  final _MetricaEstadistica metrica;

  const _EmptyRanking({required this.metrica});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(metrica.icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            context.tr('statsRankingEmpty'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('statsRankingEmptySubtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  final int posicion;
  final EstadisticasJugador stat;
  final _MetricaEstadistica metrica;
  final VoidCallback onTap;

  const _RankingTile({
    required this.posicion,
    required this.stat,
    required this.metrica,
    required this.onTap,
  });

  String get _medalla {
    if (posicion == 1) return '🥇';
    if (posicion == 2) return '🥈';
    if (posicion == 3) return '🥉';
    return '$posicion°';
  }

  String _valor(BuildContext context) {
    switch (metrica) {
      case _MetricaEstadistica.participacion:
        return context.tr(
          'statMatchesCount',
          params: {'count': '${stat.partidosJugados}'},
        );
      case _MetricaEstadistica.buenPagador:
        return context.tr(
          'statPercentOnTime',
          params: {'percent': stat.porcentajePagoAlDia.toStringAsFixed(0)},
        );
      case _MetricaEstadistica.rapido:
        if (stat.promedioDiasPago <= 0) return context.tr('statSameDay');
        if (stat.promedioDiasPago < 1) return context.tr('statLessThanDay');
        return context.tr(
          'statDaysAvg',
          params: {'days': stat.promedioDiasPago.toStringAsFixed(1)},
        );
      case _MetricaEstadistica.activoReciente:
        return context.tr(
          'statIn90Days',
          params: {'count': '${stat.partidosUltimos90Dias}'},
        );
      case _MetricaEstadistica.convocatoria:
        return context.tr(
          'statConfirmedCount',
          params: {'count': '${stat.convocatoriasConfirmadas}'},
        );
      case _MetricaEstadistica.aportado:
        return formatMoney(stat.totalGastado);
      case _MetricaEstadistica.deuda:
        return formatMoney(stat.saldoActual);
    }
  }

  String _detalle(BuildContext context) {
    switch (metrica) {
      case _MetricaEstadistica.participacion:
        return context.tr(
          'statPaidOnTime',
          params: {'count': '${stat.pagosAlDia}'},
        );
      case _MetricaEstadistica.buenPagador:
        return context.tr(
          'statMatchesLate',
          params: {
            'count': '${stat.partidosJugados}',
            'late': '${stat.pagosTardios}',
          },
        );
      case _MetricaEstadistica.rapido:
        return context.tr(
          'statPaymentsOnTime',
          params: {'count': '${stat.pagosAlDia}'},
        );
      case _MetricaEstadistica.activoReciente:
        return context.tr(
          'statTotalMatches',
          params: {'count': '${stat.partidosJugados}'},
        );
      case _MetricaEstadistica.convocatoria:
        return context.tr(
          'statMatchesPlayed',
          params: {'count': '${stat.partidosJugados}'},
        );
      case _MetricaEstadistica.aportado:
        return context.tr(
          'statMatchesCount',
          params: {'count': '${stat.partidosJugados}'},
        );
      case _MetricaEstadistica.deuda:
        return context.tr(
          'statUnpaidMatches',
          params: {'count': '${stat.partidosImpagos}'},
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  _medalla,
                  style: TextStyle(
                    fontSize: posicion <= 3 ? 22 : 16,
                    fontWeight: FontWeight.bold,
                    color: posicion <= 3 ? null : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              JugadorAvatar(
                nombre: stat.nombre,
                fotoPath: stat.fotoPath,
                fotoUrl: stat.fotoUrl,
                size: 44,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _detalle(context),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _valor(context),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: metrica.color.shade700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
