import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/deuda_explicacion.dart';
import '../models/cuenta_saldo.dart';
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

/// Cobros del jugador: cuentas por organizador + historial.
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
  CuentaSaldo? _cuentaFoco;
  List<SaldoHistorico> _historialSaldo = [];
  bool _loading = true;
  bool _hasLoaded = false;
  bool _loadInFlight = false;
  String? _error;
  bool _pagando = false;
  Timer? _reloadDebounce;

  /// Saldo de la cuenta en foco (nunca un wallet global).
  double? get _saldoCuentaFoco => _cuentaFoco?.saldoAcumulado;

  List<DetallePartido> get _deudasCuentaFoco {
    final orgId = _cuentaFoco?.organizadorId;
    if (orgId == null) return const [];
    return deudasDeOrganizador(_deudas, orgId);
  }

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
      final foco = cuentaConMayorDeuda(cuentas);
      final historialSaldo = uid != null && foco != null
          ? await repos.getSaldosByJugador(
              uid,
              organizadorId: foco.organizadorId,
            )
          : <SaldoHistorico>[];
      final deudasFoco = foco == null
          ? <DetallePartido>[]
          : deudasDeOrganizador(rawDeudas, foco.organizadorId);
      final deudas = ordenarCobrosPorAtencion(
        deudasFoco,
        saldosAnterioresPorPartido: saldosAnteriores,
      );
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
          _cuentaFoco = foco;
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
    final deudasPago = _deudasCuentaFoco;
    final saldo = _saldoCuentaFoco;
    if (deudasPago.isEmpty || saldo == null) return;
    setState(() => _pagando = true);
    try {
      await CobroPagoFlow.iniciarPagoGlobal(
        context: context,
        deudas: deudasPago,
        desgloses: _desglosePorPartido,
        saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
        saldoAcumuladoJugador: saldo,
        esTotal: esTotal,
        onCompletado: () => _load(silent: true),
      );
    } finally {
      if (mounted) setState(() => _pagando = false);
    }
  }

  void _verDetalle(DetallePartido detalle) {
    final deudasPago = _deudasCuentaFoco;
    final saldo = _saldoCuentaFoco;
    final bloqueado =
        deudasPago.any((d) => d.comprobantePendienteValidacion);
    final ancla = detalleCobroParaVerDetalle(
      deudas: deudasPago,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
      saldoAcumuladoJugador: saldo,
    );
    CobroVerDetalleSheet.show(
      context,
      detalle: detalle,
      desglose: _desglosePorPartido[detalle.partidoId],
      saldoAnteriorAlPartido: _saldoAnteriorPorPartido[detalle.partidoId],
      saldoAcumuladoJugador: saldo,
      esAnclaCuenta: detalle.partidoId == ancla?.partidoId,
      historialSaldo: _historialSaldo,
      onPayTotal: bloqueado
          ? null
          : () {
              Navigator.of(context).maybePop();
              _pagar(esTotal: true);
            },
      onPayAbono: bloqueado
          ? null
          : () {
              Navigator.of(context).maybePop();
              _pagar(esTotal: false);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;
    final deudasFoco = _deudasCuentaFoco;
    final saldoFoco = _saldoCuentaFoco;
    final visibles = cobrosVisiblesJugador(
      deudas: deudasFoco,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldoAnteriorPorPartido,
      saldoAcumuladoJugador: saldoFoco,
    );
    final explicacion = saldoFoco == null || _cuentaFoco == null
        ? null
        : explicarDeudaJugador(
            saldoAcumulado: saldoFoco,
            historial: _historialSaldo,
            organizadorId: _cuentaFoco!.organizadorId,
          );
    final ancla = visibles.ancla;
    // Hero: total home (sin netear). Pago/explicación: cuenta en foco.
    final total = _totalDeudaHome;
    final cuentaConDeuda = total > 0.005;
    final comprobanteEnRevision =
        deudasFoco.any((d) => d.comprobantePendienteValidacion);
    final mostrarHero = mostrarHeroCobroPendiente(
      totalPendiente: total,
      comprobanteEnRevision: comprobanteEnRevision,
    );
    final cobrosResumen = cobrosParaResumenDeportes(
      ancla: ancla,
      otros: visibles.otros,
    );
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
                  if (!mostrarHero)
                    PlayerCuentaAlDiaCard(
                      saldoAFavor: creditoAlDia,
                    )
                  else ...[
                    PlayerMisCobrosHeroCard(
                      total: total,
                      pagando: _pagando,
                      comprobanteEnRevision: comprobanteEnRevision,
                      explicacion: cuentaConDeuda ? explicacion : null,
                      partidoLinea: lineaPartidoDetalle(ancla),
                      deportesResumen: cobrosResumen.length > 1
                          ? resumenDeportesLinea(cobrosResumen, l10n, lang)
                          : null,
                      onPayTotal: () => _pagar(esTotal: true),
                      onPayAbono: () => _pagar(esTotal: false),
                      onVerDetallePartido: () {
                        final target = ancla ??
                            detalleCobroParaVerDetalle(
                              deudas: deudasFoco,
                              desgloses: _desglosePorPartido,
                              saldosAnterioresPorPartido:
                                  _saldoAnteriorPorPartido,
                              saldoAcumuladoJugador: saldoFoco,
                            );
                        if (target != null) _verDetalle(target);
                      },
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
