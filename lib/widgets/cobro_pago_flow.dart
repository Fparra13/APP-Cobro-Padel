import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/supabase_config.dart';
import '../l10n/matchpay_strings.dart';
import '../models/cuenta_saldo.dart';
import '../models/datos_pago_organizador.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../services/comprobante_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_storage_service.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/formatters.dart';

/// Flujo único de pago/abono del jugador (cuenta, no partido individual).
///
/// La cuenta/organizador debe venir ya seleccionada; este flujo no elige
/// automáticamente la cuenta con mayor deuda.
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

  /// Pago/abono sobre una [cuenta] ya elegida (deudas filtradas de ese org).
  static Future<void> iniciarPagoGlobal({
    required BuildContext context,
    required String organizadorId,
    required String organizadorNombre,
    required CuentaSaldo cuenta,
    required List<DetallePartido> deudas,
    required Map<int, DesgloseJugador?> desgloses,
    required bool esTotal,
    Map<int, double>? saldosAnterioresPorPartido,
    VoidCallback? onCompletado,
  }) async {
    final overlay = _overlayContext(context);
    if (!overlay.mounted) return;

    final orgId = organizadorId.trim();
    if (orgId.isEmpty || cuenta.organizadorId.trim() != orgId) {
      _snack(overlay, overlay.l10n.tr('cobrosChargeUnavailable'));
      return;
    }

    if (deudas.isEmpty) {
      _snack(overlay, overlay.l10n.tr('cobrosNoOpenCharges'));
      return;
    }

    final orgMismatch = deudas.any((d) {
      final dOrg = d.organizadorId?.trim() ?? '';
      return dOrg.isEmpty || dOrg != orgId;
    });
    if (orgMismatch) {
      _snack(overlay, overlay.l10n.tr('cobrosChargeUnavailable'));
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

    // Saldo SSOT de la cuenta seleccionada (nunca "mayor deuda" automática).
    var saldoAcumulado = cuenta.saldoAcumulado;
    if (AppRepositories.isReady) {
      final uid = AuthService.instance.currentUser?.id;
      if (uid != null) {
        saldoAcumulado = await AppRepositories.I.getSaldoCuenta(
          organizadorId: orgId,
          jugadorId: uid,
        );
      }
    }
    if (!overlay.mounted) return;

    final total = totalPendienteCobros(
      deudas,
      desgloses,
      saldosAnterioresPorPartido: saldosAnterioresPorPartido,
      saldoAcumuladoJugador: saldoAcumulado,
    );
    if (total <= 0.005 && esTotal) {
      _snack(overlay, overlay.l10n.tr('noDebtInCharge'));
      return;
    }

    final l10n = overlay.l10n;
    final nombre =
        organizadorNombre.trim().isNotEmpty
            ? organizadorNombre.trim()
            : (cuenta.nombreOrganizador.trim().isNotEmpty
                ? cuenta.nombreOrganizador.trim()
                : orgId);
    double monto;
    if (esTotal) {
      final ok = await showDialog<bool>(
        context: overlay,
        useRootNavigator: true,
        builder: (ctx) {
          final muted = Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              );
          return AlertDialog(
            title: Text(
              l10n.tr(
                'cobrosPayDialogTitle',
                params: {'amount': formatMoney(total)},
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.tr('cobrosOrganizerLabel'), style: muted),
                const SizedBox(height: 2),
                Text(
                  nombre,
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Text(l10n.tr('cobrosAutoApplyHint'), style: muted),
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
          );
        },
      );
      if (ok != true || !overlay.mounted) return;
      monto = total;
    } else {
      final abono = await _pedirMontoAbono(
        overlay,
        total,
        organizadorNombre: nombre,
      );
      if (abono == null || !overlay.mounted) return;
      monto = abono;
    }

    await _subirComprobante(
      context: overlay,
      detalle: ancla!,
      organizadorId: orgId,
      organizadorNombre: nombre,
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
    double sugerido, {
    required String organizadorNombre,
  }) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(
      text: sugerido > 0 ? sugerido.toStringAsFixed(0) : '',
    );
    return showDialog<double>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final muted = Theme.of(ctx).textTheme.bodySmall?.copyWith(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            );
        return AlertDialog(
          title: Text(l10n.tr('partialAmountTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.tr('partialAmountBody')),
              const SizedBox(height: 10),
              Text(l10n.tr('cobrosOrganizerLabel'), style: muted),
              const SizedBox(height: 2),
              Text(
                organizadorNombre,
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(l10n.tr('cobrosAutoApplyHint'), style: muted),
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
        );
      },
    );
  }

  static Future<void> _subirComprobante({
    required BuildContext context,
    required DetallePartido detalle,
    required String organizadorId,
    required String organizadorNombre,
    required double montoDeclarado,
    required bool esAbono,
    VoidCallback? onCompletado,
  }) async {
    if (!SupabaseConfig.isConfigured || detalle.id == null) return;

    final l10n = context.l10n;

    DatosPagoOrganizador? pago;
    var orgNombre = organizadorNombre.trim();
    if (AppRepositories.isReady) {
      try {
        final result =
            await AppRepositories.I.getDatosPagoOrganizador(organizadorId);
        pago = result?.pago;
        final remoteName = result?.organizadorNombre.trim() ?? '';
        if (remoteName.isNotEmpty) orgNombre = remoteName;
      } catch (_) {
        pago = null;
      }
    }
    if (!context.mounted) return;

    final continuar = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final muted = theme.colorScheme.onSurfaceVariant;
        return AlertDialog(
          title: Text(l10n.tr('receiptRequiredTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.tr('cobrosPayingToLabel'),
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 2),
                Text(
                  orgNombre.isNotEmpty ? orgNombre : organizadorId,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.tr('amountLabel'),
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoney(montoDeclarado),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.tr('cobrosContributionDataLabel'),
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 6),
                if (pago == null || !pago.tieneDatos)
                  Text(
                    l10n.tr('paymentInfoMissingOrganizer'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  )
                else ...[
                  if (pago.titularTrim.isNotEmpty)
                    Text(
                      l10n.tr(
                        'paymentInfoPayee',
                        params: {'name': pago.titularTrim},
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (pago.detalleTrim.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(pago.detalleTrim, style: theme.textTheme.bodyMedium),
                  ],
                  if (pago.notaTrim.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      pago.notaTrim,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                Text(
                  l10n.tr(
                    'receiptRequiredBody',
                    params: {
                      'amount': formatMoney(montoDeclarado),
                      'paymentType': l10n.tr(
                        esAbono ? 'paymentTypePartial' : 'paymentTypeFull',
                      ),
                    },
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
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
        );
      },
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
        organizadorId: organizadorId,
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
