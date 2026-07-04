import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/convocatoria_jugador.dart';
import '../models/mi_convocatoria.dart';
import '../models/estado_pago_jugador.dart';
import '../models/jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import '../utils/app_navigation.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/mis_invitaciones_panel.dart';
import '../widgets/pagos_por_validar_panel.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/quick_actions_panel.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import 'mis_cobros_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;

  const HomeScreen({super.key, this.onNavigateTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pdfService = PdfService();

  List<ResumenJugador> _resumenes = [];
  List<Jugador> _jugadoresActivos = [];
  List<ConvocatoriaCompleta> _convocatorias = [];
  List<MiConvocatoria> _misInvitaciones = [];
  List<DetallePartido> _pagosPorValidar = [];
  List<DetallePartido> _misDeudas = [];
  final Map<int, DesgloseJugador?> _desglosePorPartido = {};
  bool _loading = true;
  bool _primeraCarga = true;
  Timer? _reloadDebounce;
  final Set<String> _planillaSeleccionados = {};
  TipoPago _tipoPagoPlanilla = TipoPago.total;
  final _montoParcialController = TextEditingController();

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
    _montoParcialController.dispose();
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
      final results = await Future.wait([
        repos.getResumenJugadores(),
        repos.getJugadores(soloActivos: true),
        repos.getConvocatoriasActivas(),
        MisInvitacionesPanel.cargarPendientes(repos),
        repos.isCloud
            ? repos.getPagosPorValidar()
            : Future<List<DetallePartido>>.value([]),
        repos.isCloud
            ? repos.getMisDeudasPendientes()
            : Future<List<DetallePartido>>.value([]),
      ]);
      final convocatorias = results[2] as List<ConvocatoriaCompleta>;
      if (mounted) {
        setState(() {
          _resumenes = results[0] as List<ResumenJugador>;
          _jugadoresActivos = results[1] as List<Jugador>;
          _convocatorias = convocatorias;
          _misInvitaciones = results[3] as List<MiConvocatoria>;
          _pagosPorValidar = results[4] as List<DetallePartido>;
          _misDeudas = ordenarDeudasPorFecha(results[5] as List<DetallePartido>);
          _desglosePorPartido.clear();
          _primeraCarga = false;
        });
      }
      unawaited(_cargarMisDesgloses(_misDeudas));
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

  double get _totalSaldos =>
      _resumenes.fold(0.0, (sum, r) => sum + r.deudaVisible);

  int get _conDeuda => _resumenes.where((r) => r.tieneDeuda).length;

  int get _alDia => _resumenes.where((r) => !r.tieneDeuda).length;

  List<ResumenJugador> get _deudoresOrdenados {
    return _resumenes.where((r) => r.tieneDeuda).toList()
      ..sort((a, b) => b.deudaVisible.compareTo(a.deudaVisible));
  }

  Future<void> _cargarMisDesgloses(List<DetallePartido> deudas) async {
    if (deudas.isEmpty || !mounted) return;
    try {
      final repos = context.repos;
      final ultimo = deudas.first;
      final desgloseUltimo =
          await repos.getMiDesglosePartido(ultimo.partidoId);
      if (mounted) {
        setState(() {
          _desglosePorPartido[ultimo.partidoId] = desgloseUltimo;
        });
      }
    } catch (_) {
      // Desglose opcional en inicio admin.
    }
  }

  List<ResumenJugador> get _todosOrdenados {
    final copy = List<ResumenJugador>.from(_resumenes);
    copy.sort((a, b) =>
        a.jugador.nombre.toLowerCase().compareTo(b.jugador.nombre.toLowerCase()));
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return ShellTabScaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      floatingActionButton: _PartidoFab(onPressed: _mostrarMenuPartido),
      body: _loading && _primeraCarga
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
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
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                      color: Color(0xFF111827),
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.tr('homeAdminTagline'),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.3,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.tr('appModeSwitchToPlayer'),
                              onPressed: () {
                                context.switchAppUiMode(AppUiMode.player);
                              },
                              icon: Icon(
                                Icons.person_outline_rounded,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.refreshTooltip,
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
                  SliverPadding(
                    padding: NavShellScope.listPadding(context, top: 16, bottom: 24),
                    sliver: SliverList(
                      delegate: // ignore: prefer_const_constructors
                          SliverChildListDelegate([
                        _buildHeader(),
                        const SizedBox(height: 20),
                        PagosPorValidarPanel(
                          pagos: _pagosPorValidar,
                          onValidado: _load,
                        ),
                        if (_pagosPorValidar.isNotEmpty)
                          const SizedBox(height: 16),
                        _buildMisCobrosOrganizer(),
                        const SizedBox(height: 16),
                        MisInvitacionesPanel(
                          convocatorias: _misInvitaciones,
                          onRespondido: _load,
                        ),
                        if (_convocatorias.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildConvocatoriasActivas(),
                          const SizedBox(height: 20),
                        ] else
                          const SizedBox(height: 8),
                        QuickActionsPanel(
                          repos: context.repos,
                          pdfService: _pdfService,
                          resumenes: _resumenes,
                          onRefresh: _load,
                          onNavigateTab: widget.onNavigateTab,
                        ),
                        const SizedBox(height: 20),
                        _buildPlanilla(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _mostrarMenuPartido() async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.tr('homeMatchMenuTitle'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.campaign, color: Colors.blue.shade800),
                ),
                title: Text(l10n.tr('homeOrganizeConvocatoria')),
                subtitle: Text(l10n.tr('homeOrganizeConvocatoriaSubtitle')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await abrirOrganizarPartido(context);
                  _load();
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Icon(Icons.payments, color: Colors.green.shade800),
                ),
                title: Text(l10n.tr('homeRegisterPlayedMatch')),
                subtitle: Text(l10n.tr('homeRegisterPlayedMatchSubtitle')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await abrirNuevoPartidoJugado(context);
                  _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirMisCobros() {
    final goTab = widget.onNavigateTab;
    if (goTab != null) {
      goTab(1);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MisCobrosScreen()),
    ).then((_) => _load());
  }

  Widget _buildMisCobrosOrganizer() {
    final l10n = context.l10n;
    final alDia = _misDeudas.isEmpty;

    if (alDia) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tr('myCharges'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.green.shade900,
                        ),
                      ),
                      Text(
                        l10n.tr('organizerPlayerUpToDate'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _abrirMisCobros,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(l10n.tr('viewMyChargesTab')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      );
    }

    final ultimo = _misDeudas.first;
    final deudaTotal = _misDeudas.fold<double>(
      0,
      (s, d) => s + montoATransferirCobro(d, _desglosePorPartido[d.partidoId]),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('myCharges'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    Text(
                      l10n.tr(
                        'playerPendingAmount',
                        params: {'amount': formatMoney(deudaTotal)},
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CobroPartidoCard(
            detalle: ultimo,
            desglose: _desglosePorPartido[ultimo.partidoId],
            compact: true,
            estadoExtra: estadoTextoCobro(ultimo, l10n),
          ),
          if (_misDeudas.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              l10n.tr(
                'playerTotalPendingSummary',
                params: {
                  'amount': formatMoney(deudaTotal),
                  'count': '${_misDeudas.length}',
                },
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _abrirMisCobros,
            icon: const Icon(Icons.payments_outlined),
            label: Text(l10n.tr('viewChargesAndPay')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ],
      ),
    );
  }

  Widget _buildConvocatoriasActivas() {
    final l10n = context.l10n;
    final enEspera =
        _convocatorias.where((c) => c.partido.esOrganizando).toList();
    final confirmadas =
        _convocatorias.where((c) => c.partido.esConfirmado).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8E6E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_rounded, color: Colors.blue.shade800),
              const SizedBox(width: 8),
              Text(
                l10n.tr('homeActiveConvocatorias'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (enEspera.isNotEmpty) ...[
            _ConvocatoriaGrupo(
              titulo: l10n.tr('homeWaiting'),
              icono: Icons.hourglass_top_rounded,
              color: Colors.blue,
              cantidad: enEspera.length,
            ),
            ...enEspera.map((c) => _ConvocatoriaTile(
                  convocatoria: c,
                  onTap: () async {
                    await abrirOrganizarPartido(
                      context,
                      partidoId: c.partido.id,
                    );
                    _load();
                  },
                )),
          ],
          if (confirmadas.isNotEmpty) ...[
            if (enEspera.isNotEmpty) const SizedBox(height: 10),
            _ConvocatoriaGrupo(
              titulo: l10n.tr('homeConfirmed'),
              icono: Icons.check_circle_rounded,
              color: Colors.green,
              cantidad: confirmadas.length,
            ),
            ...confirmadas.map((c) => _ConvocatoriaTile(
                  convocatoria: c,
                  confirmado: true,
                  onTap: () async {
                    await abrirOrganizarPartido(
                      context,
                      partidoId: c.partido.id,
                    );
                    _load();
                  },
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = context.l10n;
    final todosAlDia = _conDeuda == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
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
                  color: todosAlDia
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  todosAlDia
                      ? Icons.check_circle_rounded
                      : Icons.account_balance_wallet_rounded,
                  color: todosAlDia
                      ? const Color(0xFF065F46)
                      : const Color(0xFF92400E),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todosAlDia
                          ? l10n.tr('homeGroupAllPaid')
                          : l10n.tr('homeGroupSummary'),
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      todosAlDia
                          ? l10n.tr('homeNoPendingDebts')
                          : l10n.tr('homeAmountToCollect',
                              params: {'amount': formatMoney(_totalSaldos)}),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _HeaderStat(
                label: l10n.tr('homeStatPlayers'),
                value: '${_jugadoresActivos.length}',
                icon: Icons.people_rounded,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeaderStat(
                label: l10n.tr('homeStatWithDebt'),
                value: '$_conDeuda',
                icon: Icons.warning_amber_rounded,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeaderStat(
                label: l10n.tr('homeStatUpToDate'),
                value: '$_alDia',
                icon: Icons.check_circle_rounded,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanilla() {
    final l10n = context.l10n;
    if (_resumenes.isEmpty) {
      return _HomeSeccion(
        titulo: l10n.tr('homeManualPaymentsTitle'),
        icono: Icons.payments_rounded,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                l10n.tr('homeNoDataYet'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.tr('homeTapMatchToStart'),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final deudores = _deudoresOrdenados;

    if (deudores.isEmpty) {
      return _HomeSeccion(
        titulo: l10n.tr('homeRegisterPaymentsTitle'),
        icono: Icons.payments_rounded,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.green.shade700, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.tr('homeNobodyOwes'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildVerFichaButton(),
          ],
        ),
      );
    }

    return _HomeSeccion(
      titulo: l10n.tr('homeManualPaymentsTitle'),
      icono: Icons.payments_rounded,
      accion: IconButton(
        icon: Icon(Icons.help_outline_rounded, color: Colors.grey.shade600),
        tooltip: l10n.helpTooltip,
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.tr('homeManualPaymentsHelpTitle')),
              content: Text(l10n.tr('homeManualPaymentsHelpBody')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.understood),
                ),
              ],
            ),
          );
        },
      ),
      child: Column(
        children: [
          Text(
            l10n.tr('homeDebtorsSummary', params: {
              'count': '${deudores.length}',
              'amount': formatMoney(_totalSaldos),
            }),
            style: TextStyle(
              fontSize: 13,
              color: Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          ...deudores.map(_buildPlanillaFila),
          if (_planillaSeleccionados.isNotEmpty) _buildPlanillaAcciones(),
          _buildVerFichaButton(),
        ],
      ),
    );
  }

  Widget _buildVerFichaButton() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: _mostrarSelectorFicha,
        icon: const Icon(Icons.person_search_rounded, size: 18),
        label: Text(l10n.tr('homeViewPlayerProfile')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    );
  }

  Widget _buildPlanillaFila(ResumenJugador r) {
    final l10n = context.l10n;
    final saldo = r.deudaVisible;
    final id = r.jugador.keyId;
    final seleccionado = _planillaSeleccionados.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: seleccionado
            ? Colors.red.shade50
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _togglePlanillaSeleccion(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Checkbox(
                  value: seleccionado,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (_) => _togglePlanillaSeleccion(id),
                ),
                JugadorAvatar(
                  nombre: r.jugador.nombre,
                  fotoPath: r.jugador.fotoPath,
                  fotoUrl: r.jugador.fotoUrl,
                  size: 40,
                  borderRadius: 12,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.jugador.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        l10n.tr('matchesPlayedCount',
                            params: {'count': '${r.partidosJugados}'}),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    formatMoney(saldo),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanillaAcciones() {
    final l10n = context.l10n;
    final seleccionados = _resumenes
        .where((r) => _planillaSeleccionados.contains(r.jugador.keyId))
        .toList();
    final conDeuda =
        seleccionados.where((r) => r.tieneDeuda).toList();
    final uno = conDeuda.length == 1 ? conDeuda.first : null;
    final totalAbono =
        conDeuda.fold(0.0, (s, r) => s + r.deudaVisible);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.tr('homeSelectedPlayers',
                params: {'count': '${conDeuda.length}'}),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (conDeuda.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.tr('homeSelectedAllUpToDate'),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            )
          else if (uno != null) ...[
            const SizedBox(height: 10),
            Text(
              l10n.tr('homePlayerBalanceLine', params: {
                'name': uno.jugador.nombre,
                'amount': formatMoney(uno.deudaVisible),
              }),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 10),
            SegmentedButton<TipoPago>(
              segments: [
                ButtonSegment(
                  value: TipoPago.total,
                  label: Text(l10n.tr('homePayFull'),
                      style: const TextStyle(fontSize: 12)),
                  icon: const Icon(Icons.check_circle, size: 16),
                ),
                ButtonSegment(
                  value: TipoPago.parcial,
                  label: Text(l10n.tr('homePartialPayment'),
                      style: const TextStyle(fontSize: 12)),
                  icon: const Icon(Icons.savings_outlined, size: 16),
                ),
              ],
              selected: {_tipoPagoPlanilla},
              onSelectionChanged: (s) {
                setState(() {
                  _tipoPagoPlanilla = s.first;
                  if (s.first == TipoPago.parcial) {
                    _montoParcialController.clear();
                  }
                });
              },
            ),
            if (_tipoPagoPlanilla == TipoPago.parcial) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _montoParcialController,
                decoration: InputDecoration(
                  labelText: l10n.tr('homePartialAmountLabel'),
                  hintText: '0',
                  helperText: l10n.tr('homePartialAmountHelper'),
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  suffixText: l10n.tr('homeOwesSuffix',
                      params: {'amount': formatMoney(uno.deudaVisible)}),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: moneyInputFormatters,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _registrarPagoUnJugador(uno),
              icon: const Icon(Icons.payments),
              label: Text(
                _tipoPagoPlanilla == TipoPago.total
                    ? l10n.tr('homeRegisterFullPayment')
                    : l10n.tr('homeRegisterPartialPayment'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              l10n.tr('homeBatchPaymentNote',
                  params: {'amount': formatMoney(totalAbono)}),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _registrarPagoMultiple(conDeuda),
              icon: const Icon(Icons.done_all),
              label: Text(l10n.tr('homeRegisterFullPaymentCount',
                  params: {'count': '${conDeuda.length}'})),
            ),
          ],
          TextButton(
            onPressed: () {
              setState(() {
                _planillaSeleccionados.clear();
                _tipoPagoPlanilla = TipoPago.total;
                _montoParcialController.clear();
              });
            },
            child: Text(l10n.tr('homeClearSelection')),
          ),
        ],
      ),
    );
  }

  void _togglePlanillaSeleccion(String jugadorId) {
    setState(() {
      if (_planillaSeleccionados.contains(jugadorId)) {
        _planillaSeleccionados.remove(jugadorId);
      } else {
        _planillaSeleccionados.add(jugadorId);
      }
      _tipoPagoPlanilla = TipoPago.total;
      _montoParcialController.clear();
    });
  }

  Future<void> _registrarPagoUnJugador(ResumenJugador resumen) async {
    final l10n = context.l10n;
    final saldo = resumen.deudaVisible;
    final monto = _tipoPagoPlanilla == TipoPago.total
        ? saldo
        : roundMoney(parseMoney(_montoParcialController.text))
            .toDouble();

    if (monto <= 0) {
      _mostrarError(l10n.tr('errorAmountGreaterThanZero'));
      return;
    }

    final concepto = monto > saldo
        ? l10n.tr('paymentConceptWithCredit')
        : monto == saldo
            ? l10n.tr('paymentConceptFull')
            : l10n.tr('paymentConceptPartial');

    await context.repos.registrarAbono(
      jugadorId: resumen.jugador.keyId,
      monto: monto,
      concepto: concepto,
    );

    if (mounted) {
      setState(() {
        _planillaSeleccionados.clear();
        _tipoPagoPlanilla = TipoPago.total;
        _montoParcialController.clear();
      });
      final excedente = monto > saldo ? monto - saldo : 0.0;
      final msg = excedente > 0
          ? l10n.tr('snackPaymentWithCredit', params: {
              'amount': formatMoney(monto),
              'credit': formatMoney(excedente),
              'name': resumen.jugador.nombre,
            })
          : monto >= saldo
              ? l10n.tr('snackDebtCleared',
                  params: {'name': resumen.jugador.nombre})
              : l10n.tr('snackPartialPayment', params: {
                  'amount': formatMoney(monto),
                  'remaining': formatMoney(saldo - monto),
                  'name': resumen.jugador.nombre,
                });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      _load();
    }
  }

  Future<void> _registrarPagoMultiple(List<ResumenJugador> jugadores) async {
    final l10n = context.l10n;
    for (final r in jugadores) {
      await context.repos.registrarAbono(
        jugadorId: r.jugador.keyId,
        monto: r.deudaVisible,
        concepto: l10n.tr('paymentConceptFull'),
      );
    }

    if (mounted) {
      setState(() => _planillaSeleccionados.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('snackFullPaymentMultiple',
              params: {'count': '${jugadores.length}'})),
        ),
      );
      _load();
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  void _mostrarSelectorFicha() {
    final l10n = context.l10n;
    final todos = _todosOrdenados;
    if (todos.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tr('homePlayerSheetTitle'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.tr('homePlayerSheetSubtitle'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: todos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final r = todos[i];
                  return _FichaSelectorTile(
                    resumen: r,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(
                        context,
                        '/historial',
                        arguments: r.jugador.keyId,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _HomeSeccion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Widget child;
  final Widget? accion;

  const _HomeSeccion({
    required this.titulo,
    required this.icono,
    required this.child,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8E6E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icono, size: 20, color: const Color(0xFF374151)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              if (accion != null) accion!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ConvocatoriaGrupo extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final MaterialColor color;
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
          Icon(icono, size: 16, color: color.shade700),
          const SizedBox(width: 6),
          Text(
            '$titulo ($cantidad)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final MaterialColor color;

  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6E1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.shade700, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color.shade900,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FichaSelectorTile extends StatelessWidget {
  final ResumenJugador resumen;
  final VoidCallback onTap;

  const _FichaSelectorTile({
    required this.resumen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final saldo = resumen.deudaVisible;
    final deuda = saldo > 0;
    final conFavor = saldo < 0;

    final (estado, estadoColor, monto) = switch ((deuda, conFavor)) {
      (true, _) => (l10n.tr('statusOwes'), Colors.red, formatMoney(saldo)),
      (_, true) =>
        (l10n.tr('statusCredit'), Colors.blue, formatMoney(-saldo)),
      _ => (l10n.tr('statusUpToDate'), Colors.green, '—'),
    };

    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              JugadorAvatar(
                nombre: resumen.jugador.nombre,
                fotoPath: resumen.jugador.fotoPath,
                fotoUrl: resumen.jugador.fotoUrl,
                size: 44,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resumen.jugador.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.tr('homePlayerRowSubtitle', params: {
                        'count': '${resumen.partidosJugados}',
                      }),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: estadoColor.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: estadoColor.shade200),
                    ),
                    child: Text(
                      estado,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: estadoColor.shade800,
                      ),
                    ),
                  ),
                  if (deuda || conFavor) ...[
                    const SizedBox(height: 4),
                    Text(
                      monto,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: estadoColor.shade800,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConvocatoriaTile extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final bool confirmado;
  final VoidCallback onTap;

  const _ConvocatoriaTile({
    required this.convocatoria,
    required this.onTap,
    this.confirmado = false,
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

    return Material(
      color: confirmado ? Colors.green.shade50 : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: confirmado
                      ? Colors.green.shade100
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  confirmado ? Icons.check_circle_rounded : Icons.campaign_rounded,
                  color: confirmado
                      ? Colors.green.shade800
                      : Colors.blue.shade800,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fecha,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$recinto · $confirmadosLine$pendientesLine',
                      style: TextStyle(
                        fontSize: 12,
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
    );
  }
}

/// FAB principal: neutro (sin deporte), pero más presente visualmente.
class _PartidoFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _PartidoFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF115E59), Color(0xFF134E4A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 22, 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.tr('homeMatchFab'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
