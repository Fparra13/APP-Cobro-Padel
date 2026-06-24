import 'package:flutter/material.dart';

import '../repositories/partido_repository.dart';
import '../utils/formatters.dart';

/// Resumen de deudas: top 3 destacado + lista completa scrolleable.
/// Mejor que un gráfico de barras cuando hay ~12 jugadores habituales.
class DeudaChartWidget extends StatelessWidget {
  final List<ResumenJugador> resumenes;

  const DeudaChartWidget({super.key, required this.resumenes});

  @override
  Widget build(BuildContext context) {
    final conDeuda = resumenes.where((r) => r.saldoActual > 0).toList()
      ..sort((a, b) => b.saldoActual.compareTo(a.saldoActual));
    final alDia = resumenes.where((r) => r.saldoActual <= 0).length;
    final totalDeuda =
        conDeuda.fold(0.0, (s, r) => s + r.saldoActual);
    final maxSaldo =
        conDeuda.isEmpty ? 1.0 : conDeuda.first.saldoActual;

    if (conDeuda.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¡Todos al día!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '$alDia jugadores sin deuda pendiente',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
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

    final top3 = conDeuda.take(3).toList();
    const medallas = ['🥇', '🥈', '🥉'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('💸', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Deudas del grupo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${conDeuda.length} debiendo · Total ${formatMoney(totalDeuda)}'
                        '${alDia > 0 ? ' · $alDia al día ✅' : ''}',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (top3.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Top deudores',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: top3.asMap().entries.map((e) {
                  final r = e.value;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: e.key < 2 ? 6 : 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _topColor(e.key).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _topColor(e.key).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(medallas[e.key], style: const TextStyle(fontSize: 20)),
                          const SizedBox(height: 4),
                          Text(
                            _shortName(r.jugador.nombre),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatMoney(r.saldoActual),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _topColor(e.key),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Todos los que deben',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: conDeuda.length > 6 ? 280 : conDeuda.length * 44.0,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: conDeuda.length > 6
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: conDeuda.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = conDeuda[i];
                  final pct = maxSaldo > 0 ? r.saldoActual / maxSaldo : 0.0;
                  return _DeudaFila(
                    nombre: r.jugador.nombre,
                    monto: r.saldoActual,
                    progreso: pct,
                    rank: i + 1,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortName(String nombre) {
    final parts = nombre.split(' ');
    return parts.first;
  }

  Color _topColor(int index) {
    const colors = [
      Color(0xFFC62828),
      Color(0xFFE65100),
      Color(0xFFF9A825),
    ];
    return colors[index % colors.length];
  }
}

class _DeudaFila extends StatelessWidget {
  final String nombre;
  final double monto;
  final double progreso;
  final int rank;

  const _DeudaFila({
    required this.nombre,
    required this.monto,
    required this.progreso,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$rank.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatMoney(monto),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progreso.clamp(0.05, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.red.shade50,
                  color: Colors.red.shade400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
