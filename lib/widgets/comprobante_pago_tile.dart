import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/matchpay_strings.dart';
import '../services/comprobante_service.dart';

/// Adjuntar o ver foto de comprobante (gasto local/cloud o pago).
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
    await ComprobanteService.instance.deleteAny(widget.comprobantePath);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      if (widget.comprobantePath == null) return const SizedBox.shrink();
      return FutureBuilder<({File? file, String? networkUrl})>(
        future: ComprobanteService.instance
            .resolveForDisplay(widget.comprobantePath),
        builder: (context, snap) => _buildPreview(
          file: snap.data?.file,
          networkUrl: snap.data?.networkUrl,
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
          widget.compact
              ? context.tr('receiptCompact')
              : context.tr('expenseReceiptPhotoOptional'),
          style: const TextStyle(fontSize: 12),
        ),
      );
    }

    return FutureBuilder<({File? file, String? networkUrl})>(
      future:
          ComprobanteService.instance.resolveForDisplay(widget.comprobantePath),
      builder: (context, snap) => _buildPreview(
        file: snap.data?.file,
        networkUrl: snap.data?.networkUrl,
        showActions: true,
      ),
    );
  }

  Widget _buildPreview({
    File? file,
    String? networkUrl,
    required bool showActions,
  }) {
    final size = widget.compact ? 48.0 : 56.0;
    Widget thumb;
    if (file != null) {
      thumb = Image.file(file, width: size, height: size, fit: BoxFit.cover);
    } else if (networkUrl != null) {
      thumb = Image.network(
        networkUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, size: 20),
        ),
      );
    } else {
      thumb = Container(
        width: size,
        height: size,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported, size: 20),
      );
    }

    return Row(
      children: [
        GestureDetector(
          onTap: () => showComprobanteViewer(
            context,
            relativePath: widget.comprobantePath!,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumb,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('expenseReceiptLabel'),
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
                    child: Text(
                      context.tr('viewBtn'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (showActions) ...[
                    TextButton(
                      onPressed: _cargando ? null : _adjuntar,
                      child: Text(
                        context.tr('changeBtn'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _quitar,
                      child: Text(
                        context.tr('removeBtn'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
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
