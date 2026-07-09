import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/sport_type.dart';
import '../domain/cobro_logic.dart';
import '../domain/deuda_explicacion.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/saldo_historico.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/cobro_ver_detalle_sheet.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/player_match_history_tile.dart';
import '../widgets/player_matches_to_close.dart';
import '../widgets/shimmer_loading.dart';

/// Historial de partidos del jugador (pestaña principal del shell).
class MiHistorialScreen extends StatefulWidget {
  final VoidCallback? onOpenMisCobros;

  const MiHistorialScreen({super.key, this.onOpenMisCobros});

  @override
  State<MiHistorialScreen> createState() => _MiHistorialScreenState();
}

class _MiHistorialScreenState extends State<MiHistorialScreen> {
  List<DetallePartido> _partidos = [];
  Map<int, double> _saldosPorPartido = {};
  List<SaldoHistorico> _historialSaldo = [];
  double _saldoAcumulado = 0;
  bool _loading = true;
  String? _error;
  SportType? _filtroDeporte;

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
      final partidos = await repos.getMisPartidosJugados(limit: 100);
      final ids = partidos.map((p) => p.partidoId).toSet();
      final saldos = await repos.getMisSaldosAnterioresPartidos(ids);
      final historialFuture = uid != null
          ? repos.getSaldosByJugador(uid)
          : Future.value(<SaldoHistorico>[]);
      final jugadorFuture = uid != null
          ? repos.getJugador(uid)
          : Future.value(null);
      final historialSaldo = await historialFuture;
      final jugador = await jugadorFuture;
      if (!mounted) return;
      setState(() {
        _partidos = partidos;
        _saldosPorPartido = saldos;
        _historialSaldo = historialSaldo;
        _saldoAcumulado = jugador?.saldoAcumulado ?? 0;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.userError(e);
        _loading = false;
      });
    }
  }

  Future<void> _verDetalle(DetallePartido detalle) async {
    DesgloseJugador? desglose;
    try {
      desglose = await context.repos.getMiDesglosePartido(detalle.partidoId);
    } catch (_) {}

    if (!mounted) return;
    await CobroVerDetalleSheet.show(
      context,
      detalle: detalle,
      desglose: desglose,
      saldoAnteriorAlPartido: _saldosPorPartido[detalle.partidoId],
      saldoAcumuladoJugador: _saldoAcumulado,
      historialSaldo: _historialSaldo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final cuentaConDeuda =
        CobroLogic.obtenerPendienteJugador(saldoAcumulado: _saldoAcumulado) >
            0.005;
    final explicacion = cuentaConDeuda
        ? explicarDeudaJugador(
            saldoAcumulado: _saldoAcumulado,
            historial: _historialSaldo,
          )
        : null;
    DetallePartido? ancla;
    if (explicacion?.partidoIdContexto != null) {
      for (final p in _partidos) {
        if (p.partidoId == explicacion!.partidoIdContexto) {
          ancla = p;
          break;
        }
      }
    }

    final conteoDeportes = conteoDeportesHistorial(_partidos);
    final partidosVisibles =
        filtrarPartidosPorDeporte(_partidos, _filtroDeporte);
    final pagadosVisibles =
        countPartidosPagadosHistorial(partidosVisibles, _saldosPorPartido);
    final pendientesVisibles =
        countPartidosPendientesHistorial(partidosVisibles, _saldosPorPartido);

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(title: Text(l10n.tr('playerMatchHistoryTitle'))),
      body: _loading
          ? ListView(
              padding: NavShellScope.listPadding(context),
              children: const [
                ShimmerLoading(
                  height: 168,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                SizedBox(height: 16),
                ShimmerLoading(
                  height: 96,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                SizedBox(height: 12),
                ShimmerLoading(
                  height: 96,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ],
            )
          : _error != null
              ? FriendlyErrorPanel(message: _error!, onRetry: () => _load())
              : RefreshIndicator(
                  color: palette.primary,
                  onRefresh: () => _load(silent: true),
                  child: _partidos.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: NavShellScope.listPadding(context),
                          children: [
                            const SizedBox(height: 24),
                            _MatchHistoryEmptyState(),
                          ],
                        )
                      : ListView(
                          padding: NavShellScope.listPadding(context),
                          children: [
                            PlayerMatchHistoryHero(
                              totalPartidos: partidosVisibles.length,
                              pagados: pagadosVisibles,
                              pendientes: pendientesVisibles,
                              conteoPorDeporte: conteoDeportes,
                              deporteSeleccionado: _filtroDeporte,
                              onDeporteSeleccionado: (sport) {
                                setState(() => _filtroDeporte = sport);
                              },
                            ),
                            if (cuentaConDeuda && widget.onOpenMisCobros != null) ...[
                              const SizedBox(height: 14),
                              MatchPaySurfaceCard(
                                urgent: true,
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: MatchPayTokens.accentUrgentBg,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.account_balance_wallet_outlined,
                                        color: MatchPayTokens.accentUrgent,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        l10n.tr('playerMatchHistoryDebtBanner'),
                                        style: MatchPayTokens.bodySmallStyle()
                                            .copyWith(
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: widget.onOpenMisCobros,
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            MatchPayTokens.accentUrgentBg,
                                        foregroundColor:
                                            MatchPayTokens.accentUrgent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                      ),
                                      child: Text(l10n.tr('myCharges')),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (cuentaConDeuda && explicacion != null) ...[
                              const SizedBox(height: 12),
                              PlayerDeudaExplicacionCard(
                                explicacion: explicacion,
                                partidoLinea: lineaPartidoDetalle(ancla),
                              ),
                            ],
                            const SizedBox(height: 18),
                            if (partidosVisibles.isEmpty)
                              MatchPaySurfaceCard(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  l10n.tr('playerMatchHistoryFilterEmpty'),
                                  textAlign: TextAlign.center,
                                  style: MatchPayTokens.bodySmallStyle().copyWith(
                                    height: 1.4,
                                  ),
                                ),
                              )
                            else
                              PlayerMatchHistoryList(
                                partidos: partidosVisibles,
                                saldosPorPartido: _saldosPorPartido,
                                modo: cuentaConDeuda
                                    ? PlayerMatchHistorialModo.cuentaConDeuda
                                    : PlayerMatchHistorialModo.porPartido,
                                historialSaldo: cuentaConDeuda
                                    ? _historialSaldo
                                    : null,
                                groupByMonth: true,
                                visual: PlayerMatchHistoryVisual.premium,
                                onPartidoTap: _verDetalle,
                              ),
                          ],
                        ),
                ),
    );
  }
}

class _MatchHistoryEmptyState extends StatelessWidget {
  const _MatchHistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3F4F6), MatchPayTokens.surfaceCard],
        ),
        border: Border.all(color: MatchPayTokens.borderSubtle),
      ),
      child: Column(
        children: [
          const Text('🏟️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            l10n.tr('playerMatchHistoryEmpty'),
            textAlign: TextAlign.center,
            style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr('playerMatchHistoryEmptyHint'),
            textAlign: TextAlign.center,
            style: MatchPayTokens.bodySmallStyle().copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
