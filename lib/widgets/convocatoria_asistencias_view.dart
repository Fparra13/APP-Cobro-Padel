import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'jugador_avatar.dart';
import 'matchpay_ui.dart';
import 'sport_icon.dart';

class ConvocatoriaAsistenciaItem {
  final Jugador jugador;
  final EstadoConfirmacion estado;
  final bool esSuplente;

  const ConvocatoriaAsistenciaItem({
    required this.jugador,
    required this.estado,
    this.esSuplente = false,
  });
}

/// Vista de seguimiento estilo “Asistencias” (hero + stats + secciones).
class ConvocatoriaAsistenciasView extends StatefulWidget {
  final DateTime fecha;
  final String recinto;
  final SportType sportType;
  final int cuposMax;
  final int cuposSuplentesMax;
  final String statusLabel;
  final List<ConvocatoriaAsistenciaItem> titulares;
  final List<ConvocatoriaAsistenciaItem> suplentes;
  final Widget? topBanner;
  final ValueChanged<String>? onCycleEstado;
  final VoidCallback? onRemindPending;

  const ConvocatoriaAsistenciasView({
    super.key,
    required this.fecha,
    required this.recinto,
    required this.sportType,
    required this.cuposMax,
    this.cuposSuplentesMax = 5,
    required this.statusLabel,
    required this.titulares,
    required this.suplentes,
    this.topBanner,
    this.onCycleEstado,
    this.onRemindPending,
  });

  @override
  State<ConvocatoriaAsistenciasView> createState() =>
      _ConvocatoriaAsistenciasViewState();
}

