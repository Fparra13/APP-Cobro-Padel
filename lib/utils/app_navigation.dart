import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/feature_gate.dart';
import '../core/subscription_service.dart';
import '../l10n/matchpay_strings.dart';
import '../screens/nuevo_partido_screen.dart';
import '../screens/organizar_partido_screen.dart';
import '../services/notification_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../utils/matchpay_context.dart';

/// Contexto del navigator raíz de la app (siempre encima del shell).
BuildContext? get matchPayRootContext =>
    NotificationService.instance.navigatorKey?.currentContext;

/// Menú crear partido / convocatoria (organizador).
Future<void> showOrganizerMatchMenu(BuildContext context) async {
  final host = matchPayRootContext ?? context;
  if (!host.mounted) return;

  final l10n = host.l10n;

  await showDialog<void>(
    context: host,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tr('homeMatchMenuTitle'),
              style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _MatchMenuActionCard(
              icon: Icons.campaign_rounded,
              iconColor: const Color(0xFF1D4ED8),
              iconBg: const Color(0xFFDBEAFE),
              title: l10n.tr('homeOrganizeConvocatoria'),
              subtitle: l10n.tr('homeOrganizeConvocatoriaSubtitle'),
              onTap: () async {
                Navigator.pop(ctx);
                await abrirOrganizarPartido(host);
                AppRepositories.notifyDataChanged();
              },
            ),
            const SizedBox(height: 10),
            _MatchMenuActionCard(
              icon: Icons.sports_score_rounded,
              iconColor: const Color(0xFF047857),
              iconBg: const Color(0xFFD1FAE5),
              title: l10n.tr('homeRegisterPlayedMatch'),
              subtitle: l10n.tr('homeRegisterPlayedMatchSubtitle'),
              onTap: () async {
                Navigator.pop(ctx);
                await abrirNuevoPartidoJugado(host);
                AppRepositories.notifyDataChanged();
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.tr('cancel')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MatchMenuActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MatchMenuActionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.sportPalette.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
            border: Border.all(color: MatchPayTokens.borderStrong),
            color: MatchPayTokens.surfaceInset,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: MatchPayTokens.titleSmallStyle().copyWith(
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: MatchPayTokens.bodySmallStyle().copyWith(
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: accent,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> abrirOrganizarPartido(
  BuildContext context, {
  int? partidoId,
}) async {
  if (partidoId == null) {
    final allowed = await FeatureGate.requirePro(
      context,
      feature: ProFeature.createMatch,
      message: context.l10n.tr('proRequiredCreateMatch'),
    );
    if (!allowed || !context.mounted) return null;
  }

  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (ctx) => AppRepositoriesScope(
        repos: AppRepositories.I,
        child: OrganizarPartidoScreen(partidoId: partidoId),
      ),
    ),
  );
}

Future<bool?> abrirNuevoPartidoJugado(BuildContext context) async {
  final allowed = await FeatureGate.requirePro(
    context,
    feature: ProFeature.createMatch,
    message: context.l10n.tr('proRequiredRegisterMatch'),
  );
  if (!allowed || !context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (ctx) => AppRepositoriesScope(
        repos: AppRepositories.I,
        child: const NuevoPartidoScreen(),
      ),
    ),
  );
}
