import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../repositories/partido_repository.dart';
import 'matchpay_ui.dart';
import 'recordatorio_deudores_sheet.dart';

class QuickActionsPanel extends StatelessWidget {
  final List<ResumenJugador> resumenes;
  final void Function(int tabIndex)? onNavigateTab;

  const QuickActionsPanel({
    super.key,
    required this.resumenes,
    this.onNavigateTab,
  });

  int get _conDeuda => resumenes.where((r) => r.tieneDeuda).length;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final acciones = <_AccionRapida>[
      _AccionRapida(
        icon: Icons.payments_outlined,
        label: l10n.tr('quickActionGroupCobros'),
        subtitulo: _conDeuda > 0
            ? l10n.tr(
                'quickActionGroupCobrosDebt',
                params: {'count': '$_conDeuda'},
              )
            : l10n.tr('quickActionGroupCobrosOk'),
        accent: _conDeuda > 0
            ? MatchPayTokens.accentUrgent
            : MatchPayTokens.accentSuccess,
        onTap: () => onNavigateTab?.call(1),
      ),
      if (_conDeuda > 0)
        _AccionRapida(
          icon: Icons.chat_rounded,
          label: l10n.tr('remindDebtors'),
          subtitulo: l10n.tr(
            'remindDebtorsPush',
            params: {'count': '$_conDeuda'},
          ),
          accent: MatchPayTokens.accentCredit,
          onTap: () => RecordatorioDeudoresSheet.show(
            context,
            resumenes: resumenes,
          ),
        ),
      _AccionRapida(
        icon: Icons.people_rounded,
        label: l10n.tr('navPlayers'),
        subtitulo: l10n.tr('manageGroup'),
        accent: MatchPayTokens.inkSecondary,
        onTap: () => onNavigateTab?.call(2),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatchPaySectionHeader(title: l10n.tr('toolsTitle')),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
          ),
          itemCount: acciones.length,
          itemBuilder: (_, i) => _AccionCard(accion: acciones[i]),
        ),
      ],
    );
  }
}

class _AccionRapida {
  final IconData icon;
  final String label;
  final String subtitulo;
  final Color accent;
  final VoidCallback onTap;

  const _AccionRapida({
    required this.icon,
    required this.label,
    required this.subtitulo,
    required this.accent,
    required this.onTap,
  });
}

class _AccionCard extends StatelessWidget {
  final _AccionRapida accion;

  const _AccionCard({required this.accion});

  @override
  Widget build(BuildContext context) {
    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: accion.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accion.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(accion.icon, color: accion.accent, size: 22),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accion.label,
                style: MatchPayTokens.titleSmallStyle(),
              ),
              Text(
                accion.subtitulo,
                style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