class _ConvocatoriaAsistenciasViewState
    extends State<ConvocatoriaAsistenciasView> {
  static const _previewLimit = 4;
  static const _holdDeclined = Duration(milliseconds: 750);
  static const _highlightFor = Duration(milliseconds: 1800);

  bool _expandTitulares = false;
  bool _expandSuplentes = false;
  bool _expandNoAsisten = false;

  /// Mantiene al jugador en Titulares un instante con badge «No asiste».
  String? _holdingDeclinedId;
  /// Resalta la fila al llegar a «No asisten».
  String? _highlightId;
  Timer? _holdTimer;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }

  int get _confirmados => widget.titulares
      .where((e) => e.estado == EstadoConfirmacion.confirmado)
      .length;

  int get _pendientes => widget.titulares
      .where(
        (e) =>
            e.estado == EstadoConfirmacion.invitado ||
            e.estado == EstadoConfirmacion.noRespondio,
      )
      .length;

  int get _noAsistenCount => widget.titulares
      .where((e) => e.estado == EstadoConfirmacion.rechazado)
      .length;

  int get _invitados => widget.titulares.length + widget.suplentes.length;

  List<ConvocatoriaAsistenciaItem> get _noAsisten => widget.titulares
      .where((e) {
        if (e.jugador.keyId == _holdingDeclinedId) return false;
        return e.estado == EstadoConfirmacion.rechazado;
      })
      .toList();

  /// Titulares en cupo; durante el hold también el que acaba de pasar a no asiste.
  List<ConvocatoriaAsistenciaItem> get _titularesEnCupo => widget.titulares
      .where((e) {
        if (e.jugador.keyId == _holdingDeclinedId) return true;
        return e.estado != EstadoConfirmacion.rechazado;
      })
      .toList();

  ConvocatoriaAsistenciaItem? _itemById(String id) {
    for (final e in widget.titulares) {
      if (e.jugador.keyId == id) return e;
    }
    for (final e in widget.suplentes) {
      if (e.jugador.keyId == id) return e;
    }
    return null;
  }

  void _mostrarSnackEstado(String nombre, EstadoConfirmacion estado) {
    final l10n = context.l10n;
    final key = switch (estado) {
      EstadoConfirmacion.confirmado => 'asistenciasManualSnackConfirmed',
      EstadoConfirmacion.rechazado => 'asistenciasManualSnackDeclined',
      EstadoConfirmacion.invitado ||
      EstadoConfirmacion.noRespondio =>
        'asistenciasManualSnackPending',
    };
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.tr(key, params: {'name': nombre})),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onCycleEstado(String id) {
    final onCycle = widget.onCycleEstado;
    if (onCycle == null) return;
    final item = _itemById(id);
    if (item == null) return;

    final actual = item.estado;
    final siguiente = actual.siguiente();
    HapticFeedback.selectionClick();

    if (siguiente == EstadoConfirmacion.rechazado &&
        actual != EstadoConfirmacion.rechazado) {
      _holdTimer?.cancel();
      _highlightTimer?.cancel();
      setState(() {
        _holdingDeclinedId = id;
        _expandNoAsisten = true;
        _highlightId = null;
      });
      onCycle(id);
      _mostrarSnackEstado(item.jugador.nombre, siguiente);
      _holdTimer = Timer(_holdDeclined, () {
        if (!mounted) return;
        setState(() {
          if (_holdingDeclinedId == id) _holdingDeclinedId = null;
          _highlightId = id;
        });
        _highlightTimer = Timer(_highlightFor, () {
          if (!mounted) return;
          if (_highlightId == id) setState(() => _highlightId = null);
        });
      });
      return;
    }

    onCycle(id);
    _mostrarSnackEstado(item.jugador.nombre, siguiente);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final fechaLine =
        '${formatFechaLegibleCorta(widget.fecha)} · ${formatHora(widget.fecha)}';
    final lugarLine =
        '${widget.recinto.isEmpty ? '—' : widget.recinto} · ${widget.sportType.labelEs}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (widget.topBanner != null) ...[
          widget.topBanner!,
          const SizedBox(height: 12),
        ],
        MatchPaySurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: SportIcon(
                    sport: widget.sportType,
                    size: 24,
                    color: palette.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fechaLine,
                      style: MatchPayTokens.titleSmallStyle().copyWith(
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lugarLine,
                      style: MatchPayTokens.bodySmallStyle(),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: MatchPayTokens.accentSuccessBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.statusLabel,
                  style: MatchPayTokens.titleSmallStyle(
                    color: MatchPayTokens.accentSuccess,
                  ).copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.check_circle_rounded,
                color: MatchPayTokens.accentSuccess,
                value: '$_confirmados',
                label: l10n.tr('asistenciasStatConfirmed'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                icon: Icons.schedule_rounded,
                color: MatchPayTokens.accentUrgent,
                value: '$_pendientes',
                label: l10n.tr('asistenciasStatPending'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                icon: Icons.cancel_rounded,
                color: MatchPayTokens.accentError,
                value: '$_noAsistenCount',
                label: l10n.tr('asistenciasStatDeclined'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                icon: Icons.groups_rounded,
                color: MatchPayTokens.accentCredit,
                value: '$_invitados',
                label: l10n.tr('asistenciasStatInvited'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionCard(
          icon: Icons.groups_rounded,
          iconColor: MatchPayTokens.accentSuccess,
          title: l10n.tr(
            'asistenciasStartersTitle',
            params: {'count': '${_titularesEnCupo.length}'},
          ),
          badge: '$_confirmados/${widget.cuposMax}',
          badgeColor: MatchPayTokens.accentSuccess,
          items: _titularesEnCupo,
          expanded: _expandTitulares,
          previewLimit: _previewLimit,
          onToggleExpand: () =>
              setState(() => _expandTitulares = !_expandTitulares),
          expandLabel: l10n.tr('asistenciasSeeAllStarters'),
          collapseLabel: l10n.tr('asistenciasCollapse'),
          onCycleEstado:
              widget.onCycleEstado == null ? null : _onCycleEstado,
          highlightId: _highlightId ?? _holdingDeclinedId,
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.person_add_alt_1_rounded,
          iconColor: MatchPayTokens.accentUrgent,
          title: l10n.tr(
            'asistenciasSubsTitle',
            params: {'count': '${widget.suplentes.length}'},
          ),
          badge: '${widget.suplentes.length}/${widget.cuposSuplentesMax}',
          badgeColor: MatchPayTokens.accentUrgent,
          items: widget.suplentes,
          expanded: _expandSuplentes,
          previewLimit: _previewLimit,
          onToggleExpand: () =>
              setState(() => _expandSuplentes = !_expandSuplentes),
          expandLabel: l10n.tr('asistenciasSeeAllSubs'),
          collapseLabel: l10n.tr('asistenciasCollapse'),
          emptyLabel: l10n.tr('asistenciasSubsEmpty'),
          onCycleEstado:
              widget.onCycleEstado == null ? null : _onCycleEstado,
          highlightId: _highlightId,
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.cancel_outlined,
          iconColor: MatchPayTokens.accentError,
          title: l10n.tr(
            'asistenciasDeclinedTitle',
            params: {'count': '${_noAsisten.length}'},
          ),
          badge: '${_noAsisten.length}',
          badgeColor: MatchPayTokens.accentError,
          items: _noAsisten,
          expanded: _expandNoAsisten,
          previewLimit: _previewLimit,
          onToggleExpand: () =>
              setState(() => _expandNoAsisten = !_expandNoAsisten),
          expandLabel: l10n.tr('asistenciasSeeAllDeclined'),
          collapseLabel: l10n.tr('asistenciasCollapse'),
          emptyLabel: l10n.tr('asistenciasDeclinedEmpty'),
          onCycleEstado:
              widget.onCycleEstado == null ? null : _onCycleEstado,
          highlightId: _highlightId,
        ),
        const SizedBox(height: 72),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: MatchPayTokens.surfaceCard,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        border: Border.all(color: MatchPayTokens.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 16),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String badge;
  final Color badgeColor;
  final List<ConvocatoriaAsistenciaItem> items;
  final bool expanded;
  final int previewLimit;
  final VoidCallback onToggleExpand;
  final String expandLabel;
  final String collapseLabel;
  final String? emptyLabel;
  final ValueChanged<String>? onCycleEstado;
  final String? highlightId;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.items,
    required this.expanded,
    required this.previewLimit,
    required this.onToggleExpand,
    required this.expandLabel,
    required this.collapseLabel,
    this.emptyLabel,
    this.onCycleEstado,
    this.highlightId,
  });

  @override
  Widget build(BuildContext context) {
    final visible =
        expanded ? items : items.take(previewLimit).toList(growable: false);
    final canExpand = items.length > previewLimit;

    return MatchPaySurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 15),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: MatchPayTokens.titleSmallStyle(color: badgeColor)
                      .copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                emptyLabel ?? '',
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkMuted,
                ),
              ),
            )
          else
            ...visible.map(
              (item) => _PlayerRow(
                item: item,
                onCycleEstado: onCycleEstado,
                highlighted: highlightId != null &&
                    highlightId == item.jugador.keyId,
              ),
            ),
          if (canExpand)
            TextButton(
              onPressed: onToggleExpand,
              style: TextButton.styleFrom(
                foregroundColor: iconColor,
                padding: const EdgeInsets.symmetric(vertical: 4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    expanded ? collapseLabel : expandLabel,
                    style: MatchPayTokens.titleSmallStyle(color: iconColor)
                        .copyWith(fontSize: 12),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: iconColor,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final ConvocatoriaAsistenciaItem item;
  final ValueChanged<String>? onCycleEstado;
  final bool highlighted;

  const _PlayerRow({
    required this.item,
    this.onCycleEstado,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final j = item.jugador;
    final manual = onCycleEstado != null && !j.tieneMatchPayApp;
    final (label, fg, bg) = switch (item.estado) {
      EstadoConfirmacion.confirmado => (
          l10n.tr('asistenciasBadgeConfirmed'),
          MatchPayTokens.accentSuccess,
          MatchPayTokens.accentSuccessBg,
        ),
      EstadoConfirmacion.rechazado => (
          l10n.tr('asistenciasBadgeDeclined'),
          MatchPayTokens.accentError,
          MatchPayTokens.accentErrorBg,
        ),
      EstadoConfirmacion.noRespondio || EstadoConfirmacion.invitado => (
          l10n.tr('asistenciasBadgePending'),
          MatchPayTokens.accentUrgent,
          MatchPayTokens.accentUrgentBg,
        ),
    };

    final statusChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: manual
            ? Border.all(color: fg.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (manual) ...[
            Icon(Icons.touch_app_rounded, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: MatchPayTokens.titleSmallStyle(color: fg)
                .copyWith(fontSize: 11),
          ),
        ],
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted
            ? MatchPayTokens.accentErrorBg
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: highlighted
            ? Border.all(
                color: MatchPayTokens.accentError.withValues(alpha: 0.45),
              )
            : Border.all(color: Colors.transparent),
      ),
      child: Row(
        children: [
          JugadorAvatar(
            nombre: j.nombre,
            fotoPath: j.fotoPath,
            fotoUrl: j.fotoUrl,
            size: 40,
            borderRadius: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  j.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      MatchPayTokens.titleSmallStyle().copyWith(fontSize: 14),
                ),
                if (manual)
                  Text(
                    l10n.tr('asistenciasManualConfirm'),
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkMuted,
                    ).copyWith(fontSize: 11),
                  ),
              ],
            ),
          ),
          if (manual)
            Tooltip(
              message: l10n.tr('asistenciasChangeStatusTooltip'),
              child: InkWell(
                onTap: () => onCycleEstado!(j.keyId),
                borderRadius: BorderRadius.circular(999),
                child: statusChip,
              ),
            )
          else
            statusChip,
        ],
      ),
    );
  }
}
