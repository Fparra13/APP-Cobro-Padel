import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import 'matchpay_ui.dart';

/// Card para que el organizador vea, copie, comparta y regenere su código.
class CodigoGrupoOrganizadorCard extends StatefulWidget {
  const CodigoGrupoOrganizadorCard({super.key});

  @override
  State<CodigoGrupoOrganizadorCard> createState() =>
      _CodigoGrupoOrganizadorCardState();
}

class _CodigoGrupoOrganizadorCardState extends State<CodigoGrupoOrganizadorCard> {
  String? _codigo;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await context.repos.obtenerMiCodigoGrupo();
      if (!mounted) return;
      setState(() {
        _codigo = code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.userError(e);
      });
    }
  }

  Future<void> _copiar() async {
    final code = _codigo;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('groupCodeCopied'))),
    );
  }

  Future<void> _compartir() async {
    final code = _codigo;
    if (code == null || code.isEmpty) return;
    final l10n = context.l10n;
    await SharePlus.instance.share(
      ShareParams(
        text: l10n.tr('groupCodeShareMessage', params: {'code': code}),
      ),
    );
  }

  Future<void> _regenerar() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('groupCodeRegenTitle')),
        content: Text(l10n.tr('groupCodeRegenBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('groupCodeRegenConfirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final code = await context.repos.regenerarMiCodigoGrupo();
      if (!mounted) return;
      setState(() {
        _codigo = code;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('groupCodeRegenDone'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.userError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return MatchPaySurfaceCard(
      elevated: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: palette.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.tr('groupCodeTitle'),
                  style: MatchPayTokens.titleSmallStyle(),
                ),
              ),
              if (_busy || _loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.tr('groupCodeSubtitle'),
            style: MatchPayTokens.bodySmallStyle(),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Text(
              _error!,
              style: MatchPayTokens.bodySmallStyle().copyWith(
                color: MatchPayTokens.accentError,
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: palette.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                _codigo ?? '—',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _codigo == null || _busy ? null : _copiar,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(l10n.tr('groupCodeCopy')),
              ),
              OutlinedButton.icon(
                onPressed: _codigo == null || _busy ? null : _compartir,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(l10n.tr('groupCodeShare')),
              ),
              TextButton(
                onPressed: _busy || _loading ? null : _regenerar,
                child: Text(l10n.tr('groupCodeRegen')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
