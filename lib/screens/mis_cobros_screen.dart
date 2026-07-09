import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/deuda_explicacion.dart';
import '../models/saldo_historico.dart';
import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../utils/player_pay_bridge.dart';
import '../widgets/cobro_pago_flow.dart';
import '../widgets/cobro_ver_detalle_sheet.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/player_match_history_tile.dart';
import '../widgets/player_matches_to_close.dart';
import '../widgets/shimmer_loading.dart';

/// Cobros del jugador: cuenta + historial de partidos.
class MisCobrosScreen extends StatefulWidget {
  const MisCobrosScreen({super.key});

  @override
  State<MisCobrosScreen> createState() => _MisCobrosScreenState();
}

class _MisCobrosScreenState extends State<MisCobrosScreen> {
  List<DetallePartido> _deudas = [];
  List<DetallePartido> _partidosJugados = [];
  final Map<int, DesgloseJugador?> _desglosePorPartido = {};
  final Map<int, double> _saldoAnteriorPorPartido = {};
  double? _saldoAcumuladoJugador;
  List<SaldoHistorico> _historialSaldo = [];
  bool _loading = true;
  bool _hasLoaded = false;
  bool _loadInFlight = false;
  String? _error;
  bool _pagando = false;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    PlayerPayBridge.instance.registerPayTotalHandler(() async {
      if (!_hasLoaded) {
        await _load();
      }
      await _pagar(esTotal: true);
    });
    PlayerPayBridge.instance.registerPayOtherHandler(() async {
      if (!_hasLoaded) {
        await _load();
      }
      await _pagar(esTotal: false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    AppRepositories.dataRevision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    PlayerPayBridge.instance.unregisterPayTotalHandler();
    PlayerPayBridge.instance.unregisterPayOtherHandler();
    _reloadDebounce?.cancel();
    AppRepositories.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    if (!_hasLoaded && !silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repos = context.repos;
      final uid = AuthService.instance.currentUser?.id;
      final rawDeudas =
          await repos.getMisDeudasPendientes(reconciliar: false);
      final jugadorFuture = uid != null
          ? repos.getJugador(uid)
          : Future.value(null);
      final historialFuture = uid != null
          ? repos.getSaldosByJugador(uid)
          : Future.value(<SaldoHistorico>[]);
      final partidosJugadosFuture = repos.getMisPartidosJugados(limit: 30);
      final partidoIds = rawDeudas.map((d) => d.partidoId).toSet();
      final partidosJugados = await partidosJugadosFuture;
      partidoIds.addAll(partidosJugados.map((p) => p.partidoId));
      final saldosAnteriores =
          await repos.getMisSaldosAnterioresPartidos(partidoIds);
      final deudas = ordenarCobrosPorAtencion(
        rawDeudas,
        saldosAnterioresPorPartido: saldosAnteriores,
      );
      final jugador = await jugadorFuture;
      final historialSaldo = await historialFuture;
      final desgloseMap = <int, DesgloseJugador?>{};
      await Future.wait(
        deudas.map((d) async {
          try {
            desgloseMap[d.partidoId] = await repos.getMiDesglosePartido(
              d.partidoId,
            );
          } catch (_) {
            desgloseMap[d.partidoId] = null;
          }
        }),
      );
      if (mounted) {
        setState(() {
          _deudas = deudas;
          _partidosJugados = partidosJugados;
          _desglosePorPartido
            ..clear()
            ..addAll(desgloseMap);
          _saldoAnteriorPorPartido
            ..clear()
            ..addAll(saldosAnteriores);
          _saldoAcumuladoJugador = jugador?.saldoAcumulado;
          _historialSaldo = historialSaldo;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = context.userError(e);
        });
      }
    } finally {
      _loadInFlight = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _hasLoaded = true;
        });
      }
    }
  }

  Future<void> _pagar({required bool esTotal}) async {
    if (_pagando) return;
    setState(() => _pagando = true);
    try {
      await CobroPagoFlow.iniciarPagoGlobal(
        context: context,
        deudas: _deudas,
        desgloses: _desglosePorPartido,
        saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
        saldoAcumuladoJugador: _saldoAcumuladoJugador,
        esTotal: esTotal,
        onCompletado: () => _load(silent: true),
      );
    } finally {
      if (mounted) setState(() => _pagando = false);
    }
  }

  void _verDetalle(DetallePartido detalle) {
    final bloqueado =
        _deudas.any((d) => d.comprobantePendienteValidacion);
    final ancla = cobrosVisiblesJugador(
      deudas: _deudas,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
      saldoAcumuladoJugador: _saldoAcumuladoJugador,
    ).ancla;
    CobroVerDetalleSheet.show(
      context,
      detalle: detalle,
      desglose: _desglosePorPartido[detalle.partidoId],
      saldoAnteriorAlPartido: _saldoAnteriorPorPartido[detalle.partidoId],
      saldoAcumuladoJugador: _saldoAcumuladoJugador,
      esAnclaCuenta: detalle.partidoId == ancla?.partidoId,
      historialSaldo: _historialSaldo,
      onPayTotal: bloqueado ? null : () => _pagar(esTotal: true),
      onPayAbono: bloqueado ? null : () => _pagar(esTotal: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;
    final visibles = cobrosVisiblesJugador(
      deudas: _deudas,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
      saldoAcumuladoJugador: _saldoAcumuladoJugador,
    );
    final explicacion = explicarDeudaJugador(
      saldoAcumulado: _saldoAcumuladoJugador ?? 0,
      historial: _historialSaldo,
    );
    final ancla = visibles.ancla;
    final total = totalPendienteCobros(
      _deudas,
      _desglosePorPartido,
      saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
      saldoAcumuladoJugador: _saldoAcumuladoJugador,
    );
    final cuentaConDeuda = (_saldoAcumuladoJugador ?? 0) > 0.005;
    final comprobanteEnRevision =
        _deudas.any((d) => d.comprobantePendienteValidacion);

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(title: Text(l10n.tr('myChargesScreenTitle'))),
      body: !_hasLoaded && _loading
          ? ListView(
              padding: NavShellScope.listPadding(context),
              children: const [
                ShimmerLoading(
                  height: 200,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                SizedBox(height: 16),
                ShimmerLoading(
                  height: 120,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: ListView(
                padding: NavShellScope.listPadding(context),
                children: [
                  if (_error != null) ...[
                    FriendlyErrorPanel(
                      message: _error!,
                      onRetry: () => _load(silent: false),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_deudas.isEmpty)
                    PlayerCuentaAlDiaCard(
                      saldoAFavor: saldoAFavorJugador(
                        _saldoAcumuladoJugador ?? 0,
                      ),
                    )
                  else ...[
                    PlayerMisCobrosHeroCard(
                      total: total,
                      pagando: _pagando,
                      comprobanteEnRevision: comprobanteEnRevision,
                      explicacion: explicacion,
                      partidoLinea: lineaPartidoDetalle(ancla),
                      deportesResumen: _deudas.length > 1
                          ? resumenDeportesLinea(_deudas, l10n, lang)
                          : null,
                      onPayTotal: () => _pagar(esTotal: true),
                      onPayAbono: () => _pagar(esTotal: false),
                      onVerDetallePartido:
                          ancla != null ? () => _verDetalle(ancla) : null,
                    ),
                    if (cuentaConDeuda && _partidosJugados.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      MatchPaySectionHeader(
                        title: l10n.tr('playerMatchHistorySection'),
                      ),
                      const SizedBox(height: 8),
                      PlayerMatchHistoryList(
                        partidos: _partidosJugados,
                        saldosPorPartido: _saldoAnteriorPorPartido,
                        modo: PlayerMatchHistorialModo.cuentaConDeuda,
                        historialSaldo: _historialSaldo,
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
