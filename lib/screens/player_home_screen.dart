import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/organizer_nudge_service.dart';
import '../core/sport_theme.dart';
import '../core/supabase_helpers.dart';
import '../core/sport_type.dart';
import '../models/convocatoria_jugador.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/estado_partido.dart';
import '../models/estadisticas_jugador.dart';
import '../models/jugador.dart';
import '../models/mi_convocatoria.dart';
import '../repositories/partido_repository.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/formatters.dart';
import '../widgets/cobro_pago_flow.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/player_matches_to_close.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/mis_invitaciones_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/player_match_history_tile.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../domain/deuda_explicacion.dart';
import '../models/saldo_historico.dart';
import '../utils/app_mode_pending.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../utils/perfil_foto.dart';
import '../widgets/app_mode_switch_button.dart';
import 'mi_historial_screen.dart';
import 'responder_convocatoria_screen.dart';

/// Home jugador: funcionalidad intacta, estética premium y deportiva.
class PlayerHomeScreen extends StatefulWidget {
  final VoidCallback? onOpenMisCobros;

  const PlayerHomeScreen({super.key, this.onOpenMisCobros});

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
  Jugador? _perfil;
  EstadisticasJugador? _misStats;
  bool _loading = true;
  bool _primeraCarga = true;
  bool _showOrganizerNudge = false;
  int _organizerPendingCount = 0;
  bool _pagandoCobro = false;
  ConvocatoriaCompleta? _heroConvocatoriaCompleta;
  Timer? _reloadDebounce;
  String? _error;

  List<MiConvocatoria> get _invitacionesTitular =>
      _todas.where((c) => !c.entry.esSuplente).toList();

  int get _invitesRecibidas => _invitacionesTitular.length;

  int get _invitesConfirmadas =>
      _invitacionesTitular.where((c) => c.estaConfirmado).length;

