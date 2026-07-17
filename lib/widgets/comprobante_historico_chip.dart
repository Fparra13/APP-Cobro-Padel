import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/comprobante_estado.dart';
import '../models/comprobante_pago.dart';
import '../models/detalle_partido.dart';
import '../services/comprobante_service.dart';
import '../utils/formatters.dart';

/// Lista de comprobantes del historial (varios abonos) + acceso a cada foto.
class ComprobanteHistoricoChip extends StatelessWidget {
  final DetallePartido detalle;

  const ComprobanteHistoricoChip({super.key, required this.detalle});

  @override
  Widget build(BuildContext context) {
    final detalleId = detalle.id;
    if (detalleId == null) {
      return _legacySingle(context);
    }

    return FutureBuilder<List<ComprobantePago>>(
      future: AppRepositories.I.getComprobantesPagoByDetalle(detalleId),
      builder: (context, snap) {
        if (snap.hasError) return _legacySingle(context);
        final hist = snap.data;
        if (hist != null && hist.isNotEmpty) {
          return _HistorialList(comprobantes: hist);
        }
        if (snap.connectionState != ConnectionState.done) {
          return _legacySingle(context);
        }
        return _legacySingle(context);
      },
    );
  }

  Widget _legacySingle(BuildContext context) {
    if (!detalle.tieneComprobanteArchivo) {
      return const SizedBox.shrink();
    }
    final estado = detalle.comprobanteEstadoEfectivo;
    if (estado == null) return const SizedBox.shrink();

    return _ComprobanteRow(
      label: _labelEstado(context.l10n, estado),
      color: estado == ComprobanteEstado.enRevision
          ? MatchPayTokens.accentUrgent
          : MatchPayTokens.inkMuted,
      onView: () => showComprobanteViewer(
        context,
        relativePath: detalle.comprobanteUrl!,
      ),
      monto: detalle.montoPagoDeclarado,
    );
  }
}

class _HistorialList extends StatelessWidget {
  final List<ComprobantePago> comprobantes;

  const _HistorialList({required this.comprobantes});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comprobantes.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.tr(
                  'receiptsHistoryCount',
                  params: {'count': '${comprobantes.length}'},
                ),
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkMuted,
                ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ...comprobantes.map((c) {
            final color = c.estado == ComprobanteEstado.enRevision
                ? MatchPayTokens.accentUrgent
                : MatchPayTokens.inkMuted;
            final when = c.createdAt != null
                ? formatFechaCorta(c.createdAt!)
                : '';
            final base = _labelEstado(l10n, c.estado);
            final label = when.isEmpty ? base : '$base · $when';
            return _ComprobanteRow(
              label: label,
              color: color,
              monto: c.montoDeclarado,
              onView: () => showComprobanteViewer(
                context,
                relativePath: c.storagePath,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ComprobanteRow extends StatelessWidget {
  final String label;
  final Color color;
  final double? monto;
  final VoidCallback onView;

  const _ComprobanteRow({
    required this.label,
    required this.color,
    required this.onView,
    this.monto,
  });

  @override
  Widget build(BuildContext context) {
    final montoTxt = monto != null && monto! > 0.005
        ? ' · ${formatMoney(monto!)}'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(Icons.receipt_long, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$label$montoTxt',
              style: MatchPayTokens.bodySmallStyle(color: color).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              context.l10n.tr('viewBtn'),
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _labelEstado(MatchPayStrings l10n, ComprobanteEstado estado) {
  return switch (estado) {
    ComprobanteEstado.rechazado => l10n.tr('cobroStatusReceiptRejected'),
    ComprobanteEstado.enRevision => l10n.tr('cobrosHeroReceiptReview'),
    ComprobanteEstado.aprobado => l10n.tr('cobroStatusReceiptSent'),
  };
}
