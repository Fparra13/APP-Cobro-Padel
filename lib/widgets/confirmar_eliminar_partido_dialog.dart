import 'package:flutter/material.dart';

/// Diálogo explícito antes de eliminar un partido o convocatoria.
Future<bool> confirmarEliminarPartido(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  List<String>? consecuencias,
}) async {
  final items = consecuencias ??
      const [
        'Se borrarán los datos del partido de forma permanente.',
        'Los saldos del grupo se recalcularán sin este partido.',
        'No podrás recuperar cobros, pagos ni comprobantes asociados.',
      ];

  final ok = await showDialog<bool>(
    context: context,
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
                    'Esta acción NO se puede revertir',
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: const Text('Sí, eliminar definitivamente'),
        ),
      ],
    ),
  );

  return ok == true;
}
