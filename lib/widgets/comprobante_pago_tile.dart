import 'dart:io';

import 'package:flutter/material.dart';

import '../services/comprobante_service.dart';

/// Adjuntar o ver foto de comprobante de pago.
class ComprobantePagoTile extends StatefulWidget {
  final String? comprobantePath;
  final ValueChanged<String?> onChanged;
  final bool compact;
  final bool readOnly;

  const ComprobantePagoTile({
    super.key,
    required this.comprobantePath,
    required this.onChanged,
    this.compact = false,
    this.readOnly = false,
  });

  @override
  State<ComprobantePagoTile> createState() => _ComprobantePagoTileState();
}

class _ComprobantePagoTileState extends State<ComprobantePagoTile> {
  bool _cargando = false;

  Future<void> _adjuntar() async {
    setState(() => _cargando = true);
    try {
      final path = await ComprobanteService.instance.pickAndSave(
        context: context,
        replacePath: widget.comprobantePath,
      );
      if (path != null) widget.onChanged(path);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _quitar() async {
    await ComprobanteService.instance.delete(widget.comprobantePath);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      if (widget.comprobantePath == null) return const SizedBox.shrink();
      return FutureBuilder<File?>(
        future: ComprobanteService.instance.resolveFile(widget.comprobantePath),
        builder: (context, snap) => _buildPreview(
          file: snap.data,
          showActions: false,
        ),
      );
    }

    if (widget.comprobantePath == null) {
      return OutlinedButton.icon(
        onPressed: _cargando ? null : _adjuntar,
        icon: _cargando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.receipt_long, size: 18),
        label: Text(
          widget.compact ? 'Comprobante' : 'Foto comprobante del gasto (opcional)',
          style: const TextStyle(fontSize: 12),
        ),
      );
    }

    return FutureBuilder<File?>(
      future: ComprobanteService.instance.resolveFile(widget.comprobantePath),
      builder: (context, snap) => _buildPreview(
        file: snap.data,
        showActions: true,
      ),
    );
  }

  Widget _buildPreview({File? file, required bool showActions}) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => showComprobanteViewer(
            context,
            relativePath: widget.comprobantePath!,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: file != null
                ? Image.file(
                    file,
                    width: widget.compact ? 48 : 56,
                    height: widget.compact ? 48 : 56,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: widget.compact ? 48 : 56,
                    height: widget.compact ? 48 : 56,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported, size: 20),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comprobante del gasto',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => showComprobanteViewer(
                      context,
                      relativePath: widget.comprobantePath!,
                    ),
                    child: const Text('Ver', style: TextStyle(fontSize: 12)),
                  ),
                  if (showActions) ...[
                    TextButton(
                      onPressed: _cargando ? null : _adjuntar,
                      child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: _quitar,
                      child: Text(
                        'Quitar',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
