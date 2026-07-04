import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/supabase_helpers.dart';
import '../l10n/matchpay_strings.dart';
import '../models/detalle_partido.dart';
import '../utils/formatters.dart';
import '../widgets/player_match_history_tile.dart';
import 'mis_cobros_screen.dart';

/// Historial de partidos del jugador autenticado (no la ficha de admin).
class MiHistorialScreen extends StatefulWidget {
  const MiHistorialScreen({super.key});

  @override
  State<MiHistorialScreen> createState() => _MiHistorialScreenState();
}

class _MiHistorialScreenState extends State<MiHistorialScreen> {
  List<DetallePartido> _partidos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final partidos = await repos.getMisPartidosJugados(limit: 100);
      if (!mounted) return;
      setState(() {
        _partidos = partidos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseHelpers.describeError(e, operacion: 'Mi historial');
        _loading = false;
      });
    }
  }

  Future<void> _openMisCobros() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MisCobrosScreen()),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pagados = _partidos.where((p) => p.pagado).length;
    final pendientes = _partidos.where((p) => p.tieneDeudaEnCobro).length;
    final totalGastado =
        _partidos.fold<double>(0, (s, p) => s + p.total);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      appBar: AppBar(
        title: Text(l10n.tr('playerMatchHistoryTitle')),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _openMisCobros,
            child: Text(l10n.tr('myCharges')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: Text(l10n.tr('retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _partidos.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Icon(
                              Icons.event_busy_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.tr('playerMatchHistoryEmpty'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFE8E6E1),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _ResumenChip(
                                    label: l10n.tr('playerStatMatches'),
                                    value: '${_partidos.length}',
                                  ),
                                  _ResumenChip(
                                    label: l10n.tr('playerMatchPaid'),
                                    value: '$pagados',
                                  ),
                                  _ResumenChip(
                                    label: l10n.tr('pendingStatus'),
                                    value: '$pendientes',
                                  ),
                                  _ResumenChip(
                                    label: l10n.tr('playerStatSpent'),
                                    value: formatMoney(totalGastado),
                                    flex: 2,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE8E6E1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < _partidos.length; i++) ...[
                                    if (i > 0)
                                      const Divider(
                                        height: 1,
                                        indent: 16,
                                        endIndent: 16,
                                      ),
                                    PlayerMatchHistoryTile(
                                      detalle: _partidos[i],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
    );
  }
}

class _ResumenChip extends StatelessWidget {
  final String label;
  final String value;
  final int flex;

  const _ResumenChip({
    required this.label,
    required this.value,
    this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Color(0xFF111827),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
