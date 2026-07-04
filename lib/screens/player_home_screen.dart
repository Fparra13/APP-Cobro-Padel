import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../core/sport_theme.dart';
import '../core/supabase_helpers.dart';
import '../constants/conceptos_cobro.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/estadisticas_jugador.dart';
import '../models/gasto_por_concepto.dart';
import '../models/jugador.dart';
import '../models/mi_convocatoria.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/mis_invitaciones_panel.dart';
import '../widgets/player_match_history_tile.dart';
import '../widgets/sport_icon.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../utils/perfil_foto.dart';
import 'mi_historial_screen.dart';
import 'mis_cobros_screen.dart';
import 'responder_convocatoria_screen.dart';

/// Home jugador: funcionalidad intacta, estética premium y deportiva.
class PlayerHomeScreen extends StatefulWidget {
  const PlayerHomeScreen({super.key});

  @override
  State<PlayerHomeScreen> createState() => _PlayerHomeScreenState();
}

class _PlayerHomeScreenState extends State<PlayerHomeScreen> {
  List<MiConvocatoria> _todas = [];
  List<DetallePartido> _deudas = [];
  List<DetallePartido> _partidosJugados = [];
  final Map<int, DesgloseJugador?> _desglosePorPartido = {};
  Jugador? _perfil;
  EstadisticasJugador? _misStats;
  List<GastoPorConcepto> _gastosPorConcepto = [];
  PeriodoResumenJugador _periodoGastos = PeriodoResumenJugador.mes;
  bool _loadingGastos = false;
  bool _loading = true;
  bool _primeraCarga = true;
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
    if (!silent || _primeraCarga) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final uid = AuthService.instance.currentUser?.id;
      final results = await Future.wait([
        repos.getMisConvocatoriasComoJugador(),
        repos.getMisDeudasPendientes(),
        if (uid != null) repos.getJugador(uid) else Future<Jugador?>.value(null),
        repos.getEstadisticas(),
        repos.getMisPartidosJugados(limit: 20),
      ]);
      final todas = results[0] as List<MiConvocatoria>;
      final deudas = ordenarDeudasPorFecha(results[1] as List<DetallePartido>);
      final perfil = results[2] as Jugador?;
      final statsAll = results[3] as List<EstadisticasJugador>;
      final partidosJugados = results[4] as List<DetallePartido>;
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
        setState(() {
          _todas = todas;
          _deudas = deudas;
          _partidosJugados = partidosJugados;
          _desglosePorPartido.clear();
          _perfil = perfil;
          _misStats = mine;
          _primeraCarga = false;
          _loading = false;
        });
      }
      unawaited(_cargarDesgloses(deudas));
      unawaited(_cargarGastosPorConcepto());
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

  (DateTime? desde, DateTime? hasta) _rangoPeriodo(PeriodoResumenJugador p) {
    final now = DateTime.now();
    return switch (p) {
      PeriodoResumenJugador.mes => (
          DateTime(now.year, now.month),
          now.add(const Duration(days: 1)),
        ),
      PeriodoResumenJugador.anio => (
          DateTime(now.year),
          now.add(const Duration(days: 1)),
        ),
      PeriodoResumenJugador.todo => (null, null),
    };
  }

  Future<void> _cargarGastosPorConcepto() async {
    if (!mounted) return;
    setState(() => _loadingGastos = true);
    try {
      final repos =
          AppRepositories.isReady ? AppRepositories.I : context.repos;
      final rango = _rangoPeriodo(_periodoGastos);
      final gastos = await repos.getMisGastosPorConcepto(
        desde: rango.$1,
        hasta: rango.$2,
      );
      if (mounted) {
        setState(() {
          _gastosPorConcepto = gastos;
          _loadingGastos = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gastosPorConcepto = [];
          _loadingGastos = false;
        });
      }
    }
  }

  Future<void> _setPeriodoGastos(PeriodoResumenJugador periodo) async {
    if (_periodoGastos == periodo) return;
    setState(() => _periodoGastos = periodo);
    await _cargarGastosPorConcepto();
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

  Future<void> _openMisCobros() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MisCobrosScreen()),
    );
    _load();
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final esAdmin = AuthService.instance.isOrganizer;
    final hero = _heroConvocatoria;
    final deudaTotal = _deudas.fold<double>(
      0,
      (s, d) => s + montoATransferirCobro(d, _desglosePorPartido[d.partidoId]),
    );

    return ShellTabScaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      body: _loading && _primeraCarga
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              color: palette.primary,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Header flotante
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                        child: Row(
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
                                        color: const Color(0xFF111827),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFF5F4F0),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.tr(
                                      'playerGreetingExcited',
                                      params: {'name': _nombreCorto},
                                    ),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: Color(0xFF111827),
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.tr('playerWelcomeBack'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (esAdmin)
                              IconButton(
                                tooltip: l10n.tr('appModeSwitchToOrganizer'),
                                onPressed: _switchToOrganizer,
                                icon: Icon(
                                  Icons.swap_horiz_rounded,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            IconButton(
                              onPressed: _load,
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (esAdmin)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Text(
                          l10n.tr('playerModePreviewChip'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
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

                        // HERO: próximo partido / por responder
                        if (hero != null) ...[
                          _HeroMatchCard(
                            convocatoria: hero,
                            needsResponse: hero.requiereRespuesta,
                            onTap: () => _openConvocatoria(hero),
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (_otrasPendientes.isNotEmpty) ...[
                          _SectionHeader(
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
                          _SectionHeader(
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

                        // Stats personales (datos reales)
                        if (_misStats != null &&
                            _misStats!.partidosJugados > 0) ...[
                          _SectionHeader(
                            title: l10n.tr('playerPerformanceTitle'),
                          ),
                          const SizedBox(height: 10),
                          _StatsGrid(
                            stats: _misStats!,
                            participacionPct: _participacionPct,
                            invitesConfirmadas: _invitesConfirmadas,
                            invitesRecibidas: _invitesRecibidas,
                          ),
                          const SizedBox(height: 24),
                        ] else if (_invitesRecibidas > 0) ...[
                          _SectionHeader(
                            title: l10n.tr('playerPerformanceTitle'),
                          ),
                          const SizedBox(height: 10),
                          _ParticipationCard(
                            pct: _participacionPct,
                            confirmadas: _invitesConfirmadas,
                            recibidas: _invitesRecibidas,
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Gastos por concepto
                        if (_misStats != null &&
                            _misStats!.partidosJugados > 0) ...[
                          _SectionHeader(
                            title: l10n.tr('playerExpensesByConceptTitle'),
                          ),
                          const SizedBox(height: 10),
                          _ExpensesByConceptCard(
                            periodo: _periodoGastos,
                            gastos: _gastosPorConcepto,
                            loading: _loadingGastos,
                            onPeriodoChanged: _setPeriodoGastos,
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Historial de partidos jugados
                        if (_partidosJugados.isNotEmpty) ...[
                          Row(
                            children: [
                              Expanded(
                                child: _SectionHeader(
                                  title: l10n.tr('playerMatchHistoryTitle'),
                                  count: _partidosJugados.length,
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
                            partidos: _partidosJugados.take(5).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Pagos / saldo
                        _SectionHeader(title: l10n.tr('paymentsTitle')),
                        const SizedBox(height: 10),
                        _PaymentsCard(
                          deudaTotal: deudaTotal,
                          saldoActual: _misStats?.saldoActual ?? 0,
                          deudas: _deudas,
                          desglosePorPartido: _desglosePorPartido,
                          onOpenCobros: _openMisCobros,
                        ),
                        const SizedBox(height: 28),

                        // Conversión elegante
                        _OrganizerUpgradeCard(
                          alreadyOrganizer: esAdmin,
                          onTap: _onBecomeOrganizerTap,
                        ),
                        const SizedBox(height: 24),
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
  final bool needsResponse;
  final VoidCallback onTap;

  const _HeroMatchCard({
    required this.convocatoria,
    required this.needsResponse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = convocatoria.partido;
    final palette = SportThemeConfig.paletteFor(p.sportType);
    final recinto = p.recinto?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          height: 200,
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
            boxShadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
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
                    const SizedBox(height: 14),
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

// ─── Secciones ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int? count;

  const _SectionHeader({required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Colors.grey.shade500,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

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
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.black12,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8E6E1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (recinto != null && recinto.isNotEmpty) recinto,
                          context.l10n.tr('respondConfirmedStatus'),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final EstadisticasJugador stats;
  final double participacionPct;
  final int invitesConfirmadas;
  final int invitesRecibidas;

  const _StatsGrid({
    required this.stats,
    required this.participacionPct,
    required this.invitesConfirmadas,
    required this.invitesRecibidas,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (
        Icons.emoji_events_rounded,
        const Color(0xFFF59E0B),
        '${stats.partidosJugados}',
        l10n.tr('playerStatMatches'),
      ),
      (
        Icons.verified_rounded,
        const Color(0xFF10B981),
        '${stats.porcentajePagoAlDia.toStringAsFixed(0)}%',
        l10n.tr('playerStatOnTime'),
      ),
      (
        Icons.payments_rounded,
        const Color(0xFF6366F1),
        formatMoney(stats.totalGastado),
        l10n.tr('playerStatSpent'),
      ),
      (
        Icons.how_to_reg_rounded,
        const Color(0xFF8B5CF6),
        invitesRecibidas == 0
            ? '—'
            : '${participacionPct.toStringAsFixed(0)}%',
        l10n.tr('playerStatParticipation'),
      ),
    ];

    return Column(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: items.map((e) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8E6E1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(e.$1, color: e.$2, size: 22),
                  const Spacer(),
                  Text(
                    e.$3,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Text(
                    e.$4,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        if (invitesRecibidas > 0) ...[
          const SizedBox(height: 10),
          _ParticipationCard(
            pct: participacionPct,
            confirmadas: invitesConfirmadas,
            recibidas: invitesRecibidas,
            compact: true,
          ),
        ],
      ],
    );
  }
}

class _ParticipationCard extends StatelessWidget {
  final double pct;
  final int confirmadas;
  final int recibidas;
  final bool compact;

  const _ParticipationCard({
    required this.pct,
    required this.confirmadas,
    required this.recibidas,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8E6E1)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 44 : 52,
            height: compact ? 44 : 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 14 : 16,
                color: const Color(0xFF4338CA),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('playerParticipationTitle'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.tr(
                    'playerParticipationBody',
                    params: {
                      'confirmed': '$confirmadas',
                      'total': '$recibidas',
                    },
                  ),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpensesByConceptCard extends StatelessWidget {
  final PeriodoResumenJugador periodo;
  final List<GastoPorConcepto> gastos;
  final bool loading;
  final ValueChanged<PeriodoResumenJugador> onPeriodoChanged;

  const _ExpensesByConceptCard({
    required this.periodo,
    required this.gastos,
    required this.loading,
    required this.onPeriodoChanged,
  });

  String _labelConcepto(BuildContext context, String concepto) {
    final l10n = context.l10n;
    if (concepto == ConceptosCobro.cancha) return l10n.tr('courtLabel');
    if (concepto == ConceptosCobro.pelotas) return l10n.tr('ballsLabel');
    return concepto;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = gastos.fold<double>(0, (s, g) => s + g.monto);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E6E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in PeriodoResumenJugador.values)
                ChoiceChip(
                  label: Text(
                    l10n.tr(switch (p) {
                      PeriodoResumenJugador.mes => 'playerPeriodMonth',
                      PeriodoResumenJugador.anio => 'playerPeriodYear',
                      PeriodoResumenJugador.todo => 'playerPeriodAll',
                    }),
                  ),
                  selected: periodo == p,
                  onSelected: (_) => onPeriodoChanged(p),
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (gastos.isEmpty)
            Text(
              l10n.tr('playerExpensesEmpty'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          else ...[
            Text(
              l10n.tr(
                'playerExpensesTotal',
                params: {'amount': formatMoney(total)},
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            ...gastos.map((g) {
              final pct = total <= 0 ? 0.0 : (g.monto / total).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _labelConcepto(context, g.concepto),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          formatMoney(g.monto),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFF3F4F6),
                        color: const Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _MatchHistoryList extends StatelessWidget {
  final List<DetallePartido> partidos;

  const _MatchHistoryList({required this.partidos});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E6E1)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < partidos.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 16, endIndent: 16),
            PlayerMatchHistoryTile(detalle: partidos[i]),
          ],
        ],
      ),
    );
  }
}

class _PaymentsCard extends StatelessWidget {
  final double deudaTotal;
  final double saldoActual;
  final List<DetallePartido> deudas;
  final Map<int, DesgloseJugador?> desglosePorPartido;
  final VoidCallback onOpenCobros;

  const _PaymentsCard({
    required this.deudaTotal,
    required this.saldoActual,
    required this.deudas,
    required this.desglosePorPartido,
    required this.onOpenCobros,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final alDia = deudaTotal <= 0.005;
    final aFavor = saldoActual < -0.005;
    final favorMonto = -saldoActual;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E6E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: !alDia
                  ? const Color(0xFFFFF7ED)
                  : aFavor
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  !alDia
                      ? Icons.payments_rounded
                      : aFavor
                          ? Icons.account_balance_wallet_rounded
                          : Icons.check_circle_rounded,
                  color: !alDia
                      ? const Color(0xFFEA580C)
                      : aFavor
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF059669),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !alDia
                            ? l10n.tr(
                                'playerPendingAmount',
                                params: {
                                  'amount': formatMoney(deudaTotal),
                                },
                              )
                            : aFavor
                                ? l10n.tr(
                                    'playerCreditBalance',
                                    params: {
                                      'amount': formatMoney(favorMonto),
                                    },
                                  )
                                : l10n.tr('noPendingDebts'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: !alDia
                              ? const Color(0xFF9A3412)
                              : aFavor
                                  ? const Color(0xFF1E40AF)
                                  : const Color(0xFF065F46),
                        ),
                      ),
                      Text(
                        !alDia
                            ? l10n.tr('playerDeclarePaymentsHint')
                            : aFavor
                                ? l10n.tr('playerCreditBalanceHint')
                                : l10n.tr('playerPaymentsUpToDate'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!alDia && deudas.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...deudas.take(2).map((d) {
              final monto =
                  montoATransferirCobro(d, desglosePorPartido[d.partidoId]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (d.sportType != null)
                      SportEmoji(sport: d.sportType, size: 18)
                    else
                      const Icon(Icons.receipt_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tituloDetallePartido(d, l10n),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(monto),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: onOpenCobros,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF111827),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.tr('myCharges'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// CTA conversión: elegante, no agresivo.
class _OrganizerUpgradeCard extends StatelessWidget {
  final bool alreadyOrganizer;
  final VoidCallback onTap;

  const _OrganizerUpgradeCard({
    required this.alreadyOrganizer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.tr('becomeOrganizerBadge').toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.tr('becomeOrganizerHeadline'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.tr('becomeOrganizerCardBody'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: palette.primaryDark,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 108,
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: Column(
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 22)),
                    const SizedBox(height: 8),
                    Text(
                      alreadyOrganizer
                          ? l10n.tr('appModeOrganizer')
                          : l10n.tr('becomeOrganizerShort'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        alreadyOrganizer
                            ? Icons.swap_horiz_rounded
                            : Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(error, style: const TextStyle(fontSize: 13)),
          TextButton(onPressed: onRetry, child: Text(context.l10n.tr('retry'))),
        ],
      ),
    );
  }
}
