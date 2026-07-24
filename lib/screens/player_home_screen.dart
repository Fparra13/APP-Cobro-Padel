import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/offline_status_controller.dart';
import '../core/organizer_nudge_service.dart';
import '../utils/organizer_subscription_flow.dart';
import '../core/sport_theme.dart';
import '../models/convocatoria_jugador.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/estadisticas_jugador.dart';
import '../models/jugador.dart';
import '../models/cuenta_saldo.dart';
import '../models/mi_convocatoria.dart';
import '../repositories/partido_repository.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/formatters.dart';
import '../utils/partido_cancelado_popup_flow.dart';
import '../widgets/player_matches_to_close.dart';
import '../widgets/cobro_ver_detalle_sheet.dart';
import '../widgets/convocatoria_avatar_strip.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/mis_invitaciones_panel.dart';
import '../widgets/convocatoria_respuesta_obligatoria_card.dart';
import '../widgets/offline_no_data_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/kloovi_brand.dart';
import '../widgets/partido_estado_publico.dart';
import '../widgets/player_match_history_tile.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../services/notification_service.dart';
import '../domain/deuda_explicacion.dart';
import '../domain/estado_partido_publico.dart';
import '../domain/player_invite_response.dart';
import '../models/saldo_historico.dart';
import '../offline/player_loader.dart';
import '../offline/offline_snapshot_store.dart';
import '../offline/network_errors.dart';
import '../utils/app_mode_pending.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../utils/perfil_foto.dart';
import '../widgets/app_mode_switch_button.dart';
import '../widgets/unirse_grupo_sheet.dart';
import 'responder_convocatoria_screen.dart';

/// Home jugador: funcionalidad intacta, estética premium y deportiva.
class PlayerHomeScreen extends StatefulWidget {
  final VoidCallback? onOpenMisCobros;
  final VoidCallback? onOpenPartidos;
  final VoidCallback? onPayTotalFromHome;
  final VoidCallback? onPayOtherFromHome;

  const PlayerHomeScreen({
    super.key,
    this.onOpenMisCobros,
    this.onOpenPartidos,
    this.onPayTotalFromHome,
    this.onPayOtherFromHome,
  });

  @override
  State<PlayerHomeScreen> createState() => _PlayerHomeScreenState();
}

class _PlayerHomeScreenState extends State<PlayerHomeScreen> {
  List<MiConvocatoria> _todas = [];
  List<DetallePartido> _deudas = [];
  List<DetallePartido> _partidosJugados = [];
  List<SaldoHistorico> _historialSaldo = [];
  Map<int, double> _saldosPorPartido = {};
  final Map<int, DesgloseJugador?> _desglosePorPartido = {};
  List<CuentaSaldo> _cuentasSaldo = [];
  double _totalDeudaHome = 0;
  Jugador? _perfil;
  EstadisticasJugador? _misStats;
  MisInvitacionesResumen _invitacionesResumen = MisInvitacionesResumen.empty;
  bool _loading = true;
  bool _primeraCarga = true;
  bool _showOrganizerNudge = false;
  int _organizerPendingCount = 0;
  bool _offlineEmpty = false;
  ConvocatoriaCompleta? _heroConvocatoriaCompleta;
  Timer? _reloadDebounce;
  String? _error;
  bool _loadingData = false;
  bool _pendingSilentReload = false;

  List<MiConvocatoria> get _invitacionesTitular =>
      _todas.where((c) => !c.entry.esSuplente).toList();

  int get _invitesRecibidas => _invitacionesTitular.length;

  int get _invitesConfirmadas =>
      _invitacionesTitular.where((c) => c.estaConfirmado).length;

  List<MiConvocatoria> get _pendientes =>
      _todas.where((c) => c.requiereRespuesta).toList();

  List<MiConvocatoria> get _proximos =>
      _todas.where((c) => c.estaConfirmado && c.esProximo).toList();

  /// Elemento principal: primero lo que requiere acción, luego el próximo partido.
  MiConvocatoria? get _heroConvocatoria {
    if (_pendientes.isNotEmpty) return _pendientes.first;
    if (_proximos.isNotEmpty) return _proximos.first;
    return null;
  }

  List<MiConvocatoria> get _otrasPendientes {
    final hero = _heroConvocatoria;
    if (hero == null) return _pendientes;
    return _pendientes
        .where((c) => c.entry.partidoId != hero.entry.partidoId)
        .toList();
  }

  List<MiConvocatoria> get _otrosProximos {
    final hero = _heroConvocatoria;
    if (hero == null) return _proximos;
    return _proximos
        .where((c) => c.entry.partidoId != hero.entry.partidoId)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    AppRepositories.dataRevision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    AppRepositories.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 900), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (silent && _loadingData) {
      _pendingSilentReload = true;
      return;
    }
    _loadingData = true;

