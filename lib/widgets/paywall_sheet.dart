import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/subscription_service.dart';
import '../l10n/matchpay_strings.dart';

/// Muro de pago Kloovi Pro (preparado para Play Store billing).
Future<bool?> showPaywallSheet(
  BuildContext context, {
  required ProFeature feature,
  String? message,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => PaywallSheet(feature: feature, message: message),
  );
}

class PaywallSheet extends StatelessWidget {
  final ProFeature feature;
  final String? message;

  const PaywallSheet({
    super.key,
    required this.feature,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.watch<AppSettingsController>().palette;
    final sub = context.watch<SubscriptionService>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium, color: palette.accent, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.paywallTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: palette.primaryDark,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message ?? l10n.paywallSubtitle,
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 20),
            _PlanColumn(
              title: l10n.paywallFreeTitle,
              color: Colors.grey.shade600,
              items: [
                l10n.freeFeatureDebts,
                l10n.freeFeatureReceipts,
              ],
            ),
            const SizedBox(height: 12),
            _PlanColumn(
              title: l10n.paywallProTitle,
              color: palette.primary,
              items: [
                l10n.proFeatureCreate,
                l10n.proFeatureAutomate,
                l10n.proFeatureStats,
              ],
              highlighted: true,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: sub.isPro
                  ? () => Navigator.pop(context, true)
                  : () async {
                      // Placeholder: abrir flujo de compra Play Store.
                      await SubscriptionService.instance.setProActive(true);
                      if (context.mounted) Navigator.pop(context, true);
                    },
              icon: const Icon(Icons.lock_open),
              label: Text(l10n.paywallCta),
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            TextButton(
              onPressed: () async {
                await SubscriptionService.instance.restorePurchases();
                if (context.mounted) {
                  Navigator.pop(context, SubscriptionService.instance.isPro);
                }
              },
              child: Text(l10n.paywallRestore),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanColumn extends StatelessWidget {
  final String title;
  final Color color;
  final List<String> items;
  final bool highlighted;

  const _PlanColumn({
    required this.title,
    required this.color,
    required this.items,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? color.withValues(alpha: 0.4) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    highlighted ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
