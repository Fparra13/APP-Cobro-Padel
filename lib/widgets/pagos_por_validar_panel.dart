import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/detalle_partido.dart';
import '../services/supabase_storage_service.dart';
import '../utils/formatters.dart';
import '../utils/single_action.dart';
import 'comprobante_historico_chip.dart';
import 'matchpay_ui.dart';

/// Pagos enviados por jugadores pendientes de conciliación (organizador).
class PagosPorValidarPanel extends StatelessWidget {
  final List<DetallePartido> pagos;
  final VoidCallback? onValidado;
  final bool prominent;
  final bool readOnly;
  final VoidCallback? onReadOnlyTap;
  /// Título ya mostrado en [MatchPaySectionHeader] del home.
  final bool sectionTitleExternal;

  const PagosPorValidarPanel({
    super.key,
    required this.pagos,
    this.onValidado,
    this.prominent = true,
    this.readOnly = false,
    this.onReadOnlyTap,
    this.sectionTitleExternal = false,
  });

  List<DetallePartido> get _pendientes =>
      pagos.where((d) => d.comprobantePendienteValidacion).toList();

  @override
  Widget build(BuildContext context) {
    if (!AppRepositories.I.isCloud || _pendientes.isEmpty) {
      return const SizedBox.shrink();
    }

    final cards = _pendientes
        .map(
          (d) => PagoPorValidarCard(
            detalle: d,
            onValidado: onValidado,
            readOnly: readOnly,
            onReadOnlyTap: onReadOnlyTap,
          ),
        )
        .toList();

    if (!prominent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TituloSeccion(
            titulo: context.tr('paymentsToValidateTitle'),
            subtitulo: context.tr('paymentsToValidateSubtitle'),
          ),
          const SizedBox(height: 8),
          ...cards.map(
            (card) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: card,
            ),
          ),
        ],
      );
    }

    return MatchPaySurfaceCard(
      urgent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!sectionTitleExternal)
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: MatchPayTokens.accentUrgent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('paymentsToValidateTitle'),
                        style: MatchPayTokens.titleSmallStyle(
                          color: MatchPayTokens.accentUrgent,
                        ),
                      ),
                      Text(
                        context.tr(
                          'pendingReceiptsCount',
                          params: {'count': '${_pendientes.length}'},
                        ),
                        style: MatchPayTokens.bodySmallStyle(
                          color: MatchPayTokens.accentUrgent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Text(
              context.tr(
                'pendingReceiptsCount',
                params: {'count': '${_pendientes.length}'},
              ),
              style: MatchPayTokens.bodySmallStyle(
                color: MatchPayTokens.accentUrgent,
              ),
            ),
          const SizedBox(height: 12),
          ...cards,
        ],
      ),
    );
  }
}

class PagoPorValidarCard extends StatefulWidget {
  final DetallePartido detalle;
  final VoidCallback? onValidado;
  final bool readOnly;
  final VoidCallback? onReadOnlyTap;

  const PagoPorValidarCard({
    super.key,
    required this.detalle,
    this.onValidado,
    this.readOnly = false,
    this.onReadOnlyTap,
  });

  @override
  State<PagoPorValidarCard> createState() => _PagoPorValidarCardState();
}

class _PagoPorValidarCardState extends State<PagoPorValidarCard> {
  bool _busy = false;

  DetallePartido get detalle => widget.detalle;

  String _contextoPartido(BuildContext context) {
    if (detalle.fechaPartido != null) {
      final recinto = detalle.recintoPartido?.trim();
      if (recinto != null && recinto.isNotEmpty) {
        return '${formatDiaCompleto(detalle.fechaPartido!)} · $recinto';
      }
      return formatDiaCompleto(detalle.fechaPartido!);
    }
    return context.tr(
      'matchNumber',
      params: {'id': '${detalle.partidoId}'},
    );
  }

