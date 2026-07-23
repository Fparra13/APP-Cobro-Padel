import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_repositories.dart';
import '../core/legal_urls.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import 'matchpay_ui.dart';

/// Card compacta: código de grupo + copiar / compartir / regenerar.
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
        text: l10n.tr(
          'groupCodeShareMessage',
          params: {
            'code': code,
            'url': LegalUrls.website,
          },
        ),
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
    final canAct = _codigo != null && !_busy && !_loading;

    return MatchPaySurfaceCard(
      elevated: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                size: 20,
                color: palette.primaryDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.tr('groupCodeTitle'),
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_busy || _loading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: _regenerar,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l10n.tr('groupCodeRegen'),
                    style: MatchPayTokens.bodySmallStyle(
                      color: palette.primaryDark,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(
              _error!,
              style: MatchPayTokens.bodySmallStyle().copyWith(
                color: MatchPayTokens.accentError,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: palette.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      _codigo ?? '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        color: palette.primaryDark,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: l10n.tr('groupCodeCopy'),
                  onPressed: canAct ? _copiar : null,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: l10n.tr('groupCodeShare'),
                  onPressed: canAct ? _compartir : null,
                  icon: const Icon(Icons.share_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
