import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/codigo_grupo_share.dart';
import '../utils/organizador_participante_form.dart';

/// Sheet: agregar persona que usa Kloovi (código) vs manual (sin app).
Future<void> showAgregarParticipanteChooser(
  BuildContext context, {
  required Future<void> Function() onManualAdded,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: MatchPayTokens.surfaceCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final l10n = ctx.l10n;
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      // Marca Kloovi (no sportPalette: puede verse azul).
      const brandTeal = Color(0xFF1AA89B);

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tr('addParticipantChooserTitle'),
              style: MatchPayTokens.titleMediumStyle().copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            _ChooserOption(
              icon: Icons.smartphone_rounded,
              tint: brandTeal,
              title: l10n.tr('addParticipantUsesKlooviTitle'),
              body: l10n.tr('addParticipantUsesKlooviBody'),
              ctaLabel: l10n.tr('organizerActivationShareCta'),
              ctaFilled: true,
              onCta: () async {
                Navigator.pop(ctx);
                await compartirCodigoGrupoOrganizador(context);
              },
            ),
            const SizedBox(height: 12),
            _ChooserOption(
              icon: Icons.person_add_alt_1_rounded,
              tint: MatchPayTokens.inkSecondary,
              title: l10n.tr('addParticipantManualTitle'),
              body: l10n.tr('addParticipantManualBody'),
              ctaLabel: l10n.tr('addParticipantManualCta'),
              ctaFilled: false,
              onCta: () async {
                Navigator.pop(ctx);
                final saved = await showOrganizerParticipanteForm(context);
                if (saved) await onManualAdded();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

class _ChooserOption extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String body;
  final String ctaLabel;
  final bool ctaFilled;
  final VoidCallback onCta;

  const _ChooserOption({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.ctaFilled,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: MatchPayTokens.surfaceInset,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MatchPayTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tint, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: MatchPayTokens.titleSmallStyle().copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: MatchPayTokens.bodySmallStyle(
                        color: MatchPayTokens.inkSecondary,
                      ).copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (ctaFilled)
            FilledButton(
              onPressed: onCta,
              style: FilledButton.styleFrom(
                backgroundColor: tint,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                ctaLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else
            OutlinedButton(
              onPressed: onCta,
              style: OutlinedButton.styleFrom(
                foregroundColor: tint,
                side: BorderSide(color: tint.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                ctaLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
