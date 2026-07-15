import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/offline_status_controller.dart';
import '../offline/organizer_home_loader.dart';
import '../offline/organizer_home_snapshot.dart';
import '../offline/offline_snapshot_store.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/convocatoria_jugador.dart';
import '../models/mi_convocatoria.dart';
import '../repositories/partido_repository.dart';
import '../widgets/partido_estado_publico.dart';
import '../domain/estado_partido_publico.dart';
import '../domain/partido_lifecycle.dart';
import '../domain/organizer_cycle_logic.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../utils/formatters.dart';
import '../utils/app_navigation.dart';
import '../utils/app_mode_pending.dart';
import '../widgets/pagos_por_validar_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/kloovi_brand.dart';
import '../widgets/app_mode_switch_button.dart';
import '../widgets/convocatoria_avatar_strip.dart';
import '../widgets/organizer_cycle_hero.dart';
import '../utils/cancelar_convocatoria_flow.dart';
import '../utils/reprogramar_convocatoria_flow.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';
import '../widgets/organizer_group_summary.dart';
import '../widgets/quick_actions_panel.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/friendly_error_panel.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;

  const HomeScreen({super.key, this.onNavigateTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ResumenJugador> _resumenes = [];
  List<ConvocatoriaCompleta> _convocatorias = [];
  List<PartidoCompleto> _partidosJugadosRecientes = [];
  List<DesgloseJugador> _ultimoPartidoDesglose = [];
  List<MiConvocatoria> _misInvitaciones = [];
  List<DetallePartido> _pagosPorValidar = [];
  List<DetallePartido> _misDeudas = [];
  bool _loading = true;
  bool _primeraCarga = true;
  bool _offlineEmpty = false;
  String? _loadError;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _load();
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
    // En silent también limpiamos error residual de cargas previos.
    if (mounted) {
      setState(() {
        if (!silent && _primeraCarga) _loading = true;
        _loadError = null;
        _offlineEmpty = false;
      });
    }

    final offlineStatus = context.read<OfflineStatusController>();
    final userId = AuthService.instance.currentUser?.id;
    final snapshotStore = userId != null
        ? OfflineSnapshotStore(userId: userId)
        : null;

    try {
      final result = await loadOrganizerHome(
        repos: context.repos,
        snapshotStore: snapshotStore,
      );

      if (!mounted) return;

      switch (result.source) {
        case OrganizerHomeLoadSource.live:
          offlineStatus.markLive();
          _applyOrganizerHomeData(result.data!);
        case OrganizerHomeLoadSource.offlineCache:
          offlineStatus.markOfflineCached(result.snapshotAt!);
          _applyOrganizerHomeData(result.data!);
        case OrganizerHomeLoadSource.offlineEmpty:
          offlineStatus.markOfflineEmpty();
          setState(() {
            _resumenes = [];
            _convocatorias = [];
            _misInvitaciones = [];
            _pagosPorValidar = [];
            _misDeudas = [];
            _partidosJugadosRecientes = [];
            _ultimoPartidoDesglose = [];
            _offlineEmpty = true;
            _primeraCarga = false;
          });
        case OrganizerHomeLoadSource.error:
          // Nunca pantalla de error en Inicio: mostrar vacío usable.
          offlineStatus.markLive();
          _applyOrganizerHomeData(OrganizerHomeData.empty);
      }

      if (result.source == OrganizerHomeLoadSource.live &&
          result.data != null) {
        unawaited(
          ConvocatoriaListaEsperaService().sincronizarPartidos(
            result.data!.convocatorias
                .where((c) => c.partido.esOrganizando)
                .map((c) => c.partido.id)
                .whereType<int>(),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _applyOrganizerHomeData(OrganizerHomeData.empty);
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyOrganizerHomeData(OrganizerHomeData data) {
    setState(() {
      _resumenes = data.resumenes;
      _convocatorias = data.convocatorias;
      _misInvitaciones = data.misInvitaciones;
      _pagosPorValidar = data.pagosPorValidar;
      _misDeudas = data.misDeudas;
      _partidosJugadosRecientes = data.partidosJugadosRecientes;
      _ultimoPartidoDesglose = data.ultimoPartidoDesglose;
      _offlineEmpty = false;
      _loadError = null;
      _primeraCarga = false;
    });
  }

  /// Solo [read]: nunca llamar [watch] desde callbacks de UI.
  bool get _readOnly => context.read<OfflineStatusController>().isReadOnly;

  void _showOfflineWriteBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('offlineWriteBlocked'))),
    );
  }

  Future<void> _openOrganizerPartido(int? partidoId) async {
    if (partidoId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('convocatoriaOpenUnavailable'))),
        );
      }
      return;
    }
    await abrirOrganizarPartido(context, partidoId: partidoId);
    if (mounted) _load(silent: true);
  }

  int get _playerPendingCount => playerModePendingCount(
        misDeudas: _misDeudas,
        misInvitaciones: _misInvitaciones,
      );

  int get _jugadoresAlDia => jugadoresAlDiaGrupo(_resumenes);

  bool get _hasPagosPendientes => _pagosPorValidar
      .any((d) => d.comprobantePendienteValidacion);

  bool get _convocatoriasNeedAttention => _convocatoriasEnLista.any((c) {
        final situacion = PartidoLifecycle.situacionOrganizador(c);
        if (situacion == ConvocatoriaOrganizadorSituacion.sinResolver) {
          return true;
        }
        return situacion == ConvocatoriaOrganizadorSituacion.preparando &&
            c.partido.esOrganizando;
      });

  PartidoCompleto? get _ultimoPartido => _partidosJugadosRecientes.isNotEmpty
      ? _partidosJugadosRecientes.first
      : null;

  OrganizerCycleSnapshot get _cycleSnapshot => OrganizerCycleSnapshot.resolve(
        convocatorias: _convocatorias,
        partidosJugadosRecientes: _partidosJugadosRecientes,
        resumenesGrupo: _resumenes,
      );

  /// Hero de partido solo en etapas operativas (convocar / registrar gastos).
  /// En cobranza manda [CobrosCard]; no duplicar ficha de partido.
  bool _mostrarHeroOperativo(OrganizerCycleSnapshot cycle) {
    switch (cycle.phase) {
      case OrganizerCyclePhase.empty:
      case OrganizerCyclePhase.preparing:
      case OrganizerCyclePhase.atRisk:
      case OrganizerCyclePhase.needsResolution:
      case OrganizerCyclePhase.registerExpenses:
        return true;
      case OrganizerCyclePhase.collecting:
      case OrganizerCyclePhase.allPaid:
        return false;
    }
  }

  List<ConvocatoriaCompleta> get _convocatoriasEnLista {
    final snap = _cycleSnapshot;
    final featuredId = snap.convocatoria?.partido.id;
    if (featuredId == null ||
        (snap.phase != OrganizerCyclePhase.preparing &&
            snap.phase != OrganizerCyclePhase.needsResolution &&
            snap.phase != OrganizerCyclePhase.atRisk &&
            snap.phase != OrganizerCyclePhase.registerExpenses)) {
      return _convocatorias;
    }
    return _convocatorias.where((c) => c.partido.id != featuredId).toList();
  }

  Future<void> _abrirRegistrarGastos(int partidoId) async {
    await Navigator.pushNamed(
      context,
      '/registrar-partido',
      arguments: partidoId,
    );
  }

  Future<void> _cancelarConvocatoria(int partidoId) async {
    if (_readOnly) {
      _showOfflineWriteBlocked();
      return;
    }
    final host = matchPayRootContext ?? context;
    if (!host.mounted) return;

    final l10n = host.l10n;
    final ok = await confirmarEliminarPartido(
      host,
      titulo: l10n.tr('organizerCycleCancelConfirmTitle'),
      mensaje: l10n.tr('organizerCycleCancelConfirmBody'),
      confirmLabel: l10n.tr('organizerCycleCancelConfirmAction'),
      consecuencias: [
        l10n.tr('organizerCycleCancelConsequence1'),
        l10n.tr('organizerCycleCancelConsequence2'),
      ],
    );
    if (!ok || !mounted) return;
    try {
      final conv = await context.repos.getConvocatoriaCompleta(partidoId);
      final cancelOk = await CancelarConvocatoriaFlow.ejecutar(
        host,
        partidoId: partidoId,
        convocatoria: conv,
      );
      if (!cancelOk || !mounted) return;
      await _load(silent: true);
      if (!host.mounted) return;
      ScaffoldMessenger.of(host).showSnackBar(
        SnackBar(content: Text(l10n.tr('organizerCycleCancelSuccessSnack'))),
      );
    } catch (e) {
      if (!host.mounted) return;
      ScaffoldMessenger.of(host).showSnackBar(
        SnackBar(
          content: Text(host.userError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _reprogramarConvocatoria(ConvocatoriaCompleta convocatoria) async {
    if (_readOnly) {
      _showOfflineWriteBlocked();
      return;
    }
    final host = matchPayRootContext ?? context;
    if (!host.mounted) return;

    final ok = await ReprogramarConvocatoriaFlow.ejecutar(
      host,
      convocatoria: convocatoria,
    );
    if (ok && mounted) {
      AppRepositories.notifyDataChanged();
      await _load(silent: true);
    }
  }

  Future<void> _onCyclePrimaryAction() async {
    final snap = _cycleSnapshot;
    switch (snap.phase) {
      case OrganizerCyclePhase.empty:
        if (_readOnly) {
          _showOfflineWriteBlocked();
          return;
        }
        await showOrganizerMatchMenu(context);
      case OrganizerCyclePhase.preparing:
      case OrganizerCyclePhase.atRisk:
      case OrganizerCyclePhase.needsResolution:
        final id = snap.convocatoria?.partido.id;
        if (id != null) {
          await abrirOrganizarPartido(context, partidoId: id);
        }
      case OrganizerCyclePhase.registerExpenses:
        if (_readOnly) {
          _showOfflineWriteBlocked();
          return;
        }
        final id = snap.convocatoria?.partido.id;
        if (id != null) {
          await _abrirRegistrarGastos(id);
        }
      case OrganizerCyclePhase.collecting:
        widget.onNavigateTab?.call(1);
      case OrganizerCyclePhase.allPaid:
        break;
    }
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = context.watch<OfflineStatusController>().isReadOnly;
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final cycle = _cycleSnapshot;

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading && _primeraCarga
                ? const PlayerHomeShimmer()
                : _loadError != null
                    ? _buildLoadErrorState()
                    : _offlineEmpty
                        ? _buildOfflineEmptyState()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Material(
                                color: MatchPayTokens.surfaceBase,
                                elevation: 0,
                                child: SafeArea(
                                  bottom: false,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      8,
                                      12,
                                      8,
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: KlooviHomeBrand(
                                              forOrganizer: true,
                                            ),
                                          ),
                                        ),
                                        AppModeSwitchButton(
                                          targetMode: AppUiMode.player,
                                          pendingCount: _playerPendingCount,
                                          onPressed: () {
                                            context.switchAppUiMode(
                                              AppUiMode.player,
                                            );
                                          },
                                        ),
                                        IconButton(
                                          tooltip: l10n.refreshTooltip,
                                          onPressed: () =>
                                              _load(silent: true),
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
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    slivers: [
                                      SliverPadding(
                                        padding: NavShellScope.listPadding(
                                          context,
                                          top: 8,
                                          bottom: 24,
                                        ),
                                        sliver: SliverList(
                                          delegate: // ignore: prefer_const_constructors
                                              SliverChildListDelegate([
                                            OrganizerGroupSummary(
                                              totalJugadores:
                                                  _resumenes.length,
                                              jugadoresConDeuda:
                                                  jugadoresConDeudaGrupo(
                                                _resumenes,
                                              ),
                                              jugadoresAlDia: _jugadoresAlDia,
                                              montoPendiente:
                                                  deudaTotalGrupo(_resumenes),
                                              onVerCobros:
                                                  widget.onNavigateTab != null
                                                      ? () => widget
                                                          .onNavigateTab!(1)
                                                      : null,
                                            ),
                                            if (_hasPagosPendientes) ...[
                                              const SizedBox(height: 16),
                                              MatchPaySectionHeader(
                                                title: l10n.tr(
                                                  'paymentsToValidateTitle',
                                                ),
                                                count: _pagosPorValidar
                                                    .where(
                                                      (d) => d
                                                          .comprobantePendienteValidacion,
                                                    )
                                                    .length,
                                                accent: true,
                                                pulseDot: true,
                                              ),
                                              const SizedBox(height: 10),
                                              PagosPorValidarPanel(
                                                pagos: _pagosPorValidar,
                                                onValidado: _load,
                                                prominent: true,
                                                sectionTitleExternal: true,
                                                readOnly: readOnly,
                                                onReadOnlyTap:
                                                    _showOfflineWriteBlocked,
                                              ),
                                            ],
                                            if (_mostrarHeroOperativo(
                                              cycle,
                                            )) ...[
                                              const SizedBox(height: 20),
                                              OrganizerCycleHero(
                                                snapshot: cycle,
                                                onPrimaryAction:
                                                    _onCyclePrimaryAction,
                                                onCreateMatch: () =>
                                                    showOrganizerMatchMenu(
                                                  context,
                                                ),
                                                onMarkPlayed: cycle
                                                            .convocatoria
                                                            ?.partido
                                                            .id ==
                                                        null
                                                    ? null
                                                    : () =>
                                                        _abrirRegistrarGastos(
                                                          cycle
                                                              .convocatoria!
                                                              .partido
                                                              .id!,
                                                        ),
                                                onReschedule:
                                                    cycle.convocatoria == null
                                                        ? null
                                                        : () =>
                                                            _reprogramarConvocatoria(
                                                              cycle
                                                                  .convocatoria!,
                                                            ),
                                                onCancel: cycle.convocatoria
                                                            ?.partido.id ==
                                                        null
                                                    ? null
                                                    : () =>
                                                        _cancelarConvocatoria(
                                                          cycle.convocatoria!
                                                              .partido.id!,
                                                        ),
                                              ),
                                            ],
                                            if (_convocatoriasEnLista
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 20),
                                              MatchPaySectionHeader(
                                                title: l10n.tr(
                                                  'homeActiveConvocatorias',
                                                ),
                                                count: _convocatoriasEnLista
                                                    .length,
                                                accent:
                                                    _convocatoriasNeedAttention,
                                                pulseDot:
                                                    _convocatoriasNeedAttention,
                                              ),
                                              const SizedBox(height: 10),
                                              _buildConvocatoriasActivas(
                                                _convocatoriasEnLista,
                                              ),
                                            ],
                                            const SizedBox(height: 20),
                                            QuickActionsPanel(
                                              resumenes: _resumenes,
                                              ultimoPartido: _ultimoPartido,
                                              ultimoPartidoDesglose:
                                                  _ultimoPartidoDesglose,
                                              onRefresh: () =>
                                                  _load(silent: true),
                                              onNavigateTab:
                                                  widget.onNavigateTab,
                                              readOnly: readOnly,
                                              onReadOnlyTap:
                                                  _showOfflineWriteBlocked,
                                            ),
                                            const SizedBox(height: 88),
                                          ]),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
          ),
          if (!readOnly)
            Positioned(
              right: 16,
              bottom: 16,
              child: OrganizerPartidoFab(
                onPressed: () => showOrganizerMatchMenu(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadErrorState() {
    return FriendlyErrorPanel(
      message: _loadError ?? context.tr('errorGeneric'),
      onRetry: _load,
    );
  }

  Widget _buildOfflineEmptyState() {
    final l10n = context.l10n;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 56,
                      color: MatchPayTokens.inkMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.tr('offlineNoDataAvailable'),
                      textAlign: TextAlign.center,
                      style: MatchPayTokens.titleSmallStyle(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.tr('offlineNoDataAvailableHint'),
                      textAlign: TextAlign.center,
                      style: MatchPayTokens.bodySmallStyle(),
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

  Widget _buildConvocatoriasActivas(List<ConvocatoriaCompleta> convocatorias) {
    final l10n = context.l10n;
    final sinResolver = convocatorias
        .where(
          (c) =>
              PartidoLifecycle.situacionOrganizador(c) ==
              ConvocatoriaOrganizadorSituacion.sinResolver,
        )
        .toList();
    final listasGastos = convocatorias
        .where(
          (c) =>
              PartidoLifecycle.situacionOrganizador(c) ==
              ConvocatoriaOrganizadorSituacion.listoParaGastos,
        )
        .toList();
    final proximas = convocatorias
        .where(
          (c) =>
              PartidoLifecycle.situacionOrganizador(c) ==
              ConvocatoriaOrganizadorSituacion.preparando,
        )
        .toList();

    Widget grupos(
      List<ConvocatoriaCompleta> lista, {
      required ConvocatoriaOrganizadorSituacion situacion,
    }) {
      final enEspera =
          lista.where((c) => c.partido.esOrganizando).toList();
      final confirmadas =
          lista.where((c) => c.partido.esConfirmado).toList();
      final esPreparando =
          situacion == ConvocatoriaOrganizadorSituacion.preparando;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enEspera.isNotEmpty) ...[
            if (esPreparando)
              _ConvocatoriaGrupo(
                titulo: l10n.tr('homeWaiting'),
                icono: Icons.hourglass_top_rounded,
                color: MatchPayTokens.accentCredit,
                cantidad: enEspera.length,
              ),
            ...enEspera.map(
              (c) => _ConvocatoriaTile(
                convocatoria: c,
                situacion: situacion,
                onTap: () => _openOrganizerPartido(c.partido.id),
              ),
            ),
          ],
          if (confirmadas.isNotEmpty) ...[
            if (enEspera.isNotEmpty) const SizedBox(height: 10),
            if (esPreparando)
              _ConvocatoriaGrupo(
                titulo: l10n.tr('homeConfirmed'),
                icono: Icons.check_circle_rounded,
                color: MatchPayTokens.accentSuccess,
                cantidad: confirmadas.length,
              ),
            ...confirmadas.map(
              (c) => _ConvocatoriaTile(
                convocatoria: c,
                confirmado: true,
                situacion: situacion,
                onTap: () => _openOrganizerPartido(c.partido.id),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sinResolver.isNotEmpty) ...[
          _ConvocatoriaGrupo(
            titulo: l10n.tr('homeUnresolvedConvocatorias'),
            icono: Icons.help_outline_rounded,
            color: MatchPayTokens.accentUrgent,
            cantidad: sinResolver.length,
          ),
          Text(
            l10n.tr('homeUnresolvedConvocatoriasHint'),
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.accentUrgent,
            ),
          ),
          const SizedBox(height: 8),
          grupos(
            sinResolver,
            situacion: ConvocatoriaOrganizadorSituacion.sinResolver,
          ),
        ],
        if (listasGastos.isNotEmpty) ...[
          if (sinResolver.isNotEmpty) const SizedBox(height: 14),
          _ConvocatoriaGrupo(
            titulo: l10n.tr('homePastConvocatorias'),
            icono: Icons.event_busy_rounded,
            color: MatchPayTokens.accentCredit,
            cantidad: listasGastos.length,
          ),
          Text(
            l10n.tr('homePastConvocatoriasHint'),
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkSecondary,
            ),
          ),
          const SizedBox(height: 8),
          grupos(
            listasGastos,
            situacion: ConvocatoriaOrganizadorSituacion.listoParaGastos,
          ),
        ],
        if (proximas.isNotEmpty) ...[
          if (sinResolver.isNotEmpty || listasGastos.isNotEmpty)
            const SizedBox(height: 14),
          grupos(
            proximas,
            situacion: ConvocatoriaOrganizadorSituacion.preparando,
          ),
        ],
      ],
    );
  }
}

class _ConvocatoriaGrupo extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Color color;
  final int cantidad;

  const _ConvocatoriaGrupo({
    required this.titulo,
    required this.icono,
    required this.color,
    required this.cantidad,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$titulo ($cantidad)',
            style: MatchPayTokens.sectionLabelStyle(color: color).copyWith(
              letterSpacing: 0.2,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConvocatoriaTile extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final bool confirmado;
  final ConvocatoriaOrganizadorSituacion situacion;
  final VoidCallback onTap;

  const _ConvocatoriaTile({
    required this.convocatoria,
    required this.onTap,
    required this.situacion,
    this.confirmado = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = convocatoria;
    final fecha = formatFechaLegibleCorta(c.partido.fecha);
    final hora = formatHora(c.partido.fecha);
    final pendientes = c.invitados - c.confirmados - c.rechazados;
    final recinto = c.partido.recinto ?? l10n.tr('noVenue');
    final confirmadosLine = l10n.tr('homeConvocatoriaConfirmedLine', params: {
      'confirmed': '${c.confirmados}',
      'max': '${c.partido.cuposMax}',
    });
    final pendientesLine = !confirmado && pendientes > 0
        ? ' · ${l10n.tr('homeConvocatoriaPendingShort', params: {'count': '$pendientes'})}'
        : '';

    final sinResolver =
        situacion == ConvocatoriaOrganizadorSituacion.sinResolver;
    final listoGastos =
        situacion == ConvocatoriaOrganizadorSituacion.listoParaGastos;
    final estadoPublico = !sinResolver && !listoGastos
        ? PartidoEstadoPublicoView.resolve(c)
        : null;

    final iconBg = sinResolver
        ? MatchPayTokens.accentUrgentBorder.withValues(alpha: 0.35)
        : listoGastos
            ? MatchPayTokens.accentCredit.withValues(alpha: 0.15)
            : confirmado
                ? MatchPayTokens.accentSuccess.withValues(alpha: 0.15)
                : MatchPayTokens.accentCredit.withValues(alpha: 0.12);
    final iconColor = sinResolver
        ? MatchPayTokens.accentUrgent
        : listoGastos
            ? MatchPayTokens.accentCredit
            : confirmado
                ? MatchPayTokens.accentSuccess
                : MatchPayTokens.accentCredit;
    final iconData = sinResolver
        ? Icons.help_outline_rounded
        : listoGastos
            ? Icons.receipt_long_rounded
            : confirmado
                ? Icons.check_circle_rounded
                : Icons.campaign_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MatchPaySurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        urgent: sinResolver,
        elevated: true,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fecha,
                    style: MatchPayTokens.titleSmallStyle(),
                  ),
                  Text(
                    '$hora · $recinto',
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkSecondary,
                    ),
                  ),
                  if (estadoPublico != null) ...[
                    const SizedBox(height: 6),
                    PartidoEstadoPublicoBadge(
                      view: estadoPublico,
                      compact: true,
                    ),
                  ],
                  const SizedBox(height: 8),
                  ConvocatoriaAvatarStrip(
                    titulares: c.titulares,
                    cuposMax: c.partido.cuposMax,
                    size: 24,
                    overlap: 18,
                    maxVisible: 4,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$confirmadosLine$pendientesLine',
                          style: MatchPayTokens.bodySmallStyle(),
                        ),
                      ),
                      if (sinResolver)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MatchPayTokens.accentUrgentBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: MatchPayTokens.accentUrgentBorder
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            l10n.tr('convocatoriaUnresolvedBadge'),
                            style: MatchPayTokens.sectionLabelStyle(
                              color: MatchPayTokens.accentUrgent,
                            ).copyWith(fontSize: 10, letterSpacing: 0),
                          ),
                        )
                      else if (listoGastos)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MatchPayTokens.accentCreditBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.tr('convocatoriaPastDateBadge'),
                            style: MatchPayTokens.sectionLabelStyle(
                              color: MatchPayTokens.accentCredit,
                            ).copyWith(fontSize: 10, letterSpacing: 0),
                          ),
                        ),
                    ],
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
    );
  }
}

/// FAB principal del organizador: crear partido o convocatoria.
class OrganizerPartidoFab extends StatelessWidget {
  final VoidCallback onPressed;

  const OrganizerPartidoFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FloatingActionButton.extended(
      heroTag: null,
      onPressed: onPressed,
      elevation: 6,
      backgroundColor: const Color(0xFF0F766E),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_rounded, size: 24),
      label: Text(
        l10n.tr('homeMatchFab'),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