    if (!silent && _primeraCarga && mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _offlineEmpty = false;
      });
    } else if (!silent && mounted) {
      setState(() {
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
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final organizerPendingFuture = AuthService.instance.isOrganizer
          ? _loadOrganizerPendingCount(repos)
          : Future<int>.value(0);

      final result = await loadPlayerHome(
        repos: repos,
        snapshotStore: snapshotStore,
      );

      if (!mounted) return;

      switch (result.source) {
        case OfflineScreenLoadSource.live:
          offlineStatus.markLive();
          await _applyPlayerHomeData(
            result.data!,
            organizerPendingFuture: organizerPendingFuture,
            fromLive: true,
          );
        case OfflineScreenLoadSource.offlineCache:
          offlineStatus.markOfflineCached(result.snapshotAt!);
          await _applyPlayerHomeData(
            result.data!,
            organizerPendingFuture: organizerPendingFuture,
            fromLive: false,
          );
        case OfflineScreenLoadSource.offlineEmpty:
          offlineStatus.markOfflineEmpty();
          setState(() {
            _todas = [];
            _deudas = [];
            _partidosJugados = [];
            _historialSaldo = [];
            _saldosPorPartido = {};
            _desglosePorPartido.clear();
            _cuentasSaldo = [];
            _totalDeudaHome = 0;
            _perfil = null;
            _misStats = null;
            _invitacionesResumen = MisInvitacionesResumen.empty;
            _heroConvocatoriaCompleta = null;
            _showOrganizerNudge = false;
            _organizerPendingCount = 0;
            _offlineEmpty = true;
            _primeraCarga = false;
          });
        case OfflineScreenLoadSource.error:
          offlineStatus.markLive();
          final network = isNetworkError(result.error!);
          final hasVisibleData =
              _todas.isNotEmpty || _perfil != null || _deudas.isNotEmpty;
          if (network && (silent || hasVisibleData)) {
            if (_error != null) {
              setState(() => _error = null);
            }
            break;
          }
          setState(() {
            _error = context.userError(result.error!);
            _primeraCarga = false;
          });
      }
    } finally {
      _loadingData = false;
      if (mounted) setState(() => _loading = false);
      if (_pendingSilentReload && mounted) {
        _pendingSilentReload = false;
        unawaited(_load(silent: true));
      }
    }
  }

  Future<void> _applyPlayerHomeData(
    PlayerHomeData data, {
    required Future<int> organizerPendingFuture,
    required bool fromLive,
  }) async {
    final todas = data.convocatorias;
    final deudas = data.deudas;
    final showNudge = await OrganizerNudgeService.shouldShowHomeCard(
      partidosJugados: data.partidosJugados.length,
      invitesRecibidas: todas.where((c) => !c.entry.esSuplente).length,
    );

    if (!mounted) return;

    setState(() {
      _todas = todas;
      _deudas = deudas;
      _partidosJugados = data.partidosJugados;
      _historialSaldo = data.historialSaldo;
      _saldosPorPartido = data.saldosPorPartido;
      _desglosePorPartido.clear();
      _cuentasSaldo = data.cuentasSaldo;
      _totalDeudaHome = data.totalDeudaHome ??
          totalDeudaDesdeCuentas(data.cuentasSaldo);
      _perfil = data.perfil;
      _misStats = data.misStats;
      _invitacionesResumen = data.invitacionesResumen;
      _showOrganizerNudge = showNudge;
      _offlineEmpty = false;
      _error = null;
      _primeraCarga = false;
    });

    // Badge organizador: no bloquea el primer paint del home jugador.
    unawaited(organizerPendingFuture.then((count) {
      if (mounted) setState(() => _organizerPendingCount = count);
    }));

    if (!fromLive) return;

    unawaited(_cargarDesgloses(deudas));
    unawaited(_cargarHeroConvocatoria(_heroConvocatoria));
    unawaited(
      ConvocatoriaListaEsperaService().sincronizarPartidos(
        todas.map((c) => c.partido.id).whereType<int>(),
      ),
    );
    unawaited(PartidoCanceladoPopupFlow.mostrarPendientesEnHome(context));
  }

  /// Solo [read]: nunca llamar [watch] desde callbacks (p. ej. Ver detalle).
  bool get _readOnly => context.read<OfflineStatusController>().isReadOnly;

  void _showOfflineWriteBlocked() {
    NotificationService.instance.showInAppSnack(
      context.l10n.tr('offlineWriteBlocked'),
    );
  }

  Future<void> _unirseAGrupo() async {
    if (_readOnly) {
      _showOfflineWriteBlocked();
      return;
    }
    final result = await UnirseGrupoSheet.show(context);
    if (!mounted || result == null) return;
    final l10n = context.l10n;
    NotificationService.instance.showInAppSnack(
      result.yaEstaba
          ? l10n.tr(
              'groupCodeJoinAlready',
              params: {'name': result.nombre},
            )
          : l10n.tr(
              'groupCodeJoinSuccess',
              params: {'name': result.nombre},
            ),
    );
    await UnirseGrupoSheet.maybeShowCuentaAdicionalInfo(context, result);
    if (!mounted) return;
    await _load(silent: true);
  }

  Future<int> _loadOrganizerPendingCount(AppRepositories repos) async {
    try {
      final results = await Future.wait([
        repos.getConvocatoriasActivas(),
        repos.getPartidosJugadosRecientesResumen(limit: 8),
        repos.isCloud
            ? repos.getPagosPorValidar()
            : Future<List<DetallePartido>>.value([]),
      ]);
      return organizerModePendingCount(
        convocatorias: results[0] as List<ConvocatoriaCompleta>,
        partidosJugadosRecientes: results[1] as List<PartidoCompleto>,
        pagosPorValidar: results[2] as List<DetallePartido>,
      );
    } catch (_) {
      return 0;
    }
  }

  Future<void> _cargarHeroConvocatoria(MiConvocatoria? hero) async {
    if (hero?.partido.id == null) {
      if (mounted) setState(() => _heroConvocatoriaCompleta = null);
      return;
    }
    try {
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final partidoId = hero!.partido.id!;
      // Player Home es vista de invitado: el roster completo viene del RPC
      // (SECURITY DEFINER). No usar getConvocatoriaCompleta por rol global
      // isOrganizer — RLS solo devolvería la fila propia y ocultaría
      // confirmaciones de otros (p. ej. organizador-player ajeno).
      final conv = await repos.getConvocatoriaRosterParaJugador(
        partidoId: partidoId,
        partido: hero.partido,
      );
      if (mounted) setState(() => _heroConvocatoriaCompleta = conv);
    } catch (_) {
      if (mounted) setState(() => _heroConvocatoriaCompleta = null);
    }
  }

  int get _partidosEsteMes {
    final now = DateTime.now();
    var count = _partidosJugados.where((p) {
      final f = p.fechaPartido;
      return f != null && f.year == now.year && f.month == now.month;
    }).length;
    count += _proximos.where((c) {
      final f = c.partido.fecha;
      return f.year == now.year && f.month == now.month;
    }).length;
    return count;
  }

  int get _semanasJugando {
    final fechas = <DateTime>[
      ..._partidosJugados.map((p) => p.fechaPartido).whereType<DateTime>(),
      ..._proximos.map((c) => c.partido.fecha),
    ];
    if (fechas.isEmpty) return 0;
    final semanas = fechas.map((f) {
      final lunes = f.subtract(Duration(days: f.weekday - 1));
      return DateTime(lunes.year, lunes.month, lunes.day);
    }).toSet();
    return semanas.length;
  }

  String _dynamicHeadline(
    MatchPayStrings l10n,
    double deudaTotal,
    MiConvocatoria? hero,
  ) {
    if (_pendientes.isNotEmpty) {
      return l10n.tr('playerContextPendingInvite');
    }
    if (hero != null && hero.estaConfirmado) {
      final emoji = SportThemeConfig.paletteFor(hero.partido.sportType).emoji;
      final fecha = hero.partido.fecha;
      if (esMismoDia(fecha, DateTime.now())) {
        return l10n.tr(
          'playerContextPlayTodayAt',
          params: {'emoji': emoji, 'time': formatHora(fecha)},
        );
      }
      final diff = fecha.difference(DateTime.now());
      if (!diff.isNegative) {
        return l10n.tr(
          'playerContextNextIn',
          params: {'emoji': emoji, 'when': formatEnCuanto(fecha)},
        );
      }
      return l10n.tr(
        'playerContextMatchAt',
        params: {'emoji': emoji, 'time': formatHora(fecha)},
      );
    }
    if (deudaTotal > 0.005) {
      return '';
    }
    final mes = _partidosEsteMes;
    if (mes >= 3) {
      return l10n.tr(
        'playerContextMatchesMonth',
        params: {'count': '$mes'},
      );
    }
    final semanas = _semanasJugando;
    if (semanas >= 2) {
      return l10n.tr(
        'playerContextWeeksStreak',
        params: {'weeks': '$semanas'},
      );
    }
    return l10n.tr('playerWelcomeBack');
  }

  Future<void> _cargarDesgloses(List<DetallePartido> deudas) async {
    if (deudas.isEmpty || !mounted) return;
    try {
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final entries = await Future.wait(
        deudas.map((d) async {
          try {
            return MapEntry(
              d.partidoId,
              await repos.getMiDesglosePartido(d.partidoId),
            );
          } catch (_) {
            return MapEntry<int, DesgloseJugador?>(d.partidoId, null);
          }
        }),
      );
      if (mounted) {
        setState(() {
          for (final e in entries) {
            _desglosePorPartido[e.key] = e.value;
          }
        });
      }
    } catch (_) {}
  }

  String get _nombreCorto {
    final nombre = _perfil?.nombre ?? context.l10n.tr('playerDefaultName');
    return nombre.split(' ').first;
  }

  Future<void> _switchToOrganizer() async {
    await context.switchAppUiMode(AppUiMode.organizer);
  }

  Future<void> _onBecomeOrganizerTap() async {
    await openOrganizerSubscriptionFlow(context);
  }

  /// Cuentas con deuda viva (orden por monto ↓ solo para display).
  List<CuentaSaldo> get _cuentasConDeuda {
    final list =
        _cuentasSaldo.where((c) => c.deuda > 0.005).toList(growable: false);
    return List<CuentaSaldo>.from(list)
      ..sort((a, b) => b.deuda.compareTo(a.deuda));
  }

  /// Solo si hay exactamente una cuenta con deuda (pago directo desde Home).
  CuentaSaldo? get _cuentaUnicaPendiente {
    final cuentas = _cuentasConDeuda;
    return cuentas.length == 1 ? cuentas.first : null;
  }

  double? get _saldoCuentaUnica => _cuentaUnicaPendiente?.saldoAcumulado;

  List<DetallePartido> get _deudasCuentaUnica {
    final orgId = _cuentaUnicaPendiente?.organizadorId;
    if (orgId == null) return const [];
    return deudasDeOrganizador(_deudas, orgId);
  }

  List<SaldoHistorico> get _historialCuentaUnica {
    final orgId = _cuentaUnicaPendiente?.organizadorId;
    if (orgId == null) return const [];
    return _historialSaldo
        .where((h) => h.organizadorId == orgId)
        .toList(growable: false);
  }

  ExplicacionDeudaJugador? get _explicacionDeuda {
    final cuenta = _cuentaUnicaPendiente;
    final saldo = cuenta?.saldoAcumulado;
    if (cuenta == null || saldo == null) return null;
    return explicarDeudaJugador(
      saldoAcumulado: saldo,
      historial: _historialCuentaUnica,
      organizadorId: cuenta.organizadorId,
    );
  }

  void _abrirMisCobros() {
    widget.onOpenMisCobros?.call();
  }

  void _pagarTotalDesdeHomeTeaser() {
    // Multi-org: no elegir cuenta; ir a Mis pendientes.
    if (_cuentasConDeuda.length > 1) {
      _abrirMisCobros();
      return;
    }
    widget.onPayTotalFromHome?.call();
  }

  void _pagarOtroDesdeHomeTeaser() {
    if (_cuentasConDeuda.length > 1) {
      _abrirMisCobros();
      return;
    }
    widget.onPayOtherFromHome?.call();
  }

  void _verDetalleCobroDesdeHome() {
    if (_cuentasConDeuda.length > 1) {
      _abrirMisCobros();
      return;
    }
    final deudasUnica = _deudasCuentaUnica;
    final saldo = _saldoCuentaUnica;
    final detalle = detalleCobroParaVerDetalle(
      deudas: deudasUnica,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldosPorPartido,
      saldoAcumuladoJugador: saldo,
    );
    if (detalle == null) {
      _abrirMisCobros();
      return;
    }
    final bloqueado =
        deudasUnica.any((d) => d.comprobantePendienteValidacion);
    final ancla = cobrosVisiblesJugador(
      deudas: deudasUnica,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldosPorPartido,
      saldoAcumuladoJugador: saldo,
    ).ancla;
    CobroVerDetalleSheet.show(
      context,
      detalle: detalle,
      desglose: _desglosePorPartido[detalle.partidoId],
      saldoAnteriorAlPartido: _saldosPorPartido[detalle.partidoId],
      saldoAcumuladoJugador: saldo,
      esAnclaCuenta: ancla?.partidoId == detalle.partidoId || ancla == null,
      historialSaldo: _historialCuentaUnica,
      onPayTotal: bloqueado || _readOnly
          ? null
          : () {
              Navigator.of(context).maybePop();
              widget.onPayTotalFromHome?.call();
            },
      onPayAbono: bloqueado || _readOnly
          ? null
          : () {
              Navigator.of(context).maybePop();
              widget.onPayOtherFromHome?.call();
            },
    );
  }

  void _openHistorial() {
    widget.onOpenPartidos?.call();
  }

  Future<void> _cambiarFoto() async {
    if (_readOnly) {
      _showOfflineWriteBlocked();
      return;
    }
    final perfil = _perfil;
    if (perfil == null) return;
    await editarFotoPerfil(
      context,
      jugador: perfil,
      onDone: () {
        if (mounted) _load(silent: true);
      },
    );
  }

  Future<void> _openConvocatoria(MiConvocatoria c) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => ResponderConvocatoriaScreen(
          partidoId: c.entry.partidoId,
          convocatoria: c,
        ),
      ),
    );
    if (mounted) _load();
  }

  bool get _hasActivityData {
    if (_partidosJugados.isNotEmpty) return true;
    if (_misStats != null && _misStats!.partidosJugados > 0) return true;
    if (_semanasJugando >= 2) return true;
    return _invitesRecibidas > 0 || _invitesConfirmadas > 0;
  }

  ({String titleKey, String bodyKey}) _organizerEmpathyCopy() {
    final now = DateTime.now();
    final playedRecently = _partidosJugados.any((p) {
      final f = p.fechaPartido;
      return f != null && now.difference(f).inDays <= 7;
    });
    if (playedRecently) {
      return (
        titleKey: 'organizerEmpathyTitleRecentMatch',
        bodyKey: 'organizerEmpathyBodyRecentMatch',
      );
    }

    final recintos = _todas
        .map((c) => c.partido.recinto?.trim())
        .whereType<String>()
        .where((r) => r.isNotEmpty)
        .toSet();
    if (recintos.length >= 2) {
      return (
        titleKey: 'organizerEmpathyTitleOtherGroup',
        bodyKey: 'organizerEmpathyBodyOtherGroup',
      );
    }

    if ((_partidosJugados.length + _invitesRecibidas) % 2 == 0) {
      return (
        titleKey: 'organizerEmpathyTitleNextTime',
        bodyKey: 'organizerEmpathyBodyNextTime',
      );
    }

    return (
      titleKey: 'organizerEmpathyTitleSimple',
      bodyKey: 'organizerEmpathyBodySimple',
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = context.watch<OfflineStatusController>().isReadOnly;
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final esAdmin = AuthService.instance.isOrganizer;
    final tieneGrupoActivo = _cuentasSaldo.any((c) => c.activo);
    // Home: unirse solo si aún no pertenece a ningún grupo.
    // (Más grupos: desde Configuración.)
    final mostrarUnirseGrupo = !esAdmin && !tieneGrupoActivo;
    final hero = _heroConvocatoria;
    // Home: solo suma deudas > 0 (nunca perfil.saldoAcumulado / neteo).
    final deudaTotal = _totalDeudaHome > 0.005
        ? _totalDeudaHome
        : totalDeudaDesdeCuentas(_cuentasSaldo);
    final alDia = deudaTotal <= 0.005;
    final explicacion = _explicacionDeuda;
    final empathy = _organizerEmpathyCopy();
    final headline = _dynamicHeadline(l10n, deudaTotal, hero);
    final cuentasDeuda = _cuentasConDeuda;
    final multiOrgPendiente = cuentasDeuda.length > 1;
    final deudasTeaser = multiOrgPendiente
        ? _deudas
        : _deudasCuentaUnica;
    final saldoTeaser = multiOrgPendiente ? null : _saldoCuentaUnica;
    final comprobanteEnRevision =
        deudasTeaser.any((d) => d.comprobantePendienteValidacion);
    final cobrosVisibles = cobrosVisiblesJugador(
      deudas: deudasTeaser,
      desgloses: _desglosePorPartido,
      saldosAnterioresPorPartido: _saldosPorPartido,
      saldoAcumuladoJugador: saldoTeaser,
    );
    final encuentrosPendientesCount =
        (cobrosVisibles.ancla != null ? 1 : 0) + cobrosVisibles.otros.length;
    final partidoLineaCobro = multiOrgPendiente
        ? null
        : lineaPartidoDetalle(cobrosVisibles.ancla);

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      body: _loading && _primeraCarga
          ? const PlayerHomeShimmer()
          : _offlineEmpty
              ? const OfflineNoDataPanel()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: MatchPayTokens.surfaceBase,
                      elevation: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              InkWell(
                                onTap: readOnly ? null : _cambiarFoto,
                                borderRadius: BorderRadius.circular(24),
                                child: Stack(
                                  children: [
                                    JugadorAvatar(
                                      nombre:
                                          _perfil?.nombre ?? _nombreCorto,
                                      fotoUrl: _perfil?.fotoUrl,
                                      fotoPath: _perfil?.fotoPath,
                                      size: 48,
                                      borderRadius: 24,
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: MatchPayTokens.ink,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: MatchPayTokens.surfaceBase,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: KlooviHomeBrand(
                                    forOrganizer: false,
                                    wordmarkHeight: 34,
                                    maxWidth: 180,
                                  ),
                                ),
                              ),
                              if (esAdmin)
                                AppModeSwitchButton(
                                  targetMode: AppUiMode.organizer,
                                  pendingCount: _organizerPendingCount,
                                  onPressed: _switchToOrganizer,
                                ),
                              IconButton(
                                onPressed: _load,
                                icon: Icon(
                                  Icons.refresh_rounded,
                                  color: MatchPayTokens.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: palette.primary,
                        onRefresh: () => _load(silent: true),
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // Saludo y titular (scroll); logo/menús quedan fijos arriba.
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.tr(
                                        'playerGreetingSmall',
                                        params: {'name': _nombreCorto},
                                      ),
                                      style: MatchPayTokens.bodySmallStyle().copyWith(
                                        color: MatchPayTokens.inkMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (headline.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        headline,
                                        style: MatchPayTokens.headlineStyle().copyWith(
                                          fontSize: 21,
                                          height: 1.3,
                                        ),
                                        maxLines: 3,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: NavShellScope.listPadding(context, top: 12),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                        if (_error != null) ...[
                          _ErrorBanner(
                            error: _error!,
                            onRetry: () => _load(silent: false),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Urgencia: aporte pendiente primero.
                        if (!alDia) ...[
                          MatchPaySectionHeader(
                            title: l10n.tr('playerHomeCobrosSection'),
                            accent: true,
                            pulseDot: true,
                          ),
                          const SizedBox(height: 10),
                          PlayerHomeCobrosTeaser(
                            total: deudaTotal,
                            pagando: false,
                            comprobanteEnRevision: comprobanteEnRevision,
                            explicacion: explicacion,
                            partidoLinea: partidoLineaCobro,
                            encuentrosPendientes: encuentrosPendientesCount,
                            onPayTotal: readOnly
                                ? _showOfflineWriteBlocked
                                : _pagarTotalDesdeHomeTeaser,
                            onPayOther: readOnly
                                ? _showOfflineWriteBlocked
                                : _pagarOtroDesdeHomeTeaser,
                            onVerDetalle: _verDetalleCobroDesdeHome,
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Próximo partido / convocatoria
                        if (hero != null) ...[
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: hero.requiereRespuesta
                                ? ConvocatoriaRespuestaObligatoriaCard(
                                    key: ValueKey(
                                      'invite-${hero.entry.partidoId}',
                                    ),
                                    convocatoria: hero,
                                    readOnly: readOnly,
                                    onReadOnlyTap: _showOfflineWriteBlocked,
                                    onRespondido: () => _load(),
                                  )
                                : _HeroMatchCard(
                                    key: ValueKey(
                                      'hero-${hero.entry.partidoId}',
                                    ),
                                    convocatoria: hero,
                                    convocatoriaCompleta:
                                        _heroConvocatoriaCompleta,
                                    needsResponse: false,
                                    onTap: () => _openConvocatoria(hero),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          if (mostrarUnirseGrupo)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _unirseAGrupo,
                                icon: const Icon(Icons.group_add_rounded),
                                label: Text(l10n.tr('groupCodeJoinAction')),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ] else if (alDia) ...[
                          _HeroEmptyCard(
                            key: const ValueKey('hero-empty'),
                            onOpenCobros: widget.onOpenMisCobros,
                            onJoinGroup:
                                mostrarUnirseGrupo ? _unirseAGrupo : null,
                            forOrganizerPlayer: esAdmin,
                          ),
                          const SizedBox(height: 12),
                          _PlayerUpToDateStrip(proximoPartido: null),
                          const SizedBox(height: 20),
                        ] else if (mostrarUnirseGrupo) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _unirseAGrupo,
                              icon: const Icon(Icons.group_add_rounded),
                              label: Text(l10n.tr('groupCodeJoinAction')),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (alDia && hero != null) ...[
                          _PlayerUpToDateStrip(
                            proximoPartido:
                                hero.estaConfirmado ? hero : null,
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Otras convocatorias pendientes / próximas
                        if (_otrasPendientes.isNotEmpty) ...[
                          MatchPaySectionHeader(
                            title: l10n.tr('playerInvitedTitle'),
                            count: _otrasPendientes.length,
                          ),
                          const SizedBox(height: 10),
                          MisInvitacionesPanel(
                            convocatorias: _otrasPendientes,
                            readOnly: readOnly,
                            onReadOnlyTap: _showOfflineWriteBlocked,
                            onRespondido: _load,
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (_otrosProximos.isNotEmpty) ...[
                          MatchPaySectionHeader(
                            title: l10n.tr('playerUpcomingTitle'),
                          ),
                          const SizedBox(height: 10),
                          ..._otrosProximos.map(
                            (c) => _SecondaryMatchCard(
                              convocatoria: c,
                              onTap: () => _openConvocatoria(c),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (_showOrganizerNudge && alDia) ...[
                          _OrganizerUpgradeCard(
                            alreadyOrganizer: esAdmin,
                            titleKey: empathy.titleKey,
                            bodyKey: empathy.bodyKey,
                            onTap: _onBecomeOrganizerTap,
                          ),
                          const SizedBox(height: 24),
                        ],

                        // 4. Actividad: siempre visible (vacío motivador para jugadores nuevos)
                        MatchPaySectionHeader(
                          title: l10n.tr('playerActivityTitle'),
                        ),
                        const SizedBox(height: 8),
                        if (!_hasActivityData) ...[
                          Text(
                            l10n.tr('playerActivityEmptyHint'),
                            style: MatchPayTokens.bodySmallStyle(
                              color: MatchPayTokens.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _StatsStrip(
                          stats: _misStats,
                          invitaciones: _invitacionesResumen,
                          semanasJugando: _semanasJugando,
                          showPlaceholders: !_hasActivityData,
                        ),
                        const SizedBox(height: 24),

                        // 5. Historial reciente solo al día (evita duplicar deuda)
                        if (alDia && _partidosJugados.isNotEmpty) ...[
                          Row(
                            children: [
                              Expanded(
                                child: MatchPaySectionHeader(
                                  title: l10n.tr('playerRecentMatchesTitle'),
                                ),
                              ),
                              TextButton(
                                onPressed: _openHistorial,
                                child: Text(l10n.tr('playerMatchHistorySeeAll')),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _MatchHistoryList(
                            partidos: _partidosJugados.take(3).toList(),
                            saldosPorPartido: _saldosPorPartido,
                            modo: PlayerMatchHistorialModo.porPartido,
                          ),
                          const SizedBox(height: 24),
                        ],
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ─── Hero partido ─────────────────────────────────────────────

class _HeroMatchCard extends StatelessWidget {
  final MiConvocatoria convocatoria;
  final ConvocatoriaCompleta? convocatoriaCompleta;
  final bool needsResponse;
  final VoidCallback onTap;

  const _HeroMatchCard({
    super.key,
    required this.convocatoria,
    this.convocatoriaCompleta,
    required this.needsResponse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final palette = SportThemeConfig.paletteFor(p.sportType);
    final recinto = p.recinto?.trim();
    final conv = convocatoriaCompleta;
    final confirmados = conv?.confirmados ?? 0;
    final pendientes = conv?.pendientes ?? 0;
    final tieneRoster = conv != null && confirmados > 0;
    final esReprogramado = convocatoria.esReprogramadoPendiente;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          height: tieneRoster ? 252 : 228,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.primaryDark,
                palette.primary,
                palette.primary.withValues(alpha: 0.88),
              ],
            ),
            boxShadow: MatchPayTokens.shadowHero(palette.primary),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -30,
                child: Opacity(
                  opacity: 0.14,
                  child: Text(
                    palette.emoji,
                    style: const TextStyle(fontSize: 140),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            (esReprogramado
                                    ? l10n.tr('matchStatusRescheduledShort')
                                    : needsResponse
                                        ? l10n.tr('playerHeroNeedsReply')
                                        : l10n.tr('playerHeroNextMatch'))
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            p.esOrganizando
                                ? l10n.tr('playerHeroMatchTypeOpen')
                                : l10n.tr('playerHeroMatchTypeReady'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      formatDiaCompleto(p.fecha),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                    ),
                    if (esReprogramado) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.tr('matchStatusPlayerRescheduledConfirm'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.place_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            [
                              if (recinto != null && recinto.isNotEmpty)
                                recinto,
                              p.sportType.labelForLocale(
                                context
                                    .readSettings()
                                    .locale
                                    .languageCode,
                              ),
                            ].join(' · '),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (conv != null && (confirmados > 0 || pendientes > 0)) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.tr(
                          'playerHeroRosterLine',
                          params: {
                            'confirmed': '$confirmados',
                            'pending': '$pendientes',
                          },
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (tieneRoster) ...[
                      const SizedBox(height: 10),
                      ConvocatoriaAvatarStrip(
                        titulares: conv.titulares,
                        cuposMax: conv.partido.cuposMax,
                        onDarkBackground: true,
                        mode: ConvocatoriaAvatarStripMode.player,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                esReprogramado
                                    ? Icons.event_repeat_rounded
                                    : needsResponse
                                        ? Icons.schedule_rounded
                                        : Icons.check_circle_rounded,
                                size: 16,
                                color: esReprogramado
                                    ? const Color(0xFF2563EB)
                                    : needsResponse
                                        ? Colors.orange.shade800
                                        : const Color(0xFF15803D),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                esReprogramado
                                    ? l10n.tr('playerHeroConfirmRescheduled')
                                    : needsResponse
                                        ? l10n.tr('playerHeroTapToReply')
                                        : l10n.tr('respondConfirmedStatus'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: esReprogramado
                                      ? const Color(0xFF1D4ED8)
                                      : needsResponse
                                          ? Colors.orange.shade900
                                          : const Color(0xFF14532D),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ],
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

class _HeroEmptyCard extends StatelessWidget {
  final VoidCallback? onOpenCobros;
  final VoidCallback? onJoinGroup;
  /// Organizador en vista jugador: no empujar a “unirse a un grupo”.
  final bool forOrganizerPlayer;

  const _HeroEmptyCard({
    super.key,
    this.onOpenCobros,
    this.onJoinGroup,
    this.forOrganizerPlayer = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final showJoin = onJoinGroup != null && !forOrganizerPlayer;
    // Sin CTA de unirse = ya tiene grupo (o es org): no decir "Únete a un grupo".
    final title = showJoin
        ? l10n.tr('playerHeroWaitingInvite')
        : l10n.tr('playerHeroAllGood');
    final subtitle = showJoin
        ? l10n.tr('playerHeroWaitingInviteSub')
        : l10n.tr('playerHeroAllGoodSub');

    return Material(
      color: Colors.transparent,
      child: Ink(
        height: showJoin ? 230 : 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.primaryDark.withValues(alpha: 0.92),
              palette.primary,
              palette.primary.withValues(alpha: 0.78),
            ],
          ),
          boxShadow: MatchPayTokens.shadowHero(palette.primary),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -30,
              child: Opacity(
                opacity: 0.12,
                child: Text(
                  palette.emoji,
                  style: const TextStyle(fontSize: 140),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l10n.tr('playerStatusUpToDate').toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  if (showJoin) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: palette.primaryDark,
                      ),
                      onPressed: onJoinGroup,
                      child: Text(l10n.tr('groupCodeJoinAction')),
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

class _PlayerUpToDateStrip extends StatelessWidget {
  final MiConvocatoria? proximoPartido;

  const _PlayerUpToDateStrip({this.proximoPartido});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MatchPaySurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: MatchPayTokens.accentSuccess,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('playerStatusUpToDate'),
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    color: const Color(0xFF065F46),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  proximoPartido != null
                      ? l10n.tr('playerStatusUpToDateNext')
                      : l10n.tr('playerStatusUpToDateSub'),
                  style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Secciones ────────────────────────────────────────────────

class _SecondaryMatchCard extends StatelessWidget {
  final MiConvocatoria convocatoria;
  final VoidCallback onTap;

  const _SecondaryMatchCard({
    required this.convocatoria,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = convocatoria.partido;
    final recinto = p.recinto?.trim();
    final palette = SportThemeConfig.paletteFor(p.sportType);
    final estadoView =
        PartidoEstadoPublicoView.resolveJugador(convocatoria, null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MatchPayTapScale(
        onTap: onTap,
        child: MatchPaySurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(palette.emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDiaCompleto(p.fecha),
                      style: MatchPayTokens.titleSmallStyle(),
                    ),
                    const SizedBox(height: 2),
                    if (estadoView != null)
                      PartidoEstadoPublicoBadge(
                        view: estadoView,
                        compact: true,
                      )
                    else
                      Text(
                        context.l10n.tr('respondConfirmedStatus'),
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          fontSize: 12.5,
                        ),
                      ),
                    if (recinto != null && recinto.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        recinto,
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          fontSize: 12.5,
                          color: MatchPayTokens.inkSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: MatchPayTokens.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  final EstadisticasJugador? stats;
  final MisInvitacionesResumen invitaciones;
  final int semanasJugando;
  final bool showPlaceholders;

  const _StatsStrip({
    required this.stats,
    required this.invitaciones,
    required this.semanasJugando,
    this.showPlaceholders = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final partidos = stats?.partidosJugados ?? 0;
    final secondary = resolvePrideSecondaryMetric(
      invitaciones: invitaciones,
      semanasJugando: semanasJugando,
    );

    final (String secondaryEmoji, String secondaryValue, String secondaryLabel) =
        switch (secondary.kind) {
      PlayerPrideSecondaryKind.respuesta => (
          '🤝',
          '${secondary.porcentaje}%',
          l10n.tr('playerStatResponsePride'),
        ),
      PlayerPrideSecondaryKind.racha => (
          '🔥',
          '${secondary.semanas}',
          l10n.tr('playerStatWeeksPride'),
        ),
      PlayerPrideSecondaryKind.vacio => (
          '🤝',
          '—',
          l10n.tr('playerStatResponsePride'),
        ),
    };

    final pagosAlDiaValue = (partidos > 0 && stats != null)
        ? '${stats!.porcentajePagoAlDia.toStringAsFixed(0)}%'
        : '—';

    // Siempre las 3 fichas principales (también en 0) para que el jugador
    // vea qué mide la app; no ocultar métricas solo porque valen cero.
    final items = <(String, String, String)>[
      (
        '🏆',
        '$partidos',
        l10n.tr('playerStatMatchesPride'),
      ),
      (
        secondaryEmoji,
        secondaryValue,
        secondaryLabel,
      ),
      (
        '💚',
        pagosAlDiaValue,
        l10n.tr('playerStatOnTimePride'),
      ),
    ];

    final visible = items.take(3).toList();
    final muted = showPlaceholders &&
        partidos == 0 &&
        invitaciones.recibidas == 0 &&
        semanasJugando < 2;

    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final e = visible[index];
          return Opacity(
            opacity: muted ? 0.72 : 1,
            child: Container(
              width: 148,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              decoration: BoxDecoration(
                color: MatchPayTokens.surfaceCard,
                borderRadius:
                    BorderRadius.circular(MatchPayTokens.radiusCardSm),
                border: Border.all(color: MatchPayTokens.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.$1, style: const TextStyle(fontSize: 20, height: 1)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        e.$2,
                        maxLines: 1,
                        style: MatchPayTokens.statValueStyle(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.$3,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


class _MatchHistoryList extends StatelessWidget {
  final List<DetallePartido> partidos;
  final Map<int, double> saldosPorPartido;
  final PlayerMatchHistorialModo modo;

  const _MatchHistoryList({
    required this.partidos,
    required this.saldosPorPartido,
    this.modo = PlayerMatchHistorialModo.porPartido,
  });

  @override
  Widget build(BuildContext context) {
    return PlayerMatchHistoryList(
      partidos: partidos,
      saldosPorPartido: saldosPorPartido,
      modo: modo,
    );
  }
}

/// CTA empático: vende alivio, no suscripción ni rol de organizador.
class _OrganizerUpgradeCard extends StatelessWidget {
  final bool alreadyOrganizer;
  final String titleKey;
  final String bodyKey;
  final VoidCallback onTap;

  const _OrganizerUpgradeCard({
    required this.alreadyOrganizer,
    required this.titleKey,
    required this.bodyKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return MatchPayTapScale(
      onTap: onTap,
      child: MatchPaySurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [palette.primaryDark, palette.primary],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tr(titleKey),
                        style: MatchPayTokens.titleSmallStyle().copyWith(
                          fontSize: 17,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.tr(bodyKey),
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final key in [
              'becomeOrganizerHomeBenefit1',
              'becomeOrganizerHomeBenefit2',
              'becomeOrganizerHomeBenefit3',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: palette.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.tr(key),
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(MatchPayTokens.radiusButton),
                ),
              ),
              child: Text(
                alreadyOrganizer
                    ? l10n.tr('appModeSwitchToOrganizer')
                    : l10n.tr('becomeOrganizerHomeCta'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MatchPaySurfaceCard(
      urgent: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: MatchPayTokens.accentError, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error,
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    color: MatchPayTokens.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.tr('retry')),
            ),
          ),
        ],
      ),
    );
  }
}
