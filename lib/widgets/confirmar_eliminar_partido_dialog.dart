import 'package:flutter/material.dart';

import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import '../utils/app_navigation.dart';

/// Diálogo explícito antes de eliminar un partido o convocatoria.
Future<bool> confirmarEliminarPartido(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  List<String>? consecuencias,
  String? confirmLabel,
}) async {
  final host = matchPayRootContext ?? context;
  if (!host.mounted) return false;

  final l10n = host.l10n;
  final items = consecuencias ??
      [
        l10n.tr('deleteMatchConsequence1'),
        l10n.tr('deleteMatchConsequence2'),
        l10n.tr('deleteMatchConsequence3'),
      ];

  final ok = await showDialog<bool>(
    context: host,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 44),
      title: Text(titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mensaje),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ctx.tr('actionIrreversible'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...items.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ', style: TextStyle(color: Colors.red.shade800)),
                          Expanded(
                            child: Text(
                              t,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red.shade900,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: Text(confirmLabel ?? ctx.tr('yesDeletePermanently')),
        ),
      ],
    ),
  );

  return ok == true;
}
