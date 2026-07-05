import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../services/comprobante_service.dart';
import '../services/supabase_storage_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/shimmer_loading.dart';

/// Deudas del jugador: declarar pago (total/abono) y subir comprobante obligatorio.
class MisCobrosScreen extends StatefulWidget {
  const MisCobrosScreen({super.key});

  @override
  State<MisCobrosScreen> createState() => _MisCobrosScreenState();
}

class _MisCobrosScreenState extends State<MisCobrosScreen> {
  List<DetallePartido> _deudas = [];
  final Map<int, DesgloseJugador?> _desglosePorPartido = {};
  bool _loading = true;
  String? _error;
  int? _subiendoId;

  @override
  void initState() {
    super.initState();
    _load();
    AppRepositories.dataRevision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    AppRepositories.dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repos = context.repos;
      final deudas = ordenarDeudasPorFecha(await repos.getMisDeudasPendientes());
      final desgloseMap = <int, DesgloseJugador?>{};
      await Future.wait(
        deudas.map((d) async {
          try {
            desgloseMap[d.partidoId] = await repos.getMiDesglosePartido(
              d.partidoId,
            );
          } catch (_) {
            desgloseMap[d.partidoId] = null;
          }
        }),
      );
      if (mounted) {
        setState(() {
          _deudas = deudas;
          _desglosePorPartido
            ..clear()
            ..addAll(desgloseMap);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = SupabaseHelpers.describeError(e, operacion: 'Mis cobros');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<double?> _pedirMontoAbono(double sugerido) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(
      text: sugerido > 0 ? sugerido.toStringAsFixed(0) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('partialAmountTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.tr('partialAmountBody')),
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
    return result;
  }

  Future<void> _iniciarPago({
    required DetallePartido detalle,
    required DesgloseJugador? desglose,
    required bool esTotal,
  }) async {
    if (detalle.comprobantePendienteValidacion) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800),
          title: Text(context.l10n.tr('paymentPendingApprovalTitle')),
          content: Text(context.l10n.tr('paymentPendingApprovalBody')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.tr('understood')),
            ),
          ],
        ),
      );
      return;
    }

    final pendiente = montoATransferirCobro(detalle, desglose);
    if (pendiente <= 0 && esTotal) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('noDebtInCharge'))),
        );
      }
      return;
    }

    final l10n = context.l10n;
    double monto;
    if (esTotal) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.tr('payFullTitle')),
          content: Text(
            l10n.tr(
              'payFullDialogBody',
              params: {'amount': formatMoney(pendiente)},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.tr('continueBtn')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      monto = pendiente;
    } else {
      final abono = await _pedirMontoAbono(pendiente);
      if (abono == null || !mounted) return;
      monto = abono;
    }

    await _subirComprobante(
      detalle: detalle,
      montoDeclarado: monto,
      esAbono: !esTotal,
    );
  }

  Future<void> _subirComprobante({
    required DetallePartido detalle,
    required double montoDeclarado,
    required bool esAbono,
  }) async {
    if (!SupabaseConfig.isConfigured || detalle.id == null) return;

    if (!mounted) return;
    final l10n = context.l10n;
    final continuar = await showDialog<bool>(
      context: context,
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
    if (continuar != true || !mounted) return;

    final source = await ComprobanteService.instance.askSource(context);
    if (source == null || !mounted) return;

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

    setState(() => _subiendoId = detalle.id);
    try {
      final path = await SupabaseStorageService.instance.uploadComprobante(
        userId: uid,
        file: File(xFile.path),
      );
      await context.repos.subirComprobantePago(
        detalleId: detalle.id!,
        storagePath: path,
        montoDeclarado: montoDeclarado,
        esAbono: esAbono,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.tr(
                esAbono ? 'paymentSentPartial' : 'paymentSentFull',
                params: {'amount': formatMoney(montoDeclarado)},
              ),
            ),
          ),
        );
        AppRepositories.notifyDataChanged();
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoId = null);
    }
  }

  Widget? _accionesPago(DetallePartido d, DesgloseJugador? desglose, bool busy) {
    final l10n = context.l10n;
    if (d.comprobantePendienteValidacion) {
      return Material(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _iniciarPago(
            detalle: d,
            desglose: desglose,
            esTotal: true,
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    color: Colors.orange.shade800, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tr('paymentPendingApprovalTitle'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.tr('paymentPendingApprovalShort'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!d.puedeDeclararPago) return null;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => _iniciarPago(
                          detalle: d,
                          desglose: desglose,
                          esTotal: true,
                        ),
                icon: const Icon(Icons.payments),
                label: Text(l10n.tr('payFullTitle')),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => _iniciarPago(
                          detalle: d,
                          desglose: desglose,
                          esTotal: false,
                        ),
                icon: const Icon(Icons.savings_outlined),
                label: Text(l10n.tr('homePartialPayment')),
              ),
            ),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ultimo = _deudas.isNotEmpty ? _deudas.first : null;
    final otros = _deudas.length > 1 ? _deudas.sublist(1) : const <DetallePartido>[];

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(title: Text(l10n.tr('myChargesScreenTitle'))),
      body: _loading
          ? ListView(
              padding: NavShellScope.listPadding(context),
              children: const [
                ShimmerLoading(height: 48, borderRadius: BorderRadius.all(Radius.circular(12))),
                SizedBox(height: 16),
                ShimmerLoading(height: 180, borderRadius: BorderRadius.all(Radius.circular(20))),
                SizedBox(height: 12),
                ShimmerLoading(height: 120, borderRadius: BorderRadius.all(Radius.circular(20))),
              ],
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: NavShellScope.listPadding(context),
                children: [
                  AyudaTip(texto: l10n.tr('misCobrosHelpTip')),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: Text(l10n.tr('retry')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_deudas.isEmpty)
                    MatchPaySurfaceCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 48,
                            color: MatchPayTokens.accentSuccess,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.tr('noPendingDebts'),
                            style: MatchPayTokens.titleSmallStyle(),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.tr('playerPaymentsUpToDate'),
                            style: MatchPayTokens.bodySmallStyle(),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if (ultimo != null) ...[
                      MatchPaySectionHeader(
                        title: _deudas.length > 1
                            ? l10n.tr('lastMatch')
                            : l10n.tr('chargeDetail'),
                        accent: true,
                      ),
                      const SizedBox(height: 8),
                      CobroPartidoCard(
                        detalle: ultimo,
                        desglose: _desglosePorPartido[ultimo.partidoId],
                        estadoExtra: estadoTextoCobro(ultimo, l10n),
                        actions: _accionesPago(
                          ultimo,
                          _desglosePorPartido[ultimo.partidoId],
                          _subiendoId == ultimo.id,
                        ),
                      ),
                    ],
                    if (otros.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      MatchPaySectionHeader(
                        title: l10n.tr('otherPendingCharges'),
                      ),
                      const SizedBox(height: 8),
                      ...otros.map((d) {
                        final desglose = _desglosePorPartido[d.partidoId];
                        final busy = _subiendoId == d.id;
                        return CobroPartidoCard(
                          detalle: d,
                          desglose: desglose,
                          compact: true,
                          estadoExtra: estadoTextoCobro(d, l10n),
                          actions: _accionesPago(d, desglose, busy),
                        );
                      }),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
