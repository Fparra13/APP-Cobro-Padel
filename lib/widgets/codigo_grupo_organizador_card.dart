import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/codigo_grupo_share.dart';
import '../utils/matchpay_context.dart';
import 'matchpay_ui.dart';

/// Formatea código de 6 dígitos como `227 695`.
String formatCodigoGrupoDisplay(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 6) {
    return '${digits.substring(0, 3)} ${digits.substring(3)}';
  }
  return raw.trim();
}

/// Card: código de grupo.
///
/// [invitationHero]: tarjeta de invitación premium (Home vacío).
/// Incluye compartir/copiar. Sin regenerar (los códigos no “expiran” en UX).
class CodigoGrupoOrganizadorCard extends StatefulWidget {
  final bool showShareAsPrimaryCta;
  final bool showCompactActions;
  final bool invitationHero;

  const CodigoGrupoOrganizadorCard({
    super.key,
    this.showShareAsPrimaryCta = false,
    this.showCompactActions = true,
    this.invitationHero = false,
  });

  @override
  State<CodigoGrupoOrganizadorCard> createState() =>
      _CodigoGrupoOrganizadorCardState();
}

class _CodigoGrupoOrganizadorCardState
    extends State<CodigoGrupoOrganizadorCard>
    with SingleTickerProviderStateMixin {
  String? _codigo;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _copiedFlash = false;
  late final AnimationController _appear;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _cargar();
  }

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
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
      _appear.forward(from: 0);
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
    HapticFeedback.lightImpact();
    setState(() => _copiedFlash = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.tr('groupCodeCopied'))));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _copiedFlash = false);
  }

  Future<void> _compartir() async {
    HapticFeedback.selectionClick();
    await compartirCodigoGrupoOrganizador(context);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.tr('groupCodeRegenDone'))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.userError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.invitationHero) {
      return _buildInvitationHero(context);
    }
    return _buildCompact(context);
  }

  Widget _buildInvitationHero(BuildContext context) {
    final l10n = context.l10n;
    // Marca Kloovi fija (no sportPalette: puede ser azul por deporte).
    const mint = Color(0xFF2EC4B6); // turquesa / verde menta
    const mintDark = Color(0xFF1AA89B);
    const mintWash = Color(0xFFF3FBFA);
    final canAct = _codigo != null && !_busy && !_loading;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(
          CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                mintWash,
                mint.withValues(alpha: 0.22),
              ],
            ),
            border: Border.all(
              color: mint.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: mintDark.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          child: Column(
            children: [
              Text(
                l10n.tr('groupCodeInviteCardTitle').toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: mintDark.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 18),
              if (_loading || _busy)
                const SizedBox(
                  height: 64,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: mintDark,
                    ),
                  ),
                )
              else if (_error != null)
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    color: MatchPayTokens.accentError,
                  ),
                )
              else
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: _copiedFlash ? 48 : 46,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    height: 1.05,
                    color: mintDark,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: Text(
                    formatCodigoGrupoDisplay(_codigo ?? '—'),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                l10n.tr('groupCodeInviteCardBody'),
                textAlign: TextAlign.center,
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkSecondary,
                ).copyWith(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canAct ? _compartir : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: mintDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  label: Text(
                    l10n.tr('organizerActivationShareCta'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: canAct ? _copiar : null,
                style: TextButton.styleFrom(
                  foregroundColor: mintDark,
                ),
                icon: Icon(
                  _copiedFlash ? Icons.check_rounded : Icons.copy_rounded,
                  size: 18,
                ),
                label: Text(
                  _copiedFlash
                      ? l10n.tr('groupCodeCopied')
                      : l10n.tr('groupCodeCopy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
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
                Icons.link_rounded,
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
                      formatCodigoGrupoDisplay(_codigo ?? '—'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: palette.primaryDark,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (widget.showCompactActions) ...[
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
              ],
            ),
          if (widget.showShareAsPrimaryCta) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canAct ? _compartir : null,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primaryDark,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.share_rounded),
                label: Text(l10n.tr('groupCodeShare')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
