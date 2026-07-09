import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/supabase_config.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../services/comprobante_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_storage_service.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/formatters.dart';

/// Flujo único de pago/abono del jugador (cuenta, no partido individual).
class CobroPagoFlow {
  CobroPagoFlow._();

  static BuildContext _overlayContext(BuildContext context) {
    return NotificationService.instance.navigatorKey?.currentContext ?? context;
  }

  static void _snack(BuildContext context, String message) {
    NotificationService.instance.showInAppSnack(
      message,
      context: context,
    );
  }

  static Future<void> iniciarPagoGlobal({
    required BuildContext context,
    required List<DetallePartido> deudas,
    required Map<int, DesgloseJugador?> desgloses,
    required bool esTotal,
    Map<int, double>? saldosAnterioresPorPartido,
    double? saldoAcumuladoJugador,
    VoidCallback? onCompletado,
  }) async {
    final overlay = _overlayContext(context);
    if (!overlay.mounted) return;

    if (deudas.isEmpty) {
      _snack(overlay, overlay.l10n.tr('cobrosNoOpenCharges'));
      return;
    }

    final pendienteRevision =
        deudas.any((d) => d.comprobantePendienteValidacion);
    if (pendienteRevision) {
      await mostrarComprobanteEnRevision(overlay);
      return;
    }

    final ancla = detalleAnclaPago(deudas);
    if (ancla?.id == null) {
      _snack(overlay, overlay.l10n.tr('cobrosChargeUnavailable'));
      return;
    }

    double? saldoAcumulado = saldoAcumuladoJugador;
    if (saldoAcumulado == null) {
      final uid = AuthService.instance.currentUser?.id;
      if (uid != null && AppRepositories.isReady) {
        final jugador = await AppRepositories.I.getJugador(uid);
        saldoAcumulado = jugador?.saldoAcumulado;
      }
    }

    final total = totalPendienteCobros(
      deudas,
      desgloses,
      saldosAnterioresPorPartido: saldosAnterioresPorPartido,
      saldoAcumuladoJugador: saldoAcumulado,
    );
    if (total <= 0.005 && esTotal) {
      if (overlay.mounted) {
        _snack(overlay, overlay.l10n.tr('noDebtInCharge'));
      }
      return;
    }

    final l10n = overlay.l10n;
    double monto;
    if (esTotal) {
      final ok = await showDialog<bool>(
        context: overlay,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.tr('cobrosPayDialogTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.tr(
                  'cobrosPayDialogBody',
                  params: {'amount': formatMoney(total)},
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.tr('cobrosAutoApplyHint'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l10n.tr(
                  'cobrosPayAmount',
                  params: {'amount': formatMoney(total)},
                ),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !overlay.mounted) return;
      monto = total;
    } else {
      final abono = await _pedirMontoAbono(overlay, total);
      if (abono == null || !overlay.mounted) return;
      monto = abono;
    }

    await _subirComprobante(
      context: overlay,
      detalle: ancla!,
      montoDeclarado: monto,
      esAbono: !esTotal,
      onCompletado: onCompletado,
    );
  }

  static Future<void> mostrarComprobanteEnRevision(BuildContext context) async {
    final overlay = _overlayContext(context);
    if (!overlay.mounted) return;
    await showDialog<void>(
      context: overlay,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800),
        title: Text(overlay.l10n.tr('paymentPendingApprovalTitle')),
        content: Text(overlay.l10n.tr('paymentPendingApprovalBody')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.tr('understood')),
          ),
        ],
      ),
    );
  }

  static Future<double?> _pedirMontoAbono(
    BuildContext context,
    double sugerido,
  ) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(
      text: sugerido > 0 ? sugerido.toStringAsFixed(0) : '',
    );
    return showDialog<double>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('partialAmountTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.tr('partialAmountBody')),
            const SizedBox(height: 8),
            Text(
              l10n.tr('cobrosAutoApplyHint'),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.tr('amountLabel'),
                hintText: sugerido > 0
                    ? formatMoney(sugerido)
                    : l10n.tr('amountHintExample'),
                prefixText: '\$ ',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              final monto = double.tryParse(raw);
              if (monto == null || monto <= 0) return;
              Navigator.pop(ctx, monto);
            },
            child: Text(l10n.tr('continueBtn')),
          ),
        ],
      ),
    );
  }

  static Future<void> _subirComprobante({
    required BuildContext context,
    required DetallePartido detalle,
    required double montoDeclarado,
    required bool esAbono,
    VoidCallback? onCompletado,
  }) async {
    if (!SupabaseConfig.isConfigured || detalle.id == null) return;

    final l10n = context.l10n;
    final continuar = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('receiptRequiredTitle')),
        content: Text(
          l10n.tr(
            'receiptRequiredBody',
            params: {
              'amount': formatMoney(montoDeclarado),
              'paymentType': l10n.tr(
                esAbono ? 'paymentTypePartial' : 'paymentTypeFull',
              ),
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.upload_file),
            label: Text(l10n.tr('uploadReceipt')),
          ),
        ],
      ),
    );
    if (continuar != true || !context.mounted) return;

    final source = await ComprobanteService.instance.askSource(context);
    if (source == null || !context.mounted) return;

    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (xFile == null) return;

    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return;

    final repos = AppRepositories.I;
    try {
      final path = await SupabaseStorageService.instance.uploadComprobante(
        userId: uid,
        file: File(xFile.path),
      );
      if (!context.mounted) return;
      await repos.subirComprobantePago(
        detalleId: detalle.id!,
        storagePath: path,
        montoDeclarado: montoDeclarado,
        esAbono: esAbono,
      );
      if (context.mounted) {
        _snack(
          context,
          l10n.tr(
            esAbono ? 'paymentSentPartial' : 'paymentSentFull',
            params: {'amount': formatMoney(montoDeclarado)},
          ),
        );
        AppRepositories.notifyDataChanged();
        onCompletado?.call();
      }
    } catch (e) {
      if (context.mounted) {
        _snack(context, context.userError(e));
      }
    }
  }
}