  double get _participacionPct =>
      _invitesRecibidas == 0
          ? 0
          : (_invitesConfirmadas / _invitesRecibidas) * 100;

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
    _reloadDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _primeraCarga && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (!silent && mounted) {
      setState(() => _error = null);
    }
    try {
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final uid = AuthService.instance.currentUser?.id;
      final organizerPendingFuture = AuthService.instance.isOrganizer
          ? _loadOrganizerPendingCount(repos)
          : Future<int>.value(0);
      final results = await Future.wait([
        repos.getMisConvocatoriasComoJugador(),
        repos.getMisDeudasPendientes(reconciliar: false),
        if (uid != null) repos.getJugador(uid) else Future<Jugador?>.value(null),
        repos.getEstadisticas(),
        repos.getMisPartidosJugados(limit: 20),
        if (uid != null)
          repos.getSaldosByJugador(uid)
        else
          Future<List<SaldoHistorico>>.value([]),
      ]);
      final todas = results[0] as List<MiConvocatoria>;
      final deudas = ordenarDeudasPorFecha(results[1] as List<DetallePartido>);
      final perfil = results[2] as Jugador?;
      final statsAll = results[3] as List<EstadisticasJugador>;
      final partidosJugados = results[4] as List<DetallePartido>;
      final historialSaldo = results[5] as List<SaldoHistorico>;
      final organizerPending = await organizerPendingFuture;
      final partidoIds = {
        ...deudas.map((d) => d.partidoId),
        ...partidosJugados.map((p) => p.partidoId),
      };
      final saldosPorPartido =
          await repos.getMisSaldosAnterioresPartidos(partidoIds);
      EstadisticasJugador? mine;
      if (uid != null) {
        for (final s in statsAll) {
          if (s.jugadorKeyId == uid) {
            mine = s;
            break;
          }
        }
      }
      if (mounted) {
        final showNudge = await OrganizerNudgeService.shouldShowHomeCard(
          partidosJugados: partidosJugados.length,
          invitesRecibidas: todas.where((c) => !c.entry.esSuplente).length,
        );
        setState(() {
          _todas = todas;
          _deudas = deudas;
          _partidosJugados = partidosJugados;
          _historialSaldo = historialSaldo;
          _saldosPorPartido = saldosPorPartido;
          _desglosePorPartido.clear();
          _perfil = perfil;
          _misStats = mine;
          _showOrganizerNudge = showNudge;
          _organizerPendingCount = organizerPending;
          _primeraCarga = false;
          _loading = false;
        });
      }
      unawaited(_cargarDesgloses(deudas));
      unawaited(_cargarHeroConvocatoria(_heroConvocatoria));
      unawaited(
        ConvocatoriaListaEsperaService().sincronizarPartidos(
          todas.map((c) => c.partido.id).whereType<int>(),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              SupabaseHelpers.describeError(e, operacion: 'Inicio jugador');
          _loading = false;
        });
      }
    }
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
      final conv = await repos.getConvocatoriaCompleta(hero!.partido.id!);
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
          'playerContextPlayToday',
          params: {'emoji': emoji, 'time': formatHora(fecha)},
        );
      }
      return l10n.tr(
        'playerContextNextIn',
        params: {'emoji': emoji, 'when': formatEnCuanto(fecha)},
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
    if (AuthService.instance.isOrganizer) {
      await _switchToOrganizer();
      return;
    }
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('becomeOrganizerTitle')),
        content: Text(l10n.tr('becomeOrganizerBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('becomeOrganizerCta')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AuthService.instance.becomeOrganizer();
      if (!mounted) return;
      await context.switchAppUiMode(AppUiMode.organizer);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('becomeOrganizerDone'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  ExplicacionDeudaJugador? get _explicacionDeuda {
    final saldo = _perfil?.saldoAcumulado ?? 0;
    return explicarDeudaJugador(
      saldoAcumulado: saldo,
      historial: _historialSaldo,
    );
  }

  Future<void> _pagarDesdeHome({required bool esTotal}) async {
    if (_pagandoCobro || _deudas.isEmpty) return;
    setState(() => _pagandoCobro = true);
    try {
      await CobroPagoFlow.iniciarPagoGlobal(
        context: context,
        deudas: _deudas,
        desgloses: _desglosePorPartido,
        esTotal: esTotal,
        onCompletado: () => _load(silent: true),
      );
    } finally {
      if (mounted) setState(() => _pagandoCobro = false);
    }
  }

  Future<void> _openHistorial() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MiHistorialScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _cambiarFoto() async {
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResponderConvocatoriaScreen(
          partidoId: c.entry.partidoId,
          convocatoria: c,
        ),
      ),
    );
    _load();
  }

  bool get _showActivityStrip {
    if (_misStats != null && _misStats!.partidosJugados > 0) return true;
    return _invitesRecibidas > 0;
  }

  Map<SportType, int> _deportesJugadosCounts() {
    final counts = <SportType, int>{};
    for (final p in _partidosJugados) {
      final sport = p.sportType;
      if (sport != null) {
        counts[sport] = (counts[sport] ?? 0) + 1;
      }
    }
    return counts;
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
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final esAdmin = AuthService.instance.isOrganizer;
    final hero = _heroConvocatoria;
    final deudaTotal = totalPendienteCobros(
      _deudas,
      _desglosePorPartido,
      saldosAnterioresPorPartido: _saldosPorPartido,
      saldoAcumuladoJugador: _perfil?.saldoAcumulado,
    );
    final alDia = deudaTotal <= 0.005;
    final explicacion = _explicacionDeuda;
    final empathy = _organizerEmpathyCopy();
    final headline = _dynamicHeadline(l10n, deudaTotal, hero);
    final lang = context.readSettings().locale.languageCode;
    final deportesCounts = _deportesJugadosCounts();
    final comprobanteEnRevision =
        _deudas.any((d) => d.comprobantePendienteValidacion);

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      body: _loading && _primeraCarga
          ? const PlayerHomeShimmer()
          : RefreshIndicator(
              color: palette.primary,
              onRefresh: () => _load(silent: true),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Header: avatar + acciones; saludo y titular a ancho completo
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                InkWell(
                                  onTap: _perfil == null ? null : _cambiarFoto,
                                  borderRadius: BorderRadius.circular(24),
                                  child: Stack(
                                    children: [
                                      JugadorAvatar(
                                        nombre: _perfil?.nombre ?? _nombreCorto,
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
                                const Spacer(),
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
                            const SizedBox(height: 12),
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
                              const SizedBox(height: 6),
                              Text(
                                headline,
                                style: MatchPayTokens.headlineStyle().copyWith(
                                  fontSize: 22,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: NavShellScope.listPadding(context, top: 12),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (_error != null) ...[
                          _ErrorBanner(error: _error!, onRetry: _load),
                          const SizedBox(height: 16),
                        ],

                        // 1. Próximo partido / convocatoria (prioridad visual)
                        if (hero != null) ...[
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: _HeroMatchCard(
                              key: ValueKey(
                                'hero-${hero.entry.partidoId}',
                              ),
                              convocatoria: hero,
                              convocatoriaCompleta: _heroConvocatoriaCompleta,
                              needsResponse: hero.requiereRespuesta,
                              onTap: () => _openConvocatoria(hero),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ] else if (alDia) ...[
                          _HeroEmptyCard(
                            key: const ValueKey('hero-empty'),
                            onOpenCobros: widget.onOpenMisCobros,
                          ),
                          const SizedBox(height: 12),
                          _PlayerUpToDateStrip(proximoPartido: null),
                          const SizedBox(height: 20),
                        ],

                        if (alDia && hero != null) ...[
                          _PlayerUpToDateStrip(
                            proximoPartido:
                                hero.estaConfirmado ? hero : null,
                          ),
                          const SizedBox(height: 8),
                        ],

                        // 2. Otras convocatorias pendientes / próximas
                        if (_otrasPendientes.isNotEmpty) ...[
                          MatchPaySectionHeader(
                            title: l10n.tr('playerInvitedTitle'),
                            count: _otrasPendientes.length,
                          ),
                          const SizedBox(height: 10),
                          MisInvitacionesPanel(
                            convocatorias: _otrasPendientes,
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

                        // 3. Cuenta pendiente (compacto; detalle en Mis cobros)
                        if (!alDia) ...[
                          MatchPaySectionHeader(
                            title: l10n.tr('playerHomeCobrosSection'),
                          ),
                          const SizedBox(height: 10),
                          PlayerHomeCobrosTeaser(
                            total: deudaTotal,
                            pagando: _pagandoCobro,
                            comprobanteEnRevision: comprobanteEnRevision,
                            explicacion: explicacion,
                            onPayTotal: () => _pagarDesdeHome(esTotal: true),
                            onOpenMisCobros:
                                widget.onOpenMisCobros ?? () {},
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

                        // 4. Actividad (chips de deportes escalables)
                        if (_showActivityStrip) ...[
                          MatchPaySectionHeader(
                            title: l10n.tr('playerActivityTitle'),
                          ),
                          const SizedBox(height: 8),
                          _StatsStrip(
                            stats: _misStats,
                            participacionPct: _participacionPct,
                            invitesConfirmadas: _invitesConfirmadas,
                            invitesRecibidas: _invitesRecibidas,
                            semanasJugando: _semanasJugando,
                          ),
                          if (deportesCounts.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _SportBreakdownChips(
                              counts: deportesCounts,
                              lang: lang,
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],

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
    final roster = conv?.titulares
            .where((j) => j.estado == EstadoConfirmacion.confirmado)
            .take(5)
            .toList() ??
        const <ConvocatoriaJugadorEntry>[];

    return MatchPayTapScale(
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: roster.isNotEmpty ? 252 : 228,
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
                            (needsResponse
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
                    if (roster.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 34,
                        child: Stack(
                          children: [
                            for (var i = 0; i < roster.length; i++)
                              Positioned(
                                left: i * 22.0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: palette.primaryDark,
                                      width: 2,
                                    ),
                                  ),
                                  child: JugadorAvatar(
                                    nombre: roster[i].jugador.nombre,
                                    fotoUrl: roster[i].jugador.fotoUrl,
                                    fotoPath: roster[i].jugador.fotoPath,
                                    size: 30,
                                    borderRadius: 15,
                                  ),
                                ),
                              ),
                          ],
                        ),
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
                                needsResponse
                                    ? Icons.schedule_rounded
                                    : Icons.check_circle_rounded,
                                size: 16,
                                color: needsResponse
                                    ? Colors.orange.shade800
                                    : const Color(0xFF15803D),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                needsResponse
                                    ? l10n.tr('playerHeroTapToReply')
                                    : l10n.tr('respondConfirmedStatus'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: needsResponse
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

  const _HeroEmptyCard({
    super.key,
    this.onOpenCobros,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return MatchPayTapScale(
      onTap: onOpenCobros,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 200,
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
                      l10n.tr('playerHeroWaitingInvite'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.tr('playerHeroWaitingInviteSub'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13,
                        height: 1.35,
                      ),
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
                    Text(
                      [
                        if (recinto != null && recinto.isNotEmpty) recinto,
                        context.l10n.tr('respondConfirmedStatus'),
                      ].join(' · '),
                      style: MatchPayTokens.bodySmallStyle().copyWith(
                        fontSize: 12.5,
                      ),
                    ),
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
  final double participacionPct;
  final int invitesConfirmadas;
  final int invitesRecibidas;
  final int semanasJugando;

  const _StatsStrip({
    required this.stats,
    required this.participacionPct,
    required this.invitesConfirmadas,
    required this.invitesRecibidas,
    required this.semanasJugando,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = <(String, String, String)>[];

    if (stats != null && stats!.partidosJugados > 0) {
      final asistencia = invitesRecibidas > 0
          ? participacionPct
          : stats!.porcentajePagoAlDia;
      items.addAll([
        (
          '🏆',
          '${stats!.partidosJugados}',
          l10n.tr('playerStatMatchesPride'),
        ),
        (
          '⭐',
          '${asistencia.toStringAsFixed(0)}%',
          l10n.tr('playerStatAttendancePride'),
        ),
      ]);
      if (stats!.partidosUltimos90Dias > 0) {
        items.add((
          '📅',
          '${stats!.partidosUltimos90Dias}',
          l10n.tr('playerStatRecentMatches'),
        ));
      }
    }

    if (semanasJugando >= 2) {
      items.add((
        '🔥',
        '$semanasJugando',
        l10n.tr('playerStatWeeksPride'),
      ));
    } else if (invitesRecibidas > 0) {
      items.add((
        '🤝',
        '${participacionPct.toStringAsFixed(0)}%',
        l10n.tr('playerStatParticipation'),
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final e = items[index];
          return Container(
            width: 148,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: MatchPayTokens.surfaceCard,
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
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
          );
        },
      ),
    );
  }
}

class _SportBreakdownChips extends StatelessWidget {
  final Map<SportType, int> counts;
  final String lang;

  const _SportBreakdownChips({
    required this.counts,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = sorted[index];
          final palette = SportThemeConfig.paletteFor(entry.key);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(palette.emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(
                  '${entry.value} ${entry.key.labelForLang(lang)}',
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
