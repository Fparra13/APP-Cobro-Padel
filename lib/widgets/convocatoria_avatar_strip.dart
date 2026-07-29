import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../utils/matchpay_context.dart';
import 'jugador_avatar.dart';

/// Máximo de avatares visibles antes de mostrar "+N".
const int kConvocatoriaAvatarsMaxVisible = 5;

enum ConvocatoriaAvatarStripMode {
  /// Ficha del jugador.
  player,

  /// Vista del organizador.
  organizer,
}

/// Qué participantes incluir en la tira.
enum ConvocatoriaAvatarStripFilter {
  /// Solo titulares confirmados (comportamiento histórico).
  confirmedOnly,

  /// Todos los titulares: confirmados, pendientes y “No va”.
  allInvitees,
}

/// Tira horizontal de avatares de convocatoria.
class ConvocatoriaAvatarStrip extends StatelessWidget {
  final List<ConvocatoriaJugadorEntry> titulares;
  final int cuposMax;
  final double size;
  final double overlap;
  final bool onDarkBackground;
  final int maxVisible;
  final ConvocatoriaAvatarStripMode mode;
  final ConvocatoriaAvatarStripFilter filter;
  final bool showStatusBadges;

  const ConvocatoriaAvatarStrip({
    super.key,
    required this.titulares,
    this.cuposMax = 4,
    this.size = 30,
    this.overlap = 22,
    this.onDarkBackground = false,
    this.maxVisible = kConvocatoriaAvatarsMaxVisible,
    this.mode = ConvocatoriaAvatarStripMode.organizer,
    this.filter = ConvocatoriaAvatarStripFilter.confirmedOnly,
    this.showStatusBadges = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.sportPalette;
    final layout = _layoutEntries();

    if (layout.items.isEmpty) return const SizedBox.shrink();

    final width = (layout.items.length - 1) * overlap + size;
    final badgeExtra = showStatusBadges ? size * 0.18 : 0.0;

    return SizedBox(
      height: size + 4 + badgeExtra,
      width: width + badgeExtra,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < layout.items.length; i++)
            Positioned(
              left: i * overlap,
              child: _buildItem(
                layout.items[i],
                palette: palette,
              ),
            ),
        ],
      ),
    );
  }

  _AvatarStripLayout _layoutEntries() {
    final entries = switch (filter) {
      ConvocatoriaAvatarStripFilter.confirmedOnly => titulares
          .where((j) => j.estado == EstadoConfirmacion.confirmado)
          .toList()
        ..sort((a, b) => a.jugador.nombre.compareTo(b.jugador.nombre)),
      ConvocatoriaAvatarStripFilter.allInvitees => _sortedAllInvitees(titulares),
    };

    return _layoutWithOverflow(entries);
  }

  static List<ConvocatoriaJugadorEntry> _sortedAllInvitees(
    List<ConvocatoriaJugadorEntry> titulares,
  ) {
    int rank(EstadoConfirmacion e) => switch (e) {
          EstadoConfirmacion.confirmado => 0,
          EstadoConfirmacion.invitado => 1,
          EstadoConfirmacion.rechazado || EstadoConfirmacion.noRespondio => 2,
        };

    return [...titulares]..sort((a, b) {
        final byEstado = rank(a.estado).compareTo(rank(b.estado));
        if (byEstado != 0) return byEstado;
        return a.jugador.nombre.compareTo(b.jugador.nombre);
      });
  }

  _AvatarStripLayout _layoutWithOverflow(List<ConvocatoriaJugadorEntry> entries) {
    if (entries.isEmpty) return const _AvatarStripLayout(items: []);

    if (entries.length <= maxVisible) {
      return _AvatarStripLayout(
        items: entries.map((e) => _AvatarStripItem(entry: e)).toList(),
      );
    }

    final visibleCount = maxVisible - 1;
    final overflow = entries.length - visibleCount;
    return _AvatarStripLayout(
      items: [
        ...entries
            .take(visibleCount)
            .map((e) => _AvatarStripItem(entry: e)),
        _AvatarStripItem(overflowCount: overflow),
      ],
    );
  }

  Widget _buildItem(
    _AvatarStripItem item, {
    required SportThemePalette palette,
  }) {
    if (item.overflowCount != null) {
      return _overflowChip(item.overflowCount!, palette);
    }
    return _avatarFor(item.entry!, palette);
  }

  Widget _overflowChip(int count, SportThemePalette palette) {
    final border = onDarkBackground
        ? Colors.white.withValues(alpha: 0.55)
        : palette.primary.withValues(alpha: 0.35);
    final fill = onDarkBackground
        ? Colors.white.withValues(alpha: 0.18)
        : palette.primary.withValues(alpha: 0.1);
    final textColor = onDarkBackground
        ? Colors.white
        : palette.primaryDark;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
        color: fill,
      ),
      child: Text(
        '+$count',
        style: TextStyle(
          color: textColor,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }

  Widget _avatarFor(
    ConvocatoriaJugadorEntry entry,
    SportThemePalette palette,
  ) {
    final estado = entry.estado;
    final declined = estado == EstadoConfirmacion.rechazado ||
        estado == EstadoConfirmacion.noRespondio;
    final confirmed = estado == EstadoConfirmacion.confirmado;

    final borderColor = onDarkBackground
        ? (confirmed
            ? const Color(0xFF69F0AE)
            : declined
                ? const Color(0xFFFF8A80)
                : Colors.white.withValues(alpha: 0.55))
        : (confirmed
            ? MatchPayTokens.accentSuccess
            : declined
                ? MatchPayTokens.accentError
                : const Color(0xFFF59E0B));

    final avatar = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: showStatusBadges ? 2.5 : 2),
      ),
      child: JugadorAvatar(
        nombre: entry.jugador.nombre,
        fotoUrl: entry.jugador.fotoUrl,
        fotoPath: entry.jugador.fotoPath,
        size: size,
        borderRadius: size / 2,
      ),
    );

    if (!showStatusBadges) {
      return Opacity(
        opacity: declined && filter == ConvocatoriaAvatarStripFilter.allInvitees
            ? 0.5
            : 1,
        child: avatar,
      );
    }

    final badgeSize = (size * 0.42).clamp(16.0, 24.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(
            opacity: declined ? 0.55 : 1,
            child: avatar,
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: _StatusBadge(estado: estado, size: badgeSize),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final EstadoConfirmacion estado;
  final double size;

  const _StatusBadge({required this.estado, required this.size});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData icon) = switch (estado) {
      EstadoConfirmacion.confirmado => (
          MatchPayTokens.accentSuccess,
          Colors.white,
          Icons.check_rounded,
        ),
      EstadoConfirmacion.invitado => (
          const Color(0xFFF59E0B),
          Colors.white,
          Icons.hourglass_top_rounded,
        ),
      EstadoConfirmacion.rechazado || EstadoConfirmacion.noRespondio => (
          MatchPayTokens.accentError,
          Colors.white,
          Icons.close_rounded,
        ),
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.68, color: fg, weight: 700),
    );
  }
}

class _AvatarStripLayout {
  final List<_AvatarStripItem> items;

  const _AvatarStripLayout({required this.items});
}

class _AvatarStripItem {
  final ConvocatoriaJugadorEntry? entry;
  final int? overflowCount;

  const _AvatarStripItem({this.entry, this.overflowCount});
}
