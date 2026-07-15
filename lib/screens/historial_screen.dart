import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/offline_status_controller.dart';
import '../domain/deuda_explicacion.dart';
import '../l10n/matchpay_strings.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/jugador.dart';
import '../models/saldo_historico.dart';
import '../offline/player_loader.dart';
import '../offline/offline_snapshot_store.dart';
import '../services/recordatorio_service.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../utils/perfil_foto.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/offline_no_data_panel.dart';

class HistorialScreen extends StatefulWidget {
  final String jugadorKey;

  const HistorialScreen({super.key, required this.jugadorKey});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final _recordatorioService = RecordatorioService();

  Jugador? _jugador;
  List<SaldoHistorico> _historial = [];
  List<DeudaPartidoAnterior> _pendientes = [];
  int _partidosJugados = 0;
  int _partidosPagados = 0;
  double _totalAbonos = 0;
  double _totalCargos = 0;
  _FiltroHistorial _filtro = _FiltroHistorial.todos;
  bool _loading = true;
  bool _offlineEmpty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _offlineEmpty = false;
      });
    }

    final offlineStatus = context.read<OfflineStatusController>();
    final userId = AuthService.instance.currentUser?.id;
    final snapshotStore = userId != null
        ? OfflineSnapshotStore(userId: userId)
        : null;

    try {
      final result = await loadPlayerJugadorFicha(
        repos: context.repos,
        jugadorKey: widget.jugadorKey,
        snapshotStore: snapshotStore,
      );

      if (!mounted) return;

      switch (result.source) {
        case OfflineScreenLoadSource.live:
          offlineStatus.markLive();
          _applyFichaData(result.data!);
        case OfflineScreenLoadSource.offlineCache:
          offlineStatus.markOfflineCached(result.snapshotAt!);
          _applyFichaData(result.data!);
        case OfflineScreenLoadSource.offlineEmpty:
          offlineStatus.markOfflineEmpty();
          setState(() {
            _jugador = null;
            _historial = [];
            _pendientes = [];
            _partidosJugados = 0;
            _partidosPagados = 0;
            _totalAbonos = 0;
            _totalCargos = 0;
            _offlineEmpty = true;
          });
        case OfflineScreenLoadSource.error:
          offlineStatus.markLive();
          setState(() {
            _error = context.userError(result.error!);
          });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFichaData(PlayerJugadorFichaData data) {
    final totalAbonos = data.historial.fold(0.0, (s, h) => s + h.abono);
    final totalCargos =
        data.historial.fold(0.0, (s, h) => s + h.cargoPartido);
    setState(() {
      _jugador = data.jugador;
      _historial = data.historial;
      _pendientes = data.pendientes;
      _partidosJugados = data.partidosJugados;
      _partidosPagados = data.partidosPagados;
      _totalAbonos = totalAbonos;
      _totalCargos = totalCargos;
      _offlineEmpty = false;
      _error = null;
    });
  }

  bool _isReadOnly(BuildContext context) =>
      context.read<OfflineStatusController>().isReadOnly;

  void _showOfflineWriteBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('offlineWriteBlocked'))),
    );
  }

  List<SaldoHistorico> get _historialFiltrado {
    return _historial.where((h) {
      switch (_filtro) {
        case _FiltroHistorial.todos:
          return true;
        case _FiltroHistorial.cargos:
          return h.cargoPartido > 0;
        case _FiltroHistorial.abonos:
          return h.abono > 0;
      }
    }).toList();
  }

  ExplicacionDeudaJugador? get _explicacionDeuda {
    final saldo = _jugador?.saldoAcumulado ?? 0;
    final orgId = AuthService.instance.currentUser?.id;
    return explicarDeudaJugador(
      saldoAcumulado: saldo,
      historial: _historial,
      organizadorId: orgId,
    );
  }

  DeudaPartidoAnterior? _partidoContextoDeuda(ExplicacionDeudaJugador exp) {
    final id = exp.partidoIdContexto;
    if (id == null) return null;
    for (final p in _pendientes) {
      if (p.partidoId == id) return p;
    }
    return null;
  }

  String? _lineaPartidoContexto(ExplicacionDeudaJugador exp) {
    final partido = _partidoContextoDeuda(exp);
    if (partido != null) {
      final lugar = partido.recinto?.trim().isNotEmpty == true
          ? ' · ${partido.recinto}'
          : '';
      return '${formatFecha(partido.fecha)}$lugar';
    }
    final id = exp.partidoIdContexto;
    if (id == null) return null;
    for (final h in _historial) {
      if (h.partidoId == id) {
        return formatFecha(h.fecha);
      }
    }
    return null;
  }

  Map<String, List<SaldoHistorico>> get _historialPorMes {
    final map = <String, List<SaldoHistorico>>{};
    for (final h in _historialFiltrado) {
      final key = '${h.fecha.year}-${h.fecha.month.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(h);
    }
    return map;
  }

  Color _colorDe(String nombre) => JugadorAvatar.colorDe(nombre);

  Future<void> _cambiarFoto() async {
    if (_isReadOnly(context)) {
      _showOfflineWriteBlocked();
      return;
    }
    final jugador = _jugador;
    if (jugador == null) return;

    await editarFotoPerfil(
      context,
      jugador: jugador,
      onDone: _load,
    );
  }

  String _etiquetaMes(String key, BuildContext context) {
    final parts = key.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return '${context.tr('month$month')} $year';
  }

  _MovimientoTipo _tipoDe(SaldoHistorico h) {
    if (h.abono > 0 && h.cargoPartido == 0) return _MovimientoTipo.abono;
    if (h.cargoPartido > 0 && h.abono == 0) return _MovimientoTipo.cargo;
    if (h.abono > 0 && h.cargoPartido > 0) return _MovimientoTipo.mixto;
    return _MovimientoTipo.otro;
  }

  Future<void> _registrarPago() async {
    if (_isReadOnly(context)) {
      _showOfflineWriteBlocked();
      return;
    }
    final jugador = _jugador;
    if (jugador == null || jugador.saldoAcumulado <= 0) return;

    final saldo = jugador.saldoAcumulado;
    final montoCtrl = TextEditingController();
    var pagoTotal = true;

    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (ctx, setModal) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('homeRegisterPaymentsTitle'),
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  jugador.nombre,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          color: Colors.red.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr(
                            'currentDebt',
                            params: {'amount': formatMoney(saldo)},
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(context.tr('homePayFull')),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(context.tr('homePartialPayment')),
                    ),
                  ],
                  selected: {pagoTotal},
                  onSelectionChanged: (s) {
                    setModal(() {
                      pagoTotal = s.first;
                      if (pagoTotal) montoCtrl.clear();
                    });
                  },
                ),
                if (!pagoTotal) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: montoCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: context.tr('homePartialAmountLabel'),
                      prefixIcon: const Icon(Icons.payments_outlined),
                      helperText: context.tr('homePartialAmountHelper'),
                      suffixText: context.tr(
                        'homeOwesSuffix',
                        params: {'amount': formatMoney(saldo)},
                      ),
                    ),
                    autofocus: true,
                    inputFormatters: moneyInputFormatters,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    pagoTotal
                        ? context.tr(
                            'confirmAmount',
                            params: {'amount': formatMoney(saldo)},
                          )
                        : context.tr('confirmPartialPayment'),
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );

    if (confirmado != true || !mounted) return;

    final monto = pagoTotal
        ? saldo
        : roundMoney(parseMoney(montoCtrl.text)).toDouble();

    if (monto <= 0) {
      _mostrarSnack(context.tr('errorAmountGreaterThanZero'), esError: true);
      return;
    }

    final concepto = monto > saldo
        ? context.tr('paymentConceptWithCredit')
        : pagoTotal
            ? context.tr('paymentConceptFull')
            : context.tr('paymentConceptPartial');

    await context.repos.registrarAbono(
      jugadorId: jugador.keyId,
      monto: monto,
      concepto: concepto,
    );

    if (mounted) {
      final excedente = monto > saldo ? monto - saldo : 0.0;
      final msg = excedente > 0
          ? context.tr(
              'snackPartialWithCredit',
              params: {
                'amount': formatMoney(monto),
                'credit': formatMoney(excedente),
              },
            )
          : monto >= saldo
              ? context.tr('snackDebtClearedShort')
              : context.tr(
                  'snackPartialRemainingShort',
                  params: {
                    'amount': formatMoney(monto),
                    'remaining': formatMoney(saldo - monto),
                  },
                );
      _mostrarSnack(msg);
      _load();
    }
  }

  Future<void> _enviarNotificacionPush() async {
    if (_isReadOnly(context)) {
      _showOfflineWriteBlocked();
      return;
    }
    final jugador = _jugador;
    if (jugador == null) return;

    if (jugador.contactEmail == null) {
      _mostrarSnack(context.tr('playerNoEmail'), esError: true);
      return;
    }

    try {
      await _recordatorioService.enviarIndividual(
        jugador: jugador,
        saldo: jugador.saldoAcumulado,
      );
      if (mounted) {
        _mostrarSnack(
          context.tr('pushSentTo', params: {'name': jugador.nombre}),
        );
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnack(
          context.tr('errorGeneric'),
          esError: true,
        );
      }
    }
  }

  void _mostrarSnack(String msg, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: esError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jugador = _jugador;
    final nombre = jugador?.nombre ?? '';
    final saldo = jugador?.saldoAcumulado ?? 0;
    final alDia = saldo <= 0;
    final conFavor = saldo < 0;
    final color = _colorDe(nombre);
    final mesesOrdenados = _historialPorMes.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('homePlayerSheetTitle')),
      ),
      body: SafeArea(
        top: false,
        child: _loading && _jugador == null && !_offlineEmpty && _error == null
            ? const Center(child: CircularProgressIndicator())
            : _offlineEmpty
                ? const OfflineNoDataPanel()
                : _error != null && _jugador == null
                    ? _buildErrorState()
                    : RefreshIndicator(
                    onRefresh: () => _load(silent: true),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                  SliverToBoxAdapter(child: _buildFicha(jugador, color, alDia, conFavor, saldo)),
                  SliverToBoxAdapter(child: _buildEstadisticas(alDia, conFavor)),
                  if (_explicacionDeuda != null)
                    SliverToBoxAdapter(child: _buildExplicacionDeuda()),
                  SliverToBoxAdapter(child: _buildAcciones(alDia, conFavor)),
                  SliverToBoxAdapter(child: _buildFiltros()),
                  if (_historialFiltrado.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyHistorial(),
                    )
                  else
                    ...mesesOrdenados.expand((mesKey) {
                      final items = _historialPorMes[mesKey] ?? const [];
                      return [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              _etiquetaMes(mesKey, context),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _buildMovimientoCard(
                              items[i],
                              esUltimo: i == items.length - 1,
                            ),
                            childCount: items.length,
                          ),
                        ),
                      ];
                    }),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildErrorState() {
    return FriendlyErrorPanel(
      message: _error ?? context.tr('playerSheetLoadFailed'),
      onRetry: _load,
    );
  }

  Widget _buildFicha(
    Jugador? jugador,
    Color color,
    bool alDia,
    bool conFavor,
    double saldo,
  ) {
    final nombre = jugador?.nombre ?? '';
    final readOnly = context.watch<OfflineStatusController>().isReadOnly;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: readOnly ? null : _cambiarFoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      JugadorAvatar(
                        nombre: nombre,
                        fotoPath: jugador?.fotoPath,
                        fotoUrl: jugador?.fotoUrl,
                        size: 72,
                        borderRadius: 18,
                        showBorder: true,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (jugador?.activo ?? false)
                            _ChipFicha(
                              icon: Icons.star_rounded,
                              label: context.tr('statusRegular'),
                              color: Colors.amber.shade300,
                            ),
                          _ChipFicha(
                            icon: conFavor
                                ? Icons.savings_rounded
                                : alDia
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                            label: conFavor
                                ? context.tr('statusCredit')
                                : alDia
                                    ? context.tr('statusUpToDate')
                                    : context.tr('withDebt'),
                            color: Colors.white,
                          ),
                          if (jugador?.contactEmail case final email?)
                            _ChipFicha(
                              icon: Icons.email_outlined,
                              label: email,
                              color: Colors.white,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  conFavor
                      ? context.tr('statusCredit')
                      : alDia
                          ? context.tr('currentBalance')
                          : context.tr('pendingDebtLabel'),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  conFavor ? formatMoney(-saldo) : formatMoney(saldo),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: colorSaldo(saldo),
                  ),
                ),
                if (!alDia && _explicacionDeuda?.subtituloKey != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      _explicacionDeuda!.subtituloKey!,
                      params: _explicacionDeuda!.subtituloParams,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticas(bool alDia, bool conFavor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: context.readSettings().sport.icon,
              label: context.tr('tabMatches'),
              value: '$_partidosJugados',
              subtitulo: alDia
                  ? context.tr(
                      'paidCountLabel',
                      params: {'count': '$_partidosPagados'},
                    )
                  : context.tr('playerDebtOnAccount'),
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.arrow_upward_rounded,
              label: context.tr('movementCharge'),
              value: formatMoney(_totalCargos),
              subtitulo: context.tr('totalGenerated'),
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.arrow_downward_rounded,
              label: context.tr('filterAbonos'),
              value: formatMoney(_totalAbonos),
              subtitulo: conFavor
                  ? context.tr('creditAvailable')
                  : alDia
                      ? context.tr('statusUpToDate')
                      : context.tr('paidLabel'),
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplicacionDeuda() {
    final exp = _explicacionDeuda;
    if (exp == null) return const SizedBox.shrink();

    final partidoLinea = _lineaPartidoContexto(exp);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        elevation: 0,
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.orange.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calculate_rounded,
                      color: Colors.orange.shade800, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr(
                        'deudaExplainTitle',
                        params: {'amount': formatMoney(exp.deudaActual)},
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              if (partidoLinea != null) ...[
                const SizedBox(height: 8),
                Text(
                  partidoLinea,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ...exp.lineas.map((linea) {
                final montoTxt = linea.esResta
                    ? '−${formatMoney(linea.monto)}'
                    : formatMoney(linea.monto);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr(linea.labelKey),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                      Text(
                        montoTxt,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              Divider(color: Colors.orange.shade200, height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('deudaExplainCurrentDebt'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                  Text(
                    formatMoney(exp.deudaActual),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcciones(bool alDia, bool conFavor) {
    if (_isReadOnly(context)) return const SizedBox.shrink();

    final tieneEmail = _jugador?.contactEmail != null;
    final puedePagar = !alDia && !conFavor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          if (puedePagar)
            Expanded(
              child: FilledButton.icon(
                onPressed: _registrarPago,
                icon: const Icon(Icons.payments_rounded),
                label: Text(context.tr('homeRegisterPaymentsTitle')),
              ),
            ),
          if (puedePagar && tieneEmail) const SizedBox(width: 8),
          if (tieneEmail)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enviarNotificacionPush,
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(
                  puedePagar
                      ? context.tr('remind')
                      : context.tr('notify'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('movementHistory'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('movementsAutoHint').replaceAll('\n', ' '),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _FiltroHistorial.values.map((f) {
                final selected = _filtro == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(context.tr(f.labelKey)),
                    selected: selected,
                    onSelected: (_) => setState(() => _filtro = f),
                    avatar: Icon(
                      f.icono,
                      size: 18,
                      color: selected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistorial() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            _filtro == _FiltroHistorial.todos
                ? context.tr('noMovementsYet')
                : context.tr('noMovementsOfType'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('movementsAutoHint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _etiquetaTipo(_MovimientoTipo tipo) {
    return switch (tipo) {
      _MovimientoTipo.abono => context.tr('movementTypePayment'),
      _MovimientoTipo.cargo => context.tr('movementTypeCharge'),
      _MovimientoTipo.mixto => context.tr('movementTypeBoth'),
      _MovimientoTipo.otro => context.tr('historicalMovement'),
    };
  }

  String _etiquetaSaldoFinal(double saldo) {
    if (saldo > 0.005) return context.tr('movementBalanceDebt');
    if (saldo < -0.005) return context.tr('movementBalanceCredit');
    return context.tr('movementBalanceZero');
  }

  String _montoConSigno(double monto, {required bool esCargo}) {
    final abs = formatMoney(monto.abs());
    if (monto.abs() < 0.005) return formatMoney(0);
    return esCargo ? '+$abs' : '−$abs';
  }

  Widget _buildMovimientoCard(SaldoHistorico h, {required bool esUltimo}) {
    final tipo = _tipoDe(h);
    final fecha = formatMesDiaHora(h.fecha);
    final titulo = context.l10n.translateConcept(h.concepto);
    final neto = h.cargoPartido - h.abono;
    final montoPrincipal = switch (tipo) {
      _MovimientoTipo.cargo => _montoConSigno(h.cargoPartido, esCargo: true),
      _MovimientoTipo.abono => _montoConSigno(h.abono, esCargo: false),
      _MovimientoTipo.mixto => _montoConSigno(neto.abs(), esCargo: neto >= 0),
      _MovimientoTipo.otro => formatMoney(h.saldoNuevo - h.saldoAnterior),
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, esUltimo ? 4 : 0),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: tipo.color.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tipo.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(tipo.icono, color: tipo.color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tipo.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _etiquetaTipo(tipo),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tipo.color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fecha,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    montoPrincipal,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: tipo.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    if (h.saldoAnterior.abs() > 0.005)
                      _MovimientoLinea(
                        label: h.saldoAnterior < 0
                            ? context.tr('movementCreditBefore')
                            : context.tr('movementOwedBefore'),
                        value: formatMoney(h.saldoAnterior.abs()),
                      ),
                    if (h.cargoPartido > 0.005)
                      _MovimientoLinea(
                        label: context.tr('movementMatchCharge'),
                        value: _montoConSigno(h.cargoPartido, esCargo: true),
                        valueColor: Colors.red.shade700,
                      ),
                    if (h.abono > 0.005)
                      _MovimientoLinea(
                        label: context.tr('movementPaidAmount'),
                        value: _montoConSigno(h.abono, esCargo: false),
                        valueColor: Colors.green.shade700,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Divider(height: 1, color: Colors.grey.shade300),
                    ),
                    _MovimientoLinea(
                      label: _etiquetaSaldoFinal(h.saldoNuevo),
                      value: formatMoney(
                        h.saldoNuevo.abs() < 0.005 ? 0 : h.saldoNuevo.abs(),
                      ),
                      valueColor: colorSaldo(h.saldoNuevo),
                      enfatizado: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FiltroHistorial {
  todos('all', Icons.list_alt_rounded),
  cargos('filterCharges', Icons.receipt_long_rounded),
  abonos('filterPayments', Icons.savings_rounded);

  final String labelKey;
  final IconData icono;

  const _FiltroHistorial(this.labelKey, this.icono);
}

enum _MovimientoTipo {
  abono(Icons.savings_rounded, Color(0xFF2E7D32)),
  cargo(Icons.receipt_long_rounded, Color(0xFFC62828)),
  mixto(Icons.swap_horiz_rounded, Color(0xFFEF6C00)),
  otro(Icons.receipt_rounded, Color(0xFF546E7A));

  final IconData icono;
  final Color color;

  const _MovimientoTipo(this.icono, this.color);
}

class _ChipFicha extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ChipFicha({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitulo;
  final MaterialColor color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitulo,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color.shade700),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.shade800),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color.shade900,
            ),
          ),
          Text(
            subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: color.shade700),
          ),
        ],
      ),
    );
  }
}

class _MovimientoLinea extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool enfatizado;

  const _MovimientoLinea({
    required this.label,
    required this.value,
    this.valueColor,
    this.enfatizado = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: enfatizado ? 13 : 12,
      fontWeight: enfatizado ? FontWeight.bold : FontWeight.w500,
      color: enfatizado ? Colors.grey.shade900 : Colors.grey.shade700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value,
            style: style.copyWith(
              color: valueColor ?? style.color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
