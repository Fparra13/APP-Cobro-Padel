import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/codigo_grupo.dart';
import 'matchpay_ui.dart';

/// Sheet para que un jugador se una a un organizador con código.
class UnirseGrupoSheet extends StatefulWidget {
  const UnirseGrupoSheet({super.key});

  static Future<UnirseGrupoResult?> show(BuildContext context) {
    return showModalBottomSheet<UnirseGrupoResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const UnirseGrupoSheet(),
    );
  }

  /// Aviso puntual al unirse a un 2.º+ organizador (cuentas de cobro separadas).
  static Future<void> maybeShowCuentaAdicionalInfo(
    BuildContext context,
    UnirseGrupoResult result,
  ) async {
    if (!result.esCuentaAdicional) return;
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('groupCodeCuentaAdicionalTitle')),
        content: Text(
          l10n.tr(
            'groupCodeCuentaAdicionalBody',
            params: {'name': result.nombre},
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.tr('understood')),
          ),
        ],
      ),
    );
  }

  @override
  State<UnirseGrupoSheet> createState() => _UnirseGrupoSheetState();
}

class _UnirseGrupoSheetState extends State<UnirseGrupoSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;
  List<MiOrganizadorGrupo> _misGrupos = const [];
  bool _loadingGrupos = true;

  @override
  void initState() {
    super.initState();
    _cargarGrupos();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargarGrupos() async {
    try {
      final list = await context.repos.listarMisOrganizadores();
      if (!mounted) return;
      setState(() {
        _misGrupos = list;
        _loadingGrupos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingGrupos = false);
    }
  }

  Future<void> _unirse() async {
    final codigo = _ctrl.text.trim();
    if (codigo.isEmpty) {
      setState(() => _error = context.l10n.tr('groupCodeJoinEmpty'));
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      setState(() => _error = context.l10n.tr('groupCodeJoinInvalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.repos.unirseConCodigoGrupo(codigo);
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.userError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.tr('groupCodeJoinTitle'),
            style: MatchPayTokens.titleMediumStyle(),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.tr('groupCodeJoinSubtitle'),
            style: MatchPayTokens.bodySmallStyle(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: l10n.tr('groupCodeJoinField'),
              hintText: '482913',
              counterText: '',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _unirse(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: MatchPayTokens.bodySmallStyle().copyWith(
                color: MatchPayTokens.accentError,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _unirse,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.group_add_rounded),
            label: Text(l10n.tr('groupCodeJoinAction')),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.tr('groupCodeMyGroups'),
            style: MatchPayTokens.titleSmallStyle(),
          ),
          const SizedBox(height: 8),
          if (_loadingGrupos)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_misGrupos.isEmpty)
            MatchPaySurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Text(
                l10n.tr('groupCodeMyGroupsEmpty'),
                style: MatchPayTokens.bodySmallStyle(),
              ),
            )
          else
            ..._misGrupos.map(
              (g) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MatchPaySurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_rounded, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g.nombre,
                          style: MatchPayTokens.titleSmallStyle(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
