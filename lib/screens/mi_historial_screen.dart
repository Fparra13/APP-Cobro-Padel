import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/supabase_helpers.dart';
import '../l10n/matchpay_strings.dart';
import '../models/detalle_partido.dart';
import '../utils/matchpay_context.dart';
import '../utils/formatters.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/player_match_history_tile.dart';
import '../widgets/shimmer_loading.dart';
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
    final palette = context.sportPalette;
    final pagados = _partidos.where((p) => p.pagado).length;
    final pendientes = _partidos.where((p) => p.tieneDeudaEnCobro).length;
    final totalGastado =
        _partidos.fold<double>(0, (s, p) => s + p.total);

    return Scaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(
        title: Text(l10n.tr('playerMatchHistoryTitle')),
        backgroundColor: MatchPayTokens.surfaceCard,
        foregroundColor: MatchPayTokens.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _openMisCobros,
            child: Text(l10n.tr('myCharges')),
          ),
        ],
      ),
      body: _loading
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                ShimmerLoading(
                  height: 108,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                SizedBox(height: 14),
                ShimmerLoading(
                  height: 72,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                SizedBox(height: 8),
                ShimmerLoading(
                  height: 72,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ],
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: MatchPayTokens.bodySmallStyle(),
                        ),
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
                  color: palette.primary,
                  onRefresh: _load,
                  child: _partidos.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            MatchPaySurfaceCard(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.event_busy_rounded,
                                    size: 48,
                                    color: MatchPayTokens.inkMuted,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.tr('playerMatchHistoryEmpty'),
                                    textAlign: TextAlign.center,
                                    style: MatchPayTokens.titleSmallStyle(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            12,
                            16,
                            16 + MediaQuery.paddingOf(context).bottom,
                          ),
                          children: [
                            SizedBox(
                              height: 108,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: 4,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final items = [
                                    (
                                      Icons.emoji_events_rounded,
                                      const Color(0xFFF59E0B),
                                      '${_partidos.length}',
                                      l10n.tr('playerStatMatches'),
                                    ),
                                    (
                                      Icons.check_circle_rounded,
                                      MatchPayTokens.accentSuccess,
                                      '$pagados',
                                      l10n.tr('playerMatchPaid'),
                                    ),
                                    (
                                      Icons.schedule_rounded,
                                      MatchPayTokens.accentUrgent,
                                      '$pendientes',
                                      l10n.tr('pendingStatus'),
                                    ),
                                    (
                                      Icons.payments_rounded,
                                      palette.primary,
                                      formatMoney(totalGastado),
                                      l10n.tr('playerStatSpent'),
                                    ),
                                  ];
                                  final e = items[index];
                                  return MatchPayStatChip(
                                    icon: e.$1,
                                    iconColor: e.$2,
                                    value: e.$3,
                                    label: e.$4,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            MatchPaySurfaceCard(
                              padding: EdgeInsets.zero,
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