  Future<void> _verComprobante() async {
    if (widget.readOnly) {
      widget.onReadOnlyTap?.call();
      return;
    }
    final url = detalle.comprobanteUrl?.trim();
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('receiptImageNotFound'))),
      );
      return;
    }
    await runOnce('ver-comprobante-${detalle.id}', () async {
      try {
        final signed = await SupabaseStorageService.instance.signedUrl(url);
        if (!mounted) return null;
        await showDialog<void>(
          context: context,
          builder: (ctx) => _ComprobanteValidacionDialog(
            signedUrl: signed,
            esAbono: detalle.pagoEsAbono == true,
            onAprobar: () async {
              Navigator.pop(ctx);
              await _confirmarYValidar(aprobado: true);
            },
            onRechazar: () async {
              Navigator.pop(ctx);
              await _confirmarYValidar(aprobado: false);
            },
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.userError(e))),
          );
        }
      }
      return null;
    });
  }

  Future<void> _confirmarYValidar({required bool aprobado}) async {
    final esAbono = detalle.pagoEsAbono == true;
    final monto = detalle.montoPagoDeclarado;
    final montoTxt = monto != null && monto > 0
        ? formatMoney(monto)
        : formatMoney(detalle.total);
    final nombre = detalle.nombreJugador ?? context.tr('thisPlayer');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          aprobado
              ? (esAbono
                  ? ctx.tr('confirmPartialReceived')
                  : ctx.tr('confirmPaymentReceived'))
              : ctx.tr('confirmRejectTitle'),
        ),
        content: Text(
          aprobado
              ? ctx.tr(
                  esAbono
                      ? 'reconcilePartialMessage'
                      : 'reconcilePaymentMessage',
                  params: {'amount': montoTxt, 'name': nombre},
                )
              : ctx.tr('rejectReceiptMessage', params: {'name': nombre}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: aprobado
                ? FilledButton.styleFrom(backgroundColor: Colors.green.shade700)
                : FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: Text(
              aprobado ? ctx.tr('yesReconcile') : ctx.tr('yesReject'),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _validar(aprobado: aprobado);
  }

  Future<void> _validar({required bool aprobado}) async {
    if (detalle.id == null || _busy) return;
    await runOnce('validar-${detalle.id}', () async {
      setState(() => _busy = true);
      try {
        await AppRepositories.I.validarComprobantePago(
          detalleId: detalle.id!,
          aprobado: aprobado,
        );
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              aprobado
                  ? (detalle.pagoEsAbono == true
                      ? context.tr('partialReceivedUpdated')
                      : context.tr('paymentReceivedUpdated'))
                  : context.tr('receiptRejected'),
            ),
          ),
        );
        AppRepositories.notifyDataChanged();
        widget.onValidado?.call();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = detalle;
    final monto = d.montoPagoDeclarado;
    final esAbono = d.pagoEsAbono == true;

    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.nombreJugador ?? context.tr('playerDefaultName'),
            style: MatchPayTokens.titleSmallStyle(),
          ),
          const SizedBox(height: 2),
          Text(
            _contextoPartido(context),
            style: MatchPayTokens.bodySmallStyle(),
          ),
          const SizedBox(height: 6),
          Text(
            monto != null && monto > 0
                ? context.tr(
                    esAbono ? 'partialDeclared' : 'paymentDeclared',
                    params: {'amount': formatMoney(monto)},
                  )
                : context.tr(
                    'matchAmountLabel',
                    params: {'amount': formatMoney(d.total)},
                  ),
            style: MatchPayTokens.titleSmallStyle(
              color: MatchPayTokens.accentUrgent,
            ),
          ),
          if ((d.comprobanteUrl ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _ComprobantePreviewThumb(
              storagePath: d.comprobanteUrl!,
              onTap: _busy ? null : _verComprobante,
            ),
          ],
          if (d.id != null) ...[
            const SizedBox(height: 4),
            ComprobanteHistoricoChip(detalle: d),
          ],
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _verComprobante,
                icon: const Icon(Icons.image_outlined, size: 20),
                label: Text(context.tr('viewReceipt')),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _confirmarYValidar(aprobado: true),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 20),
                label: Text(
                  esAbono
                      ? context.tr('partialReceived')
                      : context.tr('paymentReceived'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: MatchPayTokens.accentSuccess,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed:
                      _busy ? null : () => _confirmarYValidar(aprobado: false),
                  child: Text(context.tr('rejectReceipt')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComprobanteValidacionDialog extends StatelessWidget {
  final String signedUrl;
  final bool esAbono;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  const _ComprobanteValidacionDialog({
    required this.signedUrl,
    required this.esAbono,
    required this.onAprobar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('receiptTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: Image.network(
                signedUrl,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(context.tr('receiptImageNotFound')),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: onRechazar,
                  child: Text(context.tr('reject')),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: onAprobar,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                  child: Text(
                    esAbono
                        ? context.tr('partialReceived')
                        : context.tr('paymentReceived'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('close')),
        ),
      ],
    );
  }
}

/// Miniatura del comprobante en la cola de validación del organizador.
class _ComprobantePreviewThumb extends StatelessWidget {
  final String storagePath;
  final VoidCallback? onTap;

  const _ComprobantePreviewThumb({
    required this.storagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: SupabaseStorageService.instance.signedUrl(storagePath),
      builder: (context, snap) {
        final child = snap.hasData
            ? Image.network(
                snap.data!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(context),
              )
            : snap.hasError
                ? _placeholder(context)
                : const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  );

        return Material(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(height: 140, width: double.infinity, child: child),
          ),
        );
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade600),
            const SizedBox(height: 6),
            Text(
              context.tr('receiptImageNotFound'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String titulo;
  final String subtitulo;

  const _TituloSeccion({
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: MatchPayTokens.titleSmallStyle(),
              ),
              Text(
                subtitulo,
                style: MatchPayTokens.bodySmallStyle(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
