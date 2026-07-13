import 'package:flutter/material.dart';

import '../l10n/matchpay_strings.dart';
import '../repositories/partido_repository.dart';
import '../utils/formatters.dart';
import 'jugador_avatar.dart';

/// Resumen visual de deudas del grupo.
class DeudaChartWidget extends StatefulWidget {
  final List<ResumenJugador> resumenes;
  final VoidCallback? onRecordar;

  const DeudaChartWidget({
    super.key,
    required this.resumenes,
    this.onRecordar,
  });

  @override
  State<DeudaChartWidget> createState() => _DeudaChartWidgetState();
}

class _DeudaChartWidgetState extends State<DeudaChartWidget> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conDeuda = widget.resumenes.where((r) => r.tieneDeuda).toList()
      ..sort((a, b) => b.deudaVisible.compareTo(a.deudaVisible));
    final alDia = widget.resumenes.where((r) => !r.tieneDeuda).length;
    final totalDeuda = conDeuda.fold(0.0, (s, r) => s + r.deudaVisible);

    if (conDeuda.isEmpty) {
      return _SeccionCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.celebration_rounded,
                  color: Colors.green.shade700, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tr('debtChartAllUpToDate'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green.shade800,
                    ),
                  ),
                  Text(
                    alDia == 1
                        ? l10n.tr('debtChartOnePlayerUpToDate',
                            params: {'count': '$alDia'})
                        : l10n.tr('debtChartPlayersUpToDate',
                            params: {'count': '$alDia'}),
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
      );
    }

    final visibles = _expandido ? conDeuda : conDeuda.take(4).toList();
    const medallas = ['🥇', '🥈', '🥉'];

    return _SeccionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.red.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('debtChartToCollect'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      conDeuda.length == 1
                          ? l10n.tr('debtChartOneDebtorLine',
                              params: {'amount': formatMoney(totalDeuda)})
                          : l10n.tr('debtChartDebtorsLine', params: {
                              'count': '${conDeuda.length}',
                              'amount': formatMoney(totalDeuda),
                            }),
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onRecordar != null)
                IconButton.filledTonal(
                  onPressed: widget.onRecordar,
                  icon: const Icon(Icons.chat_rounded, size: 20),
                  tooltip: l10n.tr('debtChartRemindPush'),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green.shade50,
                    foregroundColor: Colors.green.shade800,
                  ),
                ),
            ],
          ),
          if (conDeuda.length >= 2) ...[
            const SizedBox(height: 14),
            Row(
              children: conDeuda.take(3).toList().asMap().entries.map((e) {
                final r = e.value;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: e.key < 2 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _topColor(e.key).withValues(alpha: 0.12),
                          _topColor(e.key).withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _topColor(e.key).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(medallas[e.key], style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 6),
                        Text(
                          _shortName(r.jugador.nombre),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatMoney(r.deudaVisible),
                          style: TextStyle(
                            fontSize: 13,
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
          ...visibles.asMap().entries.map(
                (e) => Padding(
                  padding: EdgeInsets.only(
                    bottom: e.key < visibles.length - 1 ? 8 : 0,
                  ),
                  child: _DeudaTile(
                    resumen: e.value,
                    rank: conDeuda.indexOf(e.value) + 1,
                    esTop: conDeuda.indexOf(e.value) < 3,
                  ),
                ),
              ),
          if (conDeuda.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: () => setState(() => _expandido = !_expandido),
                icon: Icon(
                  _expandido
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  _expandido
                      ? l10n.tr('debtChartShowLess')
                      : l10n.tr('debtChartShowMore',
                          params: {'count': '${conDeuda.length - 4}'}),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _shortName(String nombre) => nombre.split(' ').first;

  Color _topColor(int index) {
    const colors = [
      Color(0xFFC62828),
      Color(0xFFE65100),
      Color(0xFFF9A825),
    ];
    return colors[index % colors.length];
  }
}

class _SeccionCard extends StatelessWidget {
  final Widget child;

  const _SeccionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DeudaTile extends StatelessWidget {
  final ResumenJugador resumen;
  final int rank;
  final bool esTop;

  const _DeudaTile({
    required this.resumen,
    required this.rank,
    required this.esTop,
  });

  @override
  Widget build(BuildContext context) {
    final j = resumen.jugador;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          JugadorAvatar(
            nombre: j.nombre,
            fotoPath: j.fotoPath,
            fotoUrl: j.fotoUrl,
            size: 40,
            borderRadius: 12,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  j.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.tr(
                    'matchesPlayedCount',
                    params: {'count': '${resumen.partidosJugados}'},
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(resumen.deudaVisible),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.red.shade800,
                ),
              ),
              if (esTop)
                Text(
                  '#$rank',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
