import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../core/matchpay_design_tokens.dart';
import '../models/detalle_partido.dart';
import '../models/convocatoria_jugador.dart';
import '../models/mi_convocatoria.dart';
import '../models/cobros_resumen.dart';
import '../repositories/partido_repository.dart';
import '../domain/organizer_cycle_logic.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../utils/formatters.dart';
import '../utils/app_navigation.dart';
import '../utils/app_mode_pending.dart';
import '../widgets/pagos_por_validar_panel.dart';
import '../widgets/desglose_cobro_panel.dart' show ordenarDeudasPorFecha;
import '../widgets/quick_actions_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/app_mode_switch_button.dart';
import '../widgets/organizer_cycle_hero.dart';
import '../widgets/cobros_card.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/mis_invitaciones_panel.dart';

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
  List<MiConvocatoria> _misInvitaciones = [];
  List<DetallePartido> _pagosPorValidar = [];
  List<DetallePartido> _misDeudas = [];
  CobrosResumen _cobrosResumen = CobrosResumen.zero;
  bool _loading = true;
  bool _primeraCarga = true;
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
    if (!silent || _primeraCarga) {
      setState(() => _loading = true);
    }
    try {
      final repos = context.repos;
      // Reconciliar antes de cargar partidos para que hero y cobros coincidan.
      final resumenes = await repos.getResumenJugadores(
        reconciliar: false,
      );
      final cobrosResumen = cobrosResumenDesdeResumenes(resumenes);
      final results = await Future.wait([
        Future<List<ResumenJugador>>.value(resumenes),
        repos.getConvocatoriasActivas(),
        MisInvitacionesPanel.cargarPendientes(repos),
        repos.isCloud
            ? repos.getPagosPorValidar()
            : Future<List<DetallePartido>>.value([]),
        repos.isCloud
            ? repos.getMisDeudasPendientes()
            : Future<List<DetallePartido>>.value([]),
        repos.getPartidosJugadosRecientesResumen(limit: 8),
      ]);
      final convocatorias = results[1] as List<ConvocatoriaCompleta>;
      if (mounted) {
        setState(() {
          _resumenes = results[0] as List<ResumenJugador>;
          _convocatorias = convocatorias;
          _misInvitaciones = results[2] as List<MiConvocatoria>;
          _pagosPorValidar = results[3] as List<DetallePartido>;
          _misDeudas = ordenarDeudasPorFecha(results[4] as List<DetallePartido>);
          _partidosJugadosRecientes =
              results[5] as List<PartidoCompleto>;
          _cobrosResumen = cobrosResumen;
          _primeraCarga = false;
        });
      }
      unawaited(
        ConvocatoriaListaEsperaService().sincronizarPartidos(
          convocatorias
              .where((c) => c.partido.esOrganizando)
              .map((c) => c.partido.id)
              .whereType<int>(),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _playerPendingCount => playerModePendingCount(
        misDeudas: _misDeudas,
        misInvitaciones: _misInvitaciones,
      );

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
            snap.phase != OrganizerCyclePhase.registerExpenses)) {
      return _convocatorias;
    }
    return _convocatorias.where((c) => c.partido.id != featuredId).toList();
  }

  Future<void> _onCyclePrimaryAction() async {
    final snap = _cycleSnapshot;
    switch (snap.phase) {
      case OrganizerCyclePhase.empty:
        await showOrganizerMatchMenu(context);
      case OrganizerCyclePhase.preparing:
        final id = snap.convocatoria?.partido.id;
        if (id != null) {
          await abrirOrganizarPartido(context, partidoId: id);
        }
      case OrganizerCyclePhase.registerExpenses:
        final id = snap.convocatoria?.partido.id;
        if (id != null) {
          await Navigator.pushNamed(
            context,
            '/registrar-partido',
            arguments: id,
          );
        }
      case OrganizerCyclePhase.collecting:
        widget.onNavigateTab?.call(1);
      case OrganizerCyclePhase.allPaid:
        break;
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
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
                : RefreshIndicator(
                    color: palette.primary,
                    onRefresh: _load,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.homeAdminTitle,
                                    style: MatchPayTokens.displayStyle(),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    cycle.phaseLabel(l10n),
                                    style: MatchPayTokens.bodySmallStyle(
                                      color: palette.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppModeSwitchButton(
                              targetMode: AppUiMode.player,
                              pendingCount: _playerPendingCount,
                              onPressed: () {
                                context.switchAppUiMode(AppUiMode.player);
                              },
                            ),
                            IconButton(
                              tooltip: l10n.refreshTooltip,
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
                  SliverPadding(
                    padding: NavShellScope.listPadding(context, top: 16, bottom: 24),
                    sliver: SliverList(
                      delegate: // ignore: prefer_const_constructors
                          SliverChildListDelegate([
                        CobrosCard(
                          montoTotalPendiente:
                              _cobrosResumen.montoTotalPendiente,
                          jugadoresConDeuda:
                              _cobrosResumen.jugadoresConDeuda,
                          onVerCobros: widget.onNavigateTab != null
                              ? () => widget.onNavigateTab!(1)
                              : null,
                        ),
                        if (_mostrarHeroOperativo(cycle)) ...[
                          const SizedBox(height: 24),
                          OrganizerCycleHero(
                            snapshot: cycle,
                            onPrimaryAction: _onCyclePrimaryAction,
                            onCreateMatch: () =>
                                showOrganizerMatchMenu(context),
                          ),
                        ],
                        if (_pagosPorValidar
                            .any((d) => d.comprobantePendienteValidacion)) ...[
                          const SizedBox(height: 24),
                          MatchPaySectionHeader(
                            title: l10n.tr('paymentsToValidateTitle'),
                            count: _pagosPorValidar
                                .where(
                                  (d) => d.comprobantePendienteValidacion,
                                )
                                .length,
                            accent: true,
                          ),
                          const SizedBox(height: 10),
                          PagosPorValidarPanel(
                            pagos: _pagosPorValidar,
                            onValidado: _load,
                            prominent: false,
                          ),
                        ],
                        if (_convocatoriasEnLista.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          MatchPaySectionHeader(
                            title: l10n.tr('homeActiveConvocatorias'),
                            count: _convocatoriasEnLista.length,
                          ),
                          const SizedBox(height: 10),
                          _buildConvocatoriasActivas(_convocatoriasEnLista),
                        ],
                        const SizedBox(height: 24),
                        QuickActionsPanel(
                          resumenes: _resumenes,
                          onNavigateTab: widget.onNavigateTab,
                        ),
                        const SizedBox(height: 88),
                      ]),
                    ),
                  ),
                ],
                    ),
                  ),
          ),
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

  Widget _buildConvocatoriasActivas(List<ConvocatoriaCompleta> convocatorias) {
    final l10n = context.l10n;
    final vencidas = convocatorias
        .where((c) => c.partido.convocatoriaFechaPasada)
        .toList();
    final proximas = convocatorias
        .where((c) => !c.partido.convocatoriaFechaPasada)
        .toList();

    Widget grupos(List<ConvocatoriaCompleta> lista, {required bool fechaPasada}) {
      final enEspera =
          lista.where((c) => c.partido.esOrganizando).toList();
      final confirmadas =
          lista.where((c) => c.partido.esConfirmado).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enEspera.isNotEmpty) ...[
            if (!fechaPasada)
              _ConvocatoriaGrupo(
                titulo: l10n.tr('homeWaiting'),
                icono: Icons.hourglass_top_rounded,
                color: MatchPayTokens.accentCredit,
                cantidad: enEspera.length,
              ),
            ...enEspera.map(
              (c) => _ConvocatoriaTile(
                convocatoria: c,
                fechaPasada: fechaPasada,
                onTap: () async {
                  await abrirOrganizarPartido(
                    context,
                    partidoId: c.partido.id,
                  );
                  _load();
                },
              ),
            ),
          ],
          if (confirmadas.isNotEmpty) ...[
            if (enEspera.isNotEmpty) const SizedBox(height: 10),
            if (!fechaPasada)
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
                fechaPasada: fechaPasada,
                onTap: () async {
                  await abrirOrganizarPartido(
                    context,
                    partidoId: c.partido.id,
                  );
                  _load();
                },
              ),
            ),
          ],
        ],
      );
    }

    return MatchPaySurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vencidas.isNotEmpty) ...[
            _ConvocatoriaGrupo(
              titulo: l10n.tr('homePastConvocatorias'),
              icono: Icons.event_busy_rounded,
              color: MatchPayTokens.accentUrgent,
              cantidad: vencidas.length,
            ),
            Text(
              l10n.tr('homePastConvocatoriasHint'),
              style: MatchPayTokens.bodySmallStyle(
                color: MatchPayTokens.accentUrgent,
              ),
            ),
            const SizedBox(height: 8),
            grupos(vencidas, fechaPasada: true),
          ],
          if (proximas.isNotEmpty) ...[
            if (vencidas.isNotEmpty) const SizedBox(height: 14),
            grupos(proximas, fechaPasada: false),
          ],
        ],
      ),
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
  final bool fechaPasada;
  final VoidCallback onTap;

  const _ConvocatoriaTile({
    required this.convocatoria,
    required this.onTap,
    this.confirmado = false,
    this.fechaPasada = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = convocatoria;
    final fecha = formatDiaCorto(c.partido.fecha);
    final pendientes = c.invitados - c.confirmados - c.rechazados;
    final recinto = c.partido.recinto ?? l10n.tr('noVenue');
    final confirmadosLine = l10n.tr('homeConvocatoriaConfirmedLine', params: {
      'confirmed': '${c.confirmados}',
      'max': '${c.partido.cuposMax}',
    });
    final pendientesLine = !confirmado && pendientes > 0
        ? ' · ${l10n.tr('homeConvocatoriaPendingShort', params: {'count': '$pendientes'})}'
        : '';

    final tileColor = fechaPasada
        ? MatchPayTokens.accentUrgentBg
        : confirmado
            ? MatchPayTokens.accentSuccessBg
            : MatchPayTokens.surfaceInset;
    final iconBg = fechaPasada
        ? MatchPayTokens.accentUrgentBorder.withValues(alpha: 0.35)
        : confirmado
            ? MatchPayTokens.accentSuccess.withValues(alpha: 0.15)
            : MatchPayTokens.accentCredit.withValues(alpha: 0.12);
    final iconColor = fechaPasada
        ? MatchPayTokens.accentUrgent
        : confirmado
            ? MatchPayTokens.accentSuccess
            : MatchPayTokens.accentCredit;
    final iconData = fechaPasada
        ? Icons.event_busy_rounded
        : confirmado
            ? Icons.check_circle_rounded
            : Icons.campaign_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: tileColor,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
        child: InkWell(
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      Row(
                        children: [
                          Text(
                            fecha,
                            style: MatchPayTokens.titleSmallStyle(),
                          ),
                          if (fechaPasada) ...[
                            const SizedBox(width: 6),
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
                                l10n.tr('convocatoriaPastDateBadge'),
                                style: MatchPayTokens.sectionLabelStyle(
                                  color: MatchPayTokens.accentUrgent,
                                ).copyWith(fontSize: 10, letterSpacing: 0),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '$recinto · $confirmadosLine$pendientesLine',
                        style: MatchPayTokens.bodySmallStyle(),
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
