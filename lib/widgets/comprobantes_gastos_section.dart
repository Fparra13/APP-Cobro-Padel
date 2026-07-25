import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/comprobante_gasto_grupo.dart';
import '../services/comprobante_service.dart';
import '../utils/formatters.dart';

/// Comprobantes de gastos agrupados por encuentro (sin miniaturas).
///
/// Jerarquía: Organizador → Encuentro (fecha/hora + deporte/lugar) → Gastos.
class ComprobantesGastosSection extends StatelessWidget {
  final List<ComprobanteGastoGrupo> grupos;
  final Widget? header;

  const ComprobantesGastosSection({
    super.key,
    required this.grupos,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final visibles = grupos.where((g) => g.isNotEmpty).toList(growable: false);
    if (visibles.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header ??
            Text(
              l10n.tr('expenseReceiptsTitle'),
              style: MatchPayTokens.sectionLabelStyle(),
            ),
        const SizedBox(height: 8),
        ...visibles.map(
          (grupo) => _GrupoEncuentroCard(
            grupo: grupo,
            sportLabel: grupo.sportType?.labelForLang(lang),
          ),
        ),
      ],
    );
  }
}

class _GrupoEncuentroCard extends StatelessWidget {
  final ComprobanteGastoGrupo grupo;
  final String? sportLabel;

  const _GrupoEncuentroCard({
    required this.grupo,
    this.sportLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final org = grupo.organizadorNombre?.trim();
    final fechaHora = grupo.tituloFechaHora;
    final deporteLugar = grupo.lineaDeporteLugar(sportLabel: sportLabel);
    final tieneEncuentro =
        fechaHora.isNotEmpty || deporteLugar.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (org != null && org.isNotEmpty) ...[
              Text(
                l10n.tr(
                  'cobrosOrganizerNamed',
                  params: {'name': org},
                ),
                style: MatchPayTokens.bodySmallStyle().copyWith(
                  fontWeight: FontWeight.w700,
                  color: MatchPayTokens.ink,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (fechaHora.isNotEmpty)
              Text(
                fechaHora,
                style: MatchPayTokens.titleSmallStyle().copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            if (deporteLugar.isNotEmpty) ...[
              if (fechaHora.isNotEmpty) const SizedBox(height: 2),
              Text(
                deporteLugar,
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkMuted,
                ),
              ),
            ],
            if (tieneEncuentro) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: MatchPayTokens.borderSubtle),
              const SizedBox(height: 8),
            ],
            for (var i = 0; i < grupo.lineas.length; i++) ...[
              _LineaGastoComprobante(linea: grupo.lineas[i]),
              if (i < grupo.lineas.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineaGastoComprobante extends StatelessWidget {
  final ComprobanteGastoLinea linea;

  const _LineaGastoComprobante({required this.linea});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final emoji = linea.emoji;
    final concepto =
        emoji == null ? linea.concepto : '$emoji ${linea.concepto}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                concepto,
                style: MatchPayTokens.bodySmallStyle().copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatMoney(linea.monto),
              style: MatchPayTokens.bodySmallStyle().copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => showComprobanteViewer(
              context,
              relativePath: linea.path,
            ),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: Text(l10n.tr('viewReceipt')),
          ),
        ),
      ],
    );
  }
}
