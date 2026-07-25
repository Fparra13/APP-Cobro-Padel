import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/cuenta_saldo.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/saldo_historico.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/nav_shell_layout.dart';
import '../utils/player_pay_bridge.dart';
import '../widgets/cobro_pago_flow.dart';
import '../widgets/cobro_ver_detalle_sheet.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/player_match_history_tile.dart';
import '../widgets/player_matches_to_close.dart';
import '../widgets/shimmer_loading.dart';

/// Cobros del jugador: una fila/pago por organizador + historial.
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
  List<CuentaSaldo> _cuentas = [];
  double _totalDeudaHome = 0;
  final Map<String, List<SaldoHistorico>> _historialPorOrg = {};
  bool _loading = true;
  bool _hasLoaded = false;
  bool _loadInFlight = false;
  String? _error;
  /// organizadorId en curso de pago (deshabilita CTAs de esa card).
  String? _pagandoOrgId;
  Timer? _reloadDebounce;

  /// Cuentas con deuda viva, mayor monto primero (solo orden, no auto-pago).
  List<CuentaSaldo> get _cuentasConDeuda {
    final list =
        _cuentas.where((c) => c.deuda > 0.005).toList(growable: false);
    return List<CuentaSaldo>.from(list)
      ..sort((a, b) => b.deuda.compareTo(a.deuda));
  }

  bool _cuentaEnRevision(CuentaSaldo cuenta) {
    return deudasDeOrganizador(_deudas, cuenta.organizadorId)
        .any((d) => d.comprobantePendienteValidacion);
  }

  @override
  void initState() {
    super.initState();
    // Home teaser: solo inicia pago si hay una única cuenta con deuda.
    PlayerPayBridge.instance.registerPayTotalHandler(() async {
      if (!_hasLoaded) await _load();
      return _pagarDesdeBridge(esTotal: true);
    });
    PlayerPayBridge.instance.registerPayOtherHandler(() async {
      if (!_hasLoaded) await _load();
      return _pagarDesdeBridge(esTotal: false);
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
      final cuentasFuture = repos.listarMisCuentasSaldo();
      final totalFuture = repos.getMiTotalDeudaHome();
      final partidosJugadosFuture = repos.getMisPartidosJugados(limit: 30);
      final partidoIds = rawDeudas.map((d) => d.partidoId).toSet();
      final partidosJugados = await partidosJugadosFuture;
      partidoIds.addAll(partidosJugados.map((p) => p.partidoId));
      final saldosAnteriores =
          await repos.getMisSaldosAnterioresPartidos(partidoIds);
      final cuentas = await cuentasFuture;
      final totalRpc = await totalFuture;
      final total = totalRpc > 0.005
          ? totalRpc
          : totalDeudaDesdeCuentas(cuentas);

      final conDeuda = cuentas.where((c) => c.deuda > 0.005).toList();
      final historialPorOrg = <String, List<SaldoHistorico>>{};
      if (uid != null) {
        await Future.wait(
          conDeuda.map((c) async {
            try {
              historialPorOrg[c.organizadorId] = await repos.getSaldosByJugador(
                uid,
                organizadorId: c.organizadorId,
              );
            } catch (_) {
              historialPorOrg[c.organizadorId] = const [];
            }
          }),
        );
      }

      final desgloseMap = <int, DesgloseJugador?>{};
      await Future.wait(
        rawDeudas.map((d) async {
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
          _deudas = rawDeudas;
          _partidosJugados = partidosJugados;
          _desglosePorPartido
            ..clear()
            ..addAll(desgloseMap);
          _saldoAnteriorPorPartido
            ..clear()
            ..addAll(saldosAnteriores);
          _cuentas = cuentas;
          _totalDeudaHome = total;
          _historialPorOrg
            ..clear()
            ..addAll(historialPorOrg);
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

  Future<bool> _pagarDesdeBridge({required bool esTotal}) async {
    final cuentas = _cuentasConDeuda;
    if (cuentas.length != 1) return false;
    await _pagar(cuenta: cuentas.first, esTotal: esTotal);
    return true;
  }

  Future<void> _pagar({
    required CuentaSaldo cuenta,
    required bool esTotal,
  }) async {
    if (_pagandoOrgId != null) return;
    final deudasPago = deudasDeOrganizador(_deudas, cuenta.organizadorId);
    if (deudasPago.isEmpty) return;
    setState(() => _pagandoOrgId = cuenta.organizadorId);
    try {
      await CobroPagoFlow.iniciarPagoGlobal(
        context: context,
        organizadorId: cuenta.organizadorId,
        organizadorNombre: cuenta.nombreOrganizador,
        cuenta: cuenta,
        deudas: deudasPago,
        desgloses: _desglosePorPartido,
        saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
        esTotal: esTotal,
        onCompletado: () => _load(silent: true),
      );
    } finally {
      if (mounted) setState(() => _pagandoOrgId = null);
    }
  }

  void _verDetalle(CuentaSaldo cuenta) {
    final deudasOrg = deudasDeOrganizador(_deudas, cuenta.organizadorId);
    final saldo = cuenta.saldoAcumulado;
    final bloqueado =
        deudasOrg.any((d) => d.comprobantePendienteValidacion);
    final ancla = detalleCobroParaVerDetalle(
      deudas: deudasOrg,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
      saldoAcumuladoJugador: saldo,
    );
    if (ancla == null) return;
    CobroVerDetalleSheet.show(
      context,
      detalle: ancla,
      desglose: _desglosePorPartido[ancla.partidoId],
      saldoAnteriorAlPartido: _saldoAnteriorPorPartido[ancla.partidoId],
      saldoAcumuladoJugador: saldo,
      esAnclaCuenta: true,
      organizadorNombre: cuenta.nombreOrganizador,
      historialSaldo: _historialPorOrg[cuenta.organizadorId] ?? const [],
      onPayTotal: bloqueado
          ? null
          : () {
              Navigator.of(context).maybePop();
              _pagar(cuenta: cuenta, esTotal: true);
            },
      onPayAbono: bloqueado
          ? null
          : () {
              Navigator.of(context).maybePop();
              _pagar(cuenta: cuenta, esTotal: false);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cuentasDeuda = _cuentasConDeuda;
    final total = _totalDeudaHome;
    final tieneDeuda = total > 0.005 || cuentasDeuda.isNotEmpty;
    final creditoAlDia = totalCreditoDesdeCuentas(_cuentas);

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
                  if (!tieneDeuda)
                    PlayerCuentaAlDiaCard(
                      saldoAFavor: creditoAlDia,
                    )
                  else ...[
                    PlayerMisCobrosTotalResumen(total: total),
                    const SizedBox(height: 16),
                    for (final cuenta in cuentasDeuda) ...[
                      PlayerCuentaOrganizadorPendienteCard(
                        organizadorNombre: cuenta.nombreOrganizador,
                        fotoUrl: cuenta.fotoUrl,
                        deuda: cuenta.deuda,
                        pagando: _pagandoOrgId == cuenta.organizadorId,
                        comprobanteEnRevision: _cuentaEnRevision(cuenta),
                        onPayTotal: () =>
                            _pagar(cuenta: cuenta, esTotal: true),
                        onPayAbono: () =>
                            _pagar(cuenta: cuenta, esTotal: false),
                        onVerDetalle: () => _verDetalle(cuenta),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_partidosJugados.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      MatchPaySectionHeader(
                        title: l10n.tr('playerMatchHistorySection'),
                      ),
                      const SizedBox(height: 8),
                      PlayerMatchHistoryList(
                        partidos: _partidosJugados,
                        saldosPorPartido: _saldoAnteriorPorPartido,
                        modo: PlayerMatchHistorialModo.cuentaConDeuda,
                        historialSaldo: cuentasDeuda.length == 1
                            ? (_historialPorOrg[
                                    cuentasDeuda.first.organizadorId] ??
                                const [])
                            : const [],
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
