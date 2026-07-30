import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import 'convocatoria_avatar_strip.dart';
import 'jugador_avatar.dart';

/// Altura fija gemela (avatar protagonista + tipografía fina hasta 2 líneas).
const double kParticipanteCapsuleHeight = 56;

/// Matriz de desaturación para avatares pendientes / sin respuesta.
const ColorFilter _kGreyscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// Rejilla de participantes estilo cápsula (Fitness+).
///
/// Pastillas gemelas sin iconos de estado: el avatar es protagonista y comunica
/// confirmado (color), pendiente (gris) o rechazado (cápsula atenuada).
class ParticipanteCapsuleStrip extends StatelessWidget {
  final List<ConvocatoriaJugadorEntry> titulares;
  final ConvocatoriaAvatarStripFilter filter;
  final double height;
  final double avatarSize;
  final double spacing;
  final int crossAxisCount;

  const ParticipanteCapsuleStrip({
    super.key,
    required this.titulares,
    this.filter = ConvocatoriaAvatarStripFilter.allInvitees,
    this.height = kParticipanteCapsuleHeight,
    this.avatarSize = 44,
    this.spacing = 8,
    this.crossAxisCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    final entries = _filteredSorted(titulares, filter);
    if (entries.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = crossAxisCount.clamp(1, 4);
        final maxW = constraints.maxWidth;
        final usableWidth = maxW.isFinite && maxW > 0 ? maxW : 320.0;
        final cellWidth =
            (usableWidth - spacing * (columns - 1)) / columns;
        final aspectRatio = cellWidth / height;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            return _ParticipanteCapsule(
              entry: entries[index],
              avatarSize: avatarSize,
            );
          },
        );
      },
    );
  }

  static List<ConvocatoriaJugadorEntry> _filteredSorted(
    List<ConvocatoriaJugadorEntry> titulares,
    ConvocatoriaAvatarStripFilter filter,
  ) {
    final list = switch (filter) {
      ConvocatoriaAvatarStripFilter.confirmedOnly => titulares
          .where((j) => j.estado == EstadoConfirmacion.confirmado)
          .toList(),
      ConvocatoriaAvatarStripFilter.allInvitees => [...titulares],
    };

    int rank(EstadoConfirmacion e) => switch (e) {
          EstadoConfirmacion.confirmado => 0,
          EstadoConfirmacion.invitado => 1,
          EstadoConfirmacion.rechazado || EstadoConfirmacion.noRespondio => 2,
        };

    list.sort((a, b) {
      final byEstado = rank(a.estado).compareTo(rank(b.estado));
      if (byEstado != 0) return byEstado;
      return a.jugador.nombre.compareTo(b.jugador.nombre);
    });
    return list;
  }
}

class _ParticipanteCapsule extends StatelessWidget {
  final ConvocatoriaJugadorEntry entry;
  final double avatarSize;

  const _ParticipanteCapsule({
    required this.entry,
    required this.avatarSize,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = entry.jugador.nombre.trim().isEmpty
        ? context.l10n.tr('playerDefaultName')
        : entry.jugador.nombre.trim();
    final statusKey = _statusKey(entry.estado);
    final chrome = _chromeFor(entry.estado);
    final isDeclined = entry.estado == EstadoConfirmacion.rechazado ||
        entry.estado == EstadoConfirmacion.noRespondio;

    final capsule = SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: chrome.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: chrome.border, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StatusAvatar(
                  estado: entry.estado,
                  child: JugadorAvatar(
                    nombre: nombre,
                    fotoUrl: entry.jugador.fotoUrl,
                    fotoPath: entry.jugador.fotoPath,
                    size: avatarSize,
                    borderRadius: avatarSize / 2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nombre,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle(
                      color: chrome.foreground,
                    ).copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      label: '$nombre, ${context.l10n.tr(statusKey)}',
      child: isDeclined
          ? Opacity(opacity: 0.5, child: capsule)
          : capsule,
    );
  }

  static String _statusKey(EstadoConfirmacion estado) => switch (estado) {
        EstadoConfirmacion.confirmado => 'statusConfirmed',
        EstadoConfirmacion.invitado => 'statusPending',
        EstadoConfirmacion.rechazado ||
        EstadoConfirmacion.noRespondio =>
          'statusDeclined',
      };

  static _CapsuleChrome _chromeFor(EstadoConfirmacion estado) {
    switch (estado) {
      case EstadoConfirmacion.confirmado:
        return const _CapsuleChrome(
          background: Color(0xFFF3F4F6),
          border: Color(0xFFE5E7EB),
          foreground: MatchPayTokens.ink,
        );
      case EstadoConfirmacion.invitado:
        return const _CapsuleChrome(
          background: Color(0xFFF3F4F6),
          border: Color(0xFFE5E7EB),
          foreground: MatchPayTokens.ink,
        );
      case EstadoConfirmacion.rechazado:
      case EstadoConfirmacion.noRespondio:
        return const _CapsuleChrome(
          background: Color(0xFFF8EFEF),
          border: Color(0xFFE8C9C9),
          foreground: Color(0xFF6B4F4F),
        );
    }
  }
}

class _CapsuleChrome {
  final Color background;
  final Color border;
  final Color foreground;

  const _CapsuleChrome({
    required this.background,
    required this.border,
    required this.foreground,
  });
}

/// Tratamiento visual del avatar según [EstadoConfirmacion] (sin iconos).
class _StatusAvatar extends StatelessWidget {
  final EstadoConfirmacion estado;
  final Widget child;

  const _StatusAvatar({
    required this.estado,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    switch (estado) {
      case EstadoConfirmacion.confirmado:
        return child;
      case EstadoConfirmacion.invitado:
        return ColorFiltered(
          colorFilter: _kGreyscaleFilter,
          child: child,
        );
      case EstadoConfirmacion.noRespondio:
      case EstadoConfirmacion.rechazado:
        return ColorFiltered(
          colorFilter: _kGreyscaleFilter,
          child: Opacity(opacity: 0.75, child: child),
        );
    }
  }
}
