import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/offline_status_controller.dart';
import '../domain/organizer_cycle_logic.dart';
import '../l10n/matchpay_strings.dart';
import '../models/cobros_resumen.dart';
import '../offline/organizer_home_loader.dart';
import '../offline/organizer_home_snapshot.dart';
import '../offline/offline_snapshot_store.dart';
import '../repositories/partido_repository.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/cobros_card.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/offline_no_data_panel.dart';

enum _FiltroCobros { todos, conDeuda, alDia, credito }

/// Cartera de cobros del grupo (organizador).
class OrganizerCobrosScreen extends StatefulWidget {
  const OrganizerCobrosScreen({super.key});

  @override
  State<OrganizerCobrosScreen> createState() => _OrganizerCobrosScreenState();
}

class _OrganizerCobrosScreenState extends State<OrganizerCobrosScreen> {
  List<ResumenJugador> _resumenes = [];
  CobrosResumen _resumen = CobrosResumen.zero;
  _FiltroCobros _filtro = _FiltroCobros.todos;
  bool _loading = true;
  bool _offlineEmpty = false;
  String? _loadError;
  Timer? _reloadDebounce;

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
      final result = await loadOrganizerCobros(
        repos: context.repos,
        snapshotStore: snapshotStore,
      );

      if (!mounted) return;

      switch (result.source) {
        case OfflineScreenLoadSource.live:
          offlineStatus.markLive();
          _applyData(result.data!);
        case OfflineScreenLoadSource.offlineCache:
          offlineStatus.markOfflineCached(result.snapshotAt!);
          _applyData(result.data!);
        case OfflineScreenLoadSource.offlineEmpty:
          offlineStatus.markOfflineEmpty();
          setState(() {
            _resumenes = [];
            _resumen = CobrosResumen.zero;
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

  void _applyData(OrganizerCobrosData data) {
    setState(() {
      _resumenes = data.resumenes;
      _resumen = cobrosResumenDesdeResumenes(data.resumenes);
      _offlineEmpty = false;
      _loadError = null;
    });
  }

  List<ResumenJugador> get _filtrados {
    final copy = List<ResumenJugador>.from(_resumenes);
    copy.sort((a, b) {
      final cmp = b.deudaVisible.compareTo(a.deudaVisible);
      if (cmp != 0) return cmp;
      return a.jugador.nombre
          .toLowerCase()
          .compareTo(b.jugador.nombre.toLowerCase());
    });
    return switch (_filtro) {
      _FiltroCobros.todos => copy,
      _FiltroCobros.conDeuda => copy.where((r) => r.tieneDeuda).toList(),
      _FiltroCobros.alDia =>
        copy.where((r) => !r.tieneDeuda && !r.tieneCredito).toList(),
      _FiltroCobros.credito => copy.where((r) => r.tieneCredito).toList(),
    };
  }

  void _abrirFicha(String jugadorKey) {
    Navigator.pushNamed(context, '/historial', arguments: jugadorKey);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lista = _filtrados;

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(
        title: Text(l10n.tr('cobrosCardTitle')),
        backgroundColor: context.sportPrimary,
        foregroundColor: Colors.white,
      ),
      body: _loading && _resumenes.isEmpty && !_offlineEmpty && _loadError == null
          ? const PlayerHomeShimmer()
          : _offlineEmpty
              ? const OfflineNoDataPanel()
              : _loadError != null && _resumenes.isEmpty
                  ? _buildErrorState()
                  : RefreshIndicator(
                      onRefresh: () => _load(silent: true),
                      child: ListView(
                        padding: NavShellScope.listPadding(
                          context,
                          top: 16,
                          bottom: 24,
                        ),
                        children: [
                          CobrosCard(
                            montoTotalPendiente: _resumen.montoTotalPendiente,
                            jugadoresConDeuda: _resumen.jugadoresConDeuda,
                            showAction: false,
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FiltroChip(
                                  label: l10n.tr('organizerCobrosFilterAll'),
                                  selected: _filtro == _FiltroCobros.todos,
                                  onTap: () => setState(
                                    () => _filtro = _FiltroCobros.todos,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _FiltroChip(
                                  label: l10n.tr('organizerCobrosFilterDebt'),
                                  selected: _filtro == _FiltroCobros.conDeuda,
                                  onTap: () => setState(
                                    () => _filtro = _FiltroCobros.conDeuda,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _FiltroChip(
                                  label:
                                      l10n.tr('organizerCobrosFilterUpToDate'),
                                  selected: _filtro == _FiltroCobros.alDia,
                                  onTap: () => setState(
                                    () => _filtro = _FiltroCobros.alDia,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _FiltroChip(
                                  label: l10n.tr('organizerCobrosFilterCredit'),
                                  selected: _filtro == _FiltroCobros.credito,
                                  onTap: () => setState(
                                    () => _filtro = _FiltroCobros.credito,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (lista.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Text(
                                  l10n.tr('organizerCobrosEmptyFilter'),
                                  style: MatchPayTokens.bodySmallStyle(),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            ...lista.map(
                              (r) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _JugadorCobroTile(
                                  resumen: r,
                                  onTap: () => _abrirFicha(r.jugador.keyId),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildErrorState() {
    return FriendlyErrorPanel(
      message: _loadError ?? context.tr('errorGeneric'),
      onRetry: _load,
    );
  }
}

class _FiltroChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FiltroChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: context.sportPrimary.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? context.sportPrimaryDark : MatchPayTokens.inkSecondary,
      ),
    );
  }
}

class _JugadorCobroTile extends StatelessWidget {
  final ResumenJugador resumen;
  final VoidCallback onTap;

  const _JugadorCobroTile({
    required this.resumen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final j = resumen.jugador;

    final String estado;
    final Color color;
    final String monto;
    if (resumen.tieneDeuda) {
      estado = l10n.tr('statusOwes');
      color = MatchPayTokens.accentError;
      monto = formatMoney(resumen.deudaVisible);
    } else if (resumen.tieneCredito) {
      estado = l10n.tr('statusCredit');
      color = MatchPayTokens.accentCredit;
      monto = formatMoney(resumen.creditoVisible);
    } else {
      estado = l10n.tr('statusUpToDate');
      color = MatchPayTokens.accentSuccess;
      monto = '—';
    }

    return MatchPaySurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          JugadorAvatar(
            nombre: j.nombre,
            fotoPath: j.fotoPath,
            fotoUrl: j.fotoUrl,
            size: 48,
            borderRadius: MatchPayTokens.radiusChip,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  j.nombre,
                  style: MatchPayTokens.titleSmallStyle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  estado,
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (resumen.tieneDeuda || resumen.tieneCredito)
            Text(
              monto,
              style: MatchPayTokens.statValueStyle(color: color).copyWith(
                fontSize: 16,
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: MatchPayTokens.inkMuted),
        ],
      ),
    );
  }
}
