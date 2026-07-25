import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/comprobante_gasto_grupo.dart';
import '../services/comprobante_service.dart';
import '../utils/formatters.dart';

/// Comprobantes de gastos agrupados por encuentro (sin miniaturas).
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
          (grupo) => _GrupoEncuentroTile(grupo: grupo),
        ),
      ],
    );
  }
}

class _GrupoEncuentroTile extends StatelessWidget {
  final ComprobanteGastoGrupo grupo;

  const _GrupoEncuentroTile({required this.grupo});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final titulo = grupo.tituloEncuentro;
    final org = grupo.organizadorNombre;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: grupo.initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          title: Text(
            titulo.isNotEmpty
                ? titulo
                : l10n.tr('expenseReceiptsTitle'),
            style: MatchPayTokens.titleSmallStyle().copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          subtitle: org == null || org.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.tr(
                      'cobrosOrganizerNamed',
                      params: {'name': org},
                    ),
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkMuted,
                    ),
                  ),
                ),
          children: [
            for (var i = 0; i < grupo.lineas.length; i++) ...[
              _LineaGastoComprobante(linea: grupo.lineas[i]),
              if (i < grupo.lineas.length - 1)
                Divider(height: 12, color: MatchPayTokens.borderSubtle),
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
    final concepto = emoji == null
        ? linea.concepto
        : '$emoji ${linea.concepto}';

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
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => showComprobanteViewer(
              context,
              relativePath: linea.path,
            ),
            child: Text(l10n.tr('viewReceipt')),
          ),
        ),
      ],
    );
  }
}
