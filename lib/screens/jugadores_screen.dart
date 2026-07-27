import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/offline_status_controller.dart';
import '../l10n/matchpay_strings.dart';
import '../models/jugador.dart';
import '../offline/organizer_home_loader.dart';
import '../offline/offline_snapshot_store.dart';
import '../services/jugador_foto_service.dart';
import '../services/recordatorio_service.dart';
import '../services/whatsapp_share_service.dart';
import '../utils/formatters.dart';
import '../utils/jugador_name_filter.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../utils/organizador_participante_form.dart';
import '../utils/single_action.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/codigo_grupo_organizador_card.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/jugador_app_badge.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/offline_no_data_panel.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/shimmer_loading.dart';
import 'estadisticas_jugadores_screen.dart';

class JugadoresScreen extends StatefulWidget {
  const JugadoresScreen({super.key});

  @override
  State<JugadoresScreen> createState() => _JugadoresScreenState();
}

class _JugadoresScreenState extends State<JugadoresScreen> {
  static const _searchMinCount = 10;

  final _fotoService = JugadorFotoService.instance;
  final _busquedaCtrl = TextEditingController();
  List<Jugador> _jugadores = [];
  bool _loading = true;
  bool _offlineEmpty = false;
  String? _loadError;
  Timer? _reloadDebounce;
  String? _enviandoWhatsAppKey;

