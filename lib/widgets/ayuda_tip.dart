import 'package:flutter/material.dart';

/// Banner compacto con mini instrucciones para el usuario.
class AyudaTip extends StatelessWidget {
  final String texto;
  final IconData icono;
  /// Densidad reducida (p. ej. primer viewport de Organizar encuentro).
  final bool dense;

  const AyudaTip({
    super.key,
    required this.texto,
    this.icono = Icons.lightbulb_outline,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 12,
        vertical: dense ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(dense ? 8 : 10),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icono,
            size: dense ? 15 : 18,
            color: Colors.blue.shade700,
          ),
          SizedBox(width: dense ? 6 : 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: dense ? 11 : 12,
                height: dense ? 1.25 : 1.35,
                color: Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
