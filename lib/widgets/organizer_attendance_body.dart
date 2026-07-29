import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'convocatoria_asistencias_view.dart';
import 'matchpay_ui.dart';

/// Composición UI de la superficie Attendance (asistencias ↔ detalle RO).
///
/// No conoce Supabase ni el formulario Build. Recibe datos ya resueltos y
/// callbacks de dominio. El toggle Asistencias/Detalle lo controla el padre
/// ([showingDetail]) mientras AppBar viva en [OrganizarPartidoScreen].
class OrganizerAttendanceBody extends StatelessWidget {
  final bool showingDetail;

  // --- Asistencias ---
  final DateTime fecha;
  final String recinto;
  final SportType sportType;
  final int cuposMax;
  final String statusLabel;
  final List<ConvocatoriaAsistenciaItem> titulares;
  final List<ConvocatoriaAsistenciaItem> suplentes;
  final Widget? topBanner;
  final ValueChanged<String>? onCycleEstado;

  // --- Detalle solo lectura ---
  final String lugar;
  final String notas;
  final DateTime? plazoLimite;
  final DateTime? fechaDetalle;
  final SportType? sportTypeDetalle;

  const OrganizerAttendanceBody({
    super.key,
    required this.showingDetail,
    required this.fecha,
    required this.recinto,
    required this.sportType,
    required this.cuposMax,
    required this.statusLabel,
    required this.titulares,
    required this.suplentes,
    this.topBanner,
    this.onCycleEstado,
    required this.lugar,
    required this.notas,
    this.plazoLimite,
    this.fechaDetalle,
    this.sportTypeDetalle,
  });

  @override
  Widget build(BuildContext context) {
    if (showingDetail) {
      return _buildDetalle(context);
    }
    return ConvocatoriaAsistenciasView(
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
      cuposMax: cuposMax,
      statusLabel: statusLabel,
      titulares: titulares,
      suplentes: suplentes,
      topBanner: topBanner,
      onCycleEstado: onCycleEstado,
    );
  }

  Widget _buildDetalle(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;
    final sport = sportTypeDetalle;
    final fecha = fechaDetalle;
    final lugarTrim = lugar.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        MatchPaySurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tr('matchDetailTitle'),
                style: MatchPayTokens.titleMediumStyle().copyWith(fontSize: 17),
              ),
              const SizedBox(height: 14),
              if (sport != null) ...[
                Text(
                  '${sport.emoji} ${sport.labelForLang(lang)}',
                  style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 16),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                lugarTrim.isEmpty ? '—' : lugarTrim,
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkMuted,
                ),
              ),
              const SizedBox(height: 16),
              if (fecha != null) ...[
                Text(
                  formatFechaEncuentro(
                    fecha,
                    contexto: FechaEncuentroContexto.futuro,
                  ),
                  style: MatchPayTokens.titleMediumStyle().copyWith(fontSize: 20),
                ),
              ] else
                Text(
                  '—',
                  style: MatchPayTokens.bodySmallStyle(
                    color: MatchPayTokens.inkMuted,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                l10n.tr(
                  'organizeDetailCupos',
                  params: {'count': '$cuposMax'},
                ),
                style: MatchPayTokens.bodySmallStyle(color: MatchPayTokens.ink),
              ),
              if (plazoLimite != null) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.tr(
                    'organizeDetailDeadline',
                    params: {'time': formatHora(plazoLimite!)},
                  ),
                  style:
                      MatchPayTokens.bodySmallStyle(color: MatchPayTokens.ink),
                ),
              ],
              if (notas.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.tr('notesLabel'),
                  style: MatchPayTokens.bodySmallStyle(
                    color: MatchPayTokens.inkMuted,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  notas.trim(),
                  style:
                      MatchPayTokens.bodySmallStyle(color: MatchPayTokens.ink),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