  @override
  void initState() {
    super.initState();
    _load();
    AppRepositories.dataRevision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _busquedaCtrl.dispose();
    AppRepositories.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  bool get _showSearch => _jugadores.length >= _searchMinCount;

  List<Jugador> get _jugadoresVisibles =>
      filterJugadoresByName(_jugadores, _busquedaCtrl.text);

  void _onDataChanged() {
    if (!mounted) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load(silent: true);
    });
  }

  void _showOfflineWriteBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('offlineWriteBlocked'))),
    );
  }

  bool _isReadOnly(BuildContext context) =>
      context.read<OfflineStatusController>().isReadOnly;

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
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
      final result = await loadOrganizerJugadores(
        repos: context.repos,
        snapshotStore: snapshotStore,
      );

      if (!mounted) return;

      switch (result.source) {
        case OfflineScreenLoadSource.live:
          offlineStatus.markLive();
          setState(() {
            _jugadores = result.data!.jugadores;
            _offlineEmpty = false;
            _loadError = null;
          });
        case OfflineScreenLoadSource.offlineCache:
          offlineStatus.markOfflineCached(result.snapshotAt!);
          setState(() {
            _jugadores = result.data!.jugadores;
            _offlineEmpty = false;
            _loadError = null;
          });
        case OfflineScreenLoadSource.offlineEmpty:
          offlineStatus.markOfflineEmpty();
          setState(() {
            _jugadores = [];
            _offlineEmpty = true;
          });
        case OfflineScreenLoadSource.error:
          offlineStatus.markLive();
          setState(() {
            _loadError = context.userError(result.error!);
          });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForm({Jugador? jugador}) async {
    if (_isReadOnly(context)) {
      _showOfflineWriteBlocked();
      return;
    }
    final saved = await showOrganizerParticipanteForm(
      context,
      jugador: jugador,
    );
    if (saved && mounted) await _load(silent: true);
  }

  Future<void> _enviarCobroWhatsApp(Jugador j) async {
    // j.saldoAcumulado = cuenta con ESTE organizador (RPC roster / oj).
    if (j.tieneMatchPayApp || !j.puedeEnviarWhatsApp || j.saldoAcumulado <= 0) {
      return;
    }
    final key = j.keyId;
    await runOnce('wa-cobro-jugador-$key', () async {
      setState(() => _enviandoWhatsAppKey = key);
      try {
        final msg = await RecordatorioService().construirMensaje(
          jugador: j,
          saldo: j.saldoAcumulado,
        );
        final ok = await WhatsAppShareService.enviar(
          mensaje: msg,
          telefono: j.contactWhatsApp,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok
                    ? context.l10n.tr('whatsappOpening')
                    : context.l10n.tr('whatsappOpenFailed'),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.userError(e)),
              backgroundColor: MatchPayTokens.accentError,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _enviandoWhatsAppKey = null);
      }
      return null;
    });
  }

  Future<void> _confirmDelete(Jugador j) async {
    if (_isReadOnly(context)) {
      _showOfflineWriteBlocked();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        final l10n = c.l10n;
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: MatchPayTokens.accentError,
            size: 36,
          ),
          title: Text(l10n.tr('deletePlayerTitle')),
          content: Text(
            l10n.tr('deletePlayerMessage', params: {'name': j.nombre}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.tr('no')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MatchPayTokens.accentError,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.tr('yesDelete')),
            ),
          ],
        );
      },
    );
    if (confirm == true) {
      await _fotoService.delete(j.fotoPath);
      if (!mounted) return;
      await context.repos.deleteJugador(j.keyId);
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final readOnly = context.watch<OfflineStatusController>().isReadOnly;
    final activos = _jugadores.where((j) => j.activo).length;
    final conDeuda = _jugadores.where((j) => j.saldoAcumulado > 0).length;
    final visibles = _jugadoresVisibles;
    final buscando = _showSearch && _busquedaCtrl.text.trim().isNotEmpty;

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(
        title: Text(l10n.tr('playersScreenTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: l10n.tr('statsTooltip'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EstadisticasJugadoresScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.tr('refreshTooltip'),
            onPressed: () => _load(silent: true),
          ),
        ],
      ),
      body: _loading &&
              _jugadores.isEmpty &&
              !_offlineEmpty &&
              _loadError == null
          ? const _JugadoresShimmer()
          : _offlineEmpty
              ? const OfflineNoDataPanel()
              : _loadError != null && _jugadores.isEmpty
                  ? _buildLoadErrorState()
                  : RefreshIndicator(
                      color: palette.primary,
                      onRefresh: () => _load(silent: true),
                      child: _jugadores.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: NavShellScope.listPadding(context),
                              children: [
                                _buildEmptyState(),
                                const SizedBox(height: 16),
                                const CodigoGrupoOrganizadorCard(),
                              ],
                            )
                          : ListView(
                              padding: NavShellScope.listPadding(
                                context,
                                left: 16,
                                top: 16,
                                right: 16,
                              ),
                              children: [
                                const CodigoGrupoOrganizadorCard(),
                                const SizedBox(height: 16),
                                _buildResumen(activos, conDeuda),
                                const SizedBox(height: 16),
                                AyudaTip(texto: l10n.tr('playersHelpTip')),
                                if (_showSearch) ...[
                                  const SizedBox(height: 16),
                                  _buildSearchField(l10n),
                                ],
                                const SizedBox(height: 16),
                                if (buscando && visibles.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 24,
                                    ),
                                    child: Text(
                                      l10n.tr('playersSearchEmpty'),
                                      textAlign: TextAlign.center,
                                      style: MatchPayTokens.bodySmallStyle(),
                                    ),
                                  )
                                else
                                  ...visibles.map(_buildJugadorCard),
                              ],
                            ),
                    ),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(
              heroTag: 'jugadores-new-player',
              onPressed: () => _showForm(),
              icon: const Icon(Icons.person_add_rounded),
              label: Text(l10n.tr('newPlayer')),
            ),
    );
  }

  Widget _buildSearchField(MatchPayStrings l10n) {
    return TextField(
      controller: _busquedaCtrl,
      decoration: InputDecoration(
        hintText: l10n.tr('playersSearchHint'),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _busquedaCtrl.text.trim().isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _busquedaCtrl.clear();
                  setState(() {});
                },
              ),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildLoadErrorState() {
    return FriendlyErrorPanel(
      message: _loadError ?? context.tr('errorGeneric'),
      onRetry: _load,
    );
  }

  Widget _buildEmptyState() {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MatchPayTokens.accentSuccessBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.groups_rounded,
              size: 72,
              color: MatchPayTokens.accentSuccess,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.tr('playersEmptyTitle'),
            style: MatchPayTokens.titleMediumStyle(),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr('playersEmptySubtitle'),
            textAlign: TextAlign.center,
            style: MatchPayTokens.bodySmallStyle(),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showForm(),
            icon: const Icon(Icons.person_add_rounded),
            label: Text(l10n.tr('addFirstPlayer')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(MatchPayTokens.radiusButton),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen(int activos, int conDeuda) {
    final l10n = context.l10n;

    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          MatchPayStatChip(
            icon: Icons.people_alt_rounded,
            iconColor: MatchPayTokens.accentCredit,
            value: '${_jugadores.length}',
            label: l10n.tr('total'),
          ),
          const SizedBox(width: 10),
          MatchPayStatChip(
            icon: Icons.star_rounded,
            iconColor: MatchPayTokens.accentUrgent,
            value: '$activos',
            label: l10n.tr('regulars'),
          ),
          const SizedBox(width: 10),
          MatchPayStatChip(
            icon: Icons.account_balance_wallet_rounded,
            iconColor: MatchPayTokens.accentError,
            value: '$conDeuda',
            label: l10n.tr('withDebt'),
          ),
        ],
      ),
    );
  }

  Widget _buildJugadorCard(Jugador j) {
    final l10n = context.l10n;
    final deuda = j.saldoAcumulado > 0;
    final conFavor = j.saldoAcumulado < 0;
    final sinAppManual = !j.tieneMatchPayApp && j.puedeEnviarWhatsApp && deuda;
    final enviandoWa = _enviandoWhatsAppKey == j.keyId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () => _showForm(jugador: j),
        child: MatchPaySurfaceCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          onTap: () =>
              Navigator.pushNamed(context, '/historial', arguments: j.keyId),
          child: Row(
          children: [
            JugadorAvatar(
              nombre: j.nombre,
              fotoPath: j.fotoPath,
              fotoUrl: j.fotoUrl,
              size: 52,
              borderRadius: MatchPayTokens.radiusChip,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          j.nombre,
                          style: MatchPayTokens.titleSmallStyle(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (j.activo) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: MatchPayTokens.accentUrgent,
                        ),
                      ],
                      const SizedBox(width: 6),
                      JugadorAppBadge(jugador: j, compact: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MiniChip(
                        icon: j.activo ? Icons.check_circle : Icons.pause_circle,
                        label: j.activo
                            ? l10n.tr('statusRegular')
                            : l10n.tr('statusInactive'),
                        color: j.activo
                            ? MatchPayTokens.accentSuccess
                            : MatchPayTokens.inkMuted,
                      ),
                      if (j.contactEmail != null)
                        _MiniChip(
                          icon: Icons.email_outlined,
                          label: j.contactEmail!,
                          color: MatchPayTokens.accentCredit,
                        ),
                      if (j.contactWhatsApp != null)
                        _MiniChip(
                          icon: Icons.chat_outlined,
                          label: formatWhatsAppDisplay(j.contactWhatsApp),
                          color: const Color(0xFF25D366),
                        ),
                    ],
                  ),
                  if (deuda) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l10n.tr('statusOwes')}: ${formatMoney(j.saldoAcumulado)}',
                      style: MatchPayTokens.titleSmallStyle(
                        color: MatchPayTokens.accentError,
                      ).copyWith(fontSize: 13),
                    ),
                  ] else if (conFavor) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l10n.tr('statusCredit')}: ${formatMoney(-j.saldoAcumulado)}',
                      style: MatchPayTokens.titleSmallStyle(
                        color: MatchPayTokens.accentCredit,
                      ).copyWith(fontSize: 13),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('tapToViewProfile'),
                      style: MatchPayTokens.bodySmallStyle().copyWith(
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                if (sinAppManual)
                  IconButton.filledTonal(
                    icon: enviandoWa
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.payments_outlined, size: 22),
                    tooltip: l10n.tr('sendDebtWhatsApp'),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFF1B8F4E),
                    ),
                    onPressed: enviandoWa ? null : () => _enviarCobroWhatsApp(j),
                  ),
                if (sinAppManual) const SizedBox(height: 4),
                IconButton.filledTonal(
                  icon: const Icon(Icons.edit_rounded, size: 22),
                  tooltip: l10n.tr('editTooltip'),
                  style: IconButton.styleFrom(
                    backgroundColor: MatchPayTokens.accentCreditBg,
                    foregroundColor: MatchPayTokens.accentCredit,
                  ),
                  onPressed: () => _showForm(jugador: j),
                ),
                const SizedBox(height: 4),
                IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline_rounded, size: 22),
                  tooltip: l10n.tr('deleteTooltip'),
                  style: IconButton.styleFrom(
                    backgroundColor: MatchPayTokens.accentErrorBg,
                    foregroundColor: MatchPayTokens.accentError,
                  ),
                  onPressed: () => _confirmDelete(j),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: MatchPayTokens.sectionLabelStyle(color: color).copyWith(
                letterSpacing: 0,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JugadoresShimmer extends StatelessWidget {
  const _JugadoresShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: NavShellScope.listPadding(context, left: 16, top: 16, right: 16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ShimmerLoading(
          height: 14,
          width: 120,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: Row(
            children: [
              Expanded(
                child: ShimmerLoading(
                  borderRadius: BorderRadius.circular(
                    MatchPayTokens.radiusCardSm,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ShimmerLoading(
                  borderRadius: BorderRadius.circular(
                    MatchPayTokens.radiusCardSm,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ShimmerLoading(
          height: 56,
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ShimmerLoading(
              height: 96,
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
            ),
          ),
        ),
      ],
    );
  }
}
