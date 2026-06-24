import 'package:flutter/material.dart';

import '../models/estadisticas_jugador.dart';
import '../repositories/estadisticas_repository.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/jugador_avatar.dart';

enum _MetricaEstadistica {
  participacion(
    'Participación',
    Icons.sports_tennis_rounded,
    Colors.blue,
    'Quién juega más partidos con el grupo',
  ),
  buenPagador(
    'Buen pagador',
    Icons.verified_rounded,
    Colors.green,
    'Paga al día, sin impagos (mín. 2 partidos)',
  ),
  rapido(
    'Pago rápido',
    Icons.bolt_rounded,
    Colors.amber,
    'Menor tiempo promedio para pagar',
  ),
  activoReciente(
    'Activo (90 días)',
    Icons.trending_up_rounded,
    Colors.teal,
    'Más partidos en los últimos 3 meses',
  ),
  convocatoria(
    'Convocatorias',
    Icons.campaign_rounded,
    Colors.indigo,
    'Más confirmaciones en convocatorias',
  ),
  aportado(
    'Total aportado',
    Icons.payments_rounded,
    Colors.deepPurple,
    'Mayor monto acumulado en partidos',
  ),
  deuda(
    'Mayor deuda',
    Icons.account_balance_wallet_rounded,
    Colors.red,
    'Saldo pendiente actual (para seguimiento)',
  );

  final String label;
  final IconData icon;
  final MaterialColor color;
  final String descripcion;

  const _MetricaEstadistica(
    this.label,
    this.icon,
    this.color,
    this.descripcion,
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
  final _repo = EstadisticasRepository();
  List<EstadisticasJugador> _stats = [];
  _MetricaEstadistica _metrica = _MetricaEstadistica.participacion;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await _repo.getAll();
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  List<EstadisticasJugador> get _rankingActual {
    switch (_metrica) {
      case _MetricaEstadistica.participacion:
        return _repo.masParticipacion(_stats);
      case _MetricaEstadistica.buenPagador:
        return _repo.mejoresPagadores(_stats);
      case _MetricaEstadistica.rapido:
        return _repo.pagadoresRapidos(_stats);
      case _MetricaEstadistica.activoReciente:
        return _repo.masActivosRecientes(_stats);
      case _MetricaEstadistica.convocatoria:
        return _repo.reyConvocatoria(_stats);
      case _MetricaEstadistica.aportado:
        return _repo.masAportado(_stats);
      case _MetricaEstadistica.deuda:
        return _repo.mayorDeuda(_stats);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ranking = _rankingActual.take(10).toList();
    final m = _metrica;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Estadísticas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  const AyudaTip(
                    texto:
                        'Rankings del grupo basados en partidos reales. '
                        '¡Solo para diversión entre amigos! 😄',
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _MetricaEstadistica.values.map((metrica) {
                        final selected = _metrica == metrica;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(metrica.label),
                            selected: selected,
                            avatar: Icon(
                              metrica.icon,
                              size: 18,
                              color: selected
                                  ? Colors.white
                                  : metrica.color.shade700,
                            ),
                            selectedColor: metrica.color,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : null,
                              fontWeight:
                                  selected ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (_) =>
                                setState(() => _metrica = metrica),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                              arguments: e.value.jugadorId,
                            ),
                          ),
                        ),
                ],
              ),
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
                  metrica.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metrica.descripcion,
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
            'Sin datos para este ranking',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Registra partidos y convocatorias\npara ver estadísticas aquí.',
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

  String get _valor {
    switch (metrica) {
      case _MetricaEstadistica.participacion:
        return '${stat.partidosJugados} partido${stat.partidosJugados == 1 ? '' : 's'}';
      case _MetricaEstadistica.buenPagador:
        return '${stat.porcentajePagoAlDia.toStringAsFixed(0)}% al día';
      case _MetricaEstadistica.rapido:
        if (stat.promedioDiasPago <= 0) return 'Mismo día';
        if (stat.promedioDiasPago < 1) return '< 1 día';
        return '${stat.promedioDiasPago.toStringAsFixed(1)} días prom.';
      case _MetricaEstadistica.activoReciente:
        return '${stat.partidosUltimos90Dias} en 90 días';
      case _MetricaEstadistica.convocatoria:
        return '${stat.convocatoriasConfirmadas} confirmada${stat.convocatoriasConfirmadas == 1 ? '' : 's'}';
      case _MetricaEstadistica.aportado:
        return formatMoney(stat.totalGastado);
      case _MetricaEstadistica.deuda:
        return formatMoney(stat.saldoActual);
    }
  }

  String get _detalle {
    switch (metrica) {
      case _MetricaEstadistica.participacion:
        return '${stat.pagosAlDia} pagados al día';
      case _MetricaEstadistica.buenPagador:
        return '${stat.partidosJugados} partidos · ${stat.pagosTardios} tardíos';
      case _MetricaEstadistica.rapido:
        return '${stat.pagosAlDia} pagos al día';
      case _MetricaEstadistica.activoReciente:
        return '${stat.partidosJugados} partidos en total';
      case _MetricaEstadistica.convocatoria:
        return '${stat.partidosJugados} partidos jugados';
      case _MetricaEstadistica.aportado:
        return '${stat.partidosJugados} partidos';
      case _MetricaEstadistica.deuda:
        return '${stat.partidosImpagos} partido${stat.partidosImpagos == 1 ? '' : 's'} impago${stat.partidosImpagos == 1 ? '' : 's'}';
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
                      _detalle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _valor,
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
