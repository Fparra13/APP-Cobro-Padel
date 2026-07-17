import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../utils/formatters.dart';

/// Bloque de fecha estilo Spond: mes abreviado arriba + día grande.
class EventDateBlock extends StatelessWidget {
  final DateTime fecha;
  final Color? dayColor;
  final Color? monthColor;

  const EventDateBlock({
    super.key,
    required this.fecha,
    this.dayColor,
    this.monthColor,
  });

  @override
  Widget build(BuildContext context) {
    final mes = formatMesAbrev(fecha);
    final dia = formatDiaNumero(fecha);

    return SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mes,
            textAlign: TextAlign.center,
            style: MatchPayTokens.sectionLabelStyle(
              color: monthColor ?? MatchPayTokens.inkMuted,
            ).copyWith(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dia,
            textAlign: TextAlign.center,
            style: MatchPayTokens.headlineStyle(
              color: dayColor ?? MatchPayTokens.ink,
            ).copyWith(
              fontSize: 26,
              height: 1.0,
              letterSpacing: -0.8,
            ),
          ),
        ],
      ),
    );
  }
}
