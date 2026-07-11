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

/// Solo avatares de titulares **confirmados**; la fila crece conforme confirman.
class ConvocatoriaAvatarStrip extends StatelessWidget {
  final List<ConvocatoriaJugadorEntry> titulares;
  final int cuposMax;
  final double size;
  final double overlap;
  final bool onDarkBackground;
  final int maxVisible;
  final ConvocatoriaAvatarStripMode mode;

  const ConvocatoriaAvatarStrip({
    super.key,
    required this.titulares,
    this.cuposMax = 4,
    this.size = 30,
    this.overlap = 22,
    this.onDarkBackground = false,
    this.maxVisible = kConvocatoriaAvatarsMaxVisible,
    this.mode = ConvocatoriaAvatarStripMode.organizer,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.sportPalette;
    final layout = _layoutConfirmedOnly();

    if (layout.items.isEmpty) return const SizedBox.shrink();

    final width = (layout.items.length - 1) * overlap + size;

    return SizedBox(
      height: size + 4,
      width: width,
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

  _AvatarStripLayout _layoutConfirmedOnly() {
    final entries = titulares
        .where((j) => j.estado == EstadoConfirmacion.confirmado)
        .toList()
      ..sort((a, b) => a.jugador.nombre.compareTo(b.jugador.nombre));

    return _layoutWithOverflow(entries);
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
    return _confirmedAvatar(item.entry!, palette);
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

  Widget _confirmedAvatar(
    ConvocatoriaJugadorEntry entry,
    SportThemePalette palette,
  ) {
    final borderColor = onDarkBackground
        ? palette.primaryDark
        : MatchPayTokens.accentSuccess;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: onDarkBackground ? const Color(0xFF69F0AE) : borderColor,
          width: 2,
        ),
      ),
      child: JugadorAvatar(
        nombre: entry.jugador.nombre,
        fotoUrl: entry.jugador.fotoUrl,
        fotoPath: entry.jugador.fotoPath,
        size: size,
        borderRadius: size / 2,
      ),
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
