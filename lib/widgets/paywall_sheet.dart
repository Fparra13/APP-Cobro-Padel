import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal_urls.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/paywall_catalog.dart';
import '../core/subscription_service.dart';
import '../l10n/matchpay_strings.dart';

abstract final class _KlooviBrand {
  static const petrol = Color(0xFF0B1E3A);
  static const petrolMuted = Color(0xFF4A6078);
  static const teal = Color(0xFF2EC4B6);
  static const tealDeep = Color(0xFF1AA89B);
  static const mintWash = Color(0xFFF3FBFA);
  static const mintSoft = Color(0xFFE8F6F3);
  static const paper = Color(0xFFFFFDFB);
  static const line = Color(0xFFE3ECEA);
}

/// Copy de pantalla solo donde el texto UX cambia y no tocamos l10n.
abstract final class _PaywallUxCopy {
  static String headlineBefore(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Everything you need to organize your sports gatherings ';
      case 'pt':
        return 'Tudo o que você precisa para organizar seus encontros esportivos ';
      default:
        return 'Todo lo que necesitas para organizar tus encuentros deportivos ';
    }
  }

  static String headlineAccent(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'effortlessly.';
      case 'pt':
        return 'sem esforço.';
      default:
        return 'sin esfuerzo.';
    }
  }

  static String secondary(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Organize gatherings, confirm participants and keep your group under control from one place.';
      case 'pt':
        return 'Organize encontros, confirme participantes e mantenha o controle do grupo em um só lugar.';
      default:
        return 'Organiza encuentros, confirma participantes y mantén el control de tu grupo desde un solo lugar.';
    }
  }

  static String remindersDesc(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Never chase confirmations.';
      case 'pt':
        return 'Nunca persiga confirmações.';
      default:
        return 'Nunca persigas confirmaciones.';
    }
  }

  static String statsDesc(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'See group activity at a glance.';
      case 'pt':
        return 'Conheça a atividade do grupo.';
      default:
        return 'Conoce la actividad del grupo.';
    }
  }

  static String historyDesc(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Browse all your gatherings.';
      case 'pt':
        return 'Consulte todos os seus encontros.';
      default:
        return 'Consulta todos tus encuentros.';
    }
  }

  static String unlimitedTitle(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Unlimited gatherings';
      case 'pt':
        return 'Encontros ilimitados';
      default:
        return 'Encuentros ilimitados';
    }
  }

  static String unlimitedDesc(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Organize every match you need.';
      case 'pt':
        return 'Organize todos os jogos que precisar.';
      default:
        return 'Organiza todos los partidos que necesites.';
    }
  }

  static String yearlyEquiv(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Equals \$1,249 per month';
      case 'pt':
        return 'Equivale a \$1.249 por mês';
      default:
        return 'Equivale a \$1.249 al mes';
    }
  }

  static String yearlySavings(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'More than 55% savings';
      case 'pt':
        return 'Mais de 55% de economia';
      default:
        return 'Más de 55% de ahorro';
    }
  }

  static String launchOffer(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Launch offer';
      case 'pt':
        return 'Oferta de lançamento';
      default:
        return 'Oferta de lanzamiento';
    }
  }

  static String founderStripLine1(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Only for the first';
      case 'pt':
        return 'Só para os primeiros';
      default:
        return 'Solo para los primeros';
    }
  }

  static String founderStripLine2(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return '1,000 organizers';
      case 'pt':
        return '1.000 organizadores';
      default:
        return '1.000 organizadores';
    }
  }

  static String trialCancelLine(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'Cancel anytime. No commitment.';
      case 'pt':
        return 'Cancele quando quiser. Sem compromisso.';
      default:
        return 'Cancela cuando quieras. Sin compromiso.';
    }
  }

  static String monthlyFlex(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        return 'No lock-in';
      case 'pt':
        return 'Sem permanência';
      default:
        return 'Sin permanencia';
    }
  }
}

/// Paywall visual Kloovi Pro (sin compra; Billing en una etapa posterior).
Future<bool?> showPaywallSheet(
  BuildContext context, {
  required ProFeature feature,
  String? message,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: _KlooviBrand.paper,
    builder: (ctx) => PaywallSheet(feature: feature, message: message),
  );
}

class PaywallSheet extends StatefulWidget {
  final ProFeature feature;
  final String? message;

  const PaywallSheet({
    super.key,
    required this.feature,
    this.message,
  });

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  PaywallPlanId _selected = PaywallPlanId.yearly;

  void _showBillingSoonSnack() {
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tr('paywallBillingSoonSnack'))),
    );
  }

  void _onStartTrial() => _showBillingSoonSnack();

  void _onRestorePurchases() => _showBillingSoonSnack();

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sub = context.watch<SubscriptionService>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.94;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ColoredBox(
          color: _KlooviBrand.paper,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PaywallHero(
                          headlineBefore:
                              _PaywallUxCopy.headlineBefore(context),
                          headlineAccent:
                              _PaywallUxCopy.headlineAccent(context),
                          body: _PaywallUxCopy.secondary(context),
                        ),
                        const SizedBox(height: 18),
                        _BenefitsSection(l10n: l10n),
                        const SizedBox(height: 16),
                        _TrialBanner(l10n: l10n),
                        const SizedBox(height: 16),
                        _PlansRow(
                          selected: _selected,
                          l10n: l10n,
                          onSelect: (id) => setState(() => _selected = id),
                        ),
                        const SizedBox(height: 22),
                        if (sub.isPro)
                          SizedBox(
                            height: 58,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: _ctaStyle(),
                              child: Text(l10n.understood),
                            ),
                          )
                        else ...[
                          SizedBox(
                            height: 58,
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _onStartTrial,
                              style: _ctaStyle(),
                              icon: const Icon(Icons.rocket_launch_rounded,
                                  size: 22),
                              label: Text(
                                l10n.tr('paywallStartTrialCta'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  letterSpacing: -0.15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton(
                              onPressed: _onRestorePurchases,
                              style: TextButton.styleFrom(
                                foregroundColor: _KlooviBrand.tealDeep,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              child: Text(l10n.paywallRestore),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        _LegalFooter(
                          l10n: l10n,
                          onTerms: () => _openUrl(LegalUrls.termsOfService),
                          onPrivacy: () => _openUrl(LegalUrls.privacyPolicy),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _ctaStyle() {
    return FilledButton.styleFrom(
      backgroundColor: _KlooviBrand.tealDeep,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _PaywallHero extends StatelessWidget {
  final String headlineBefore;
  final String headlineAccent;
  final String body;

  const _PaywallHero({
    required this.headlineBefore,
    required this.headlineAccent,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset(
              'assets/brand/logo-wordmark.png',
              height: 24,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: _KlooviBrand.tealDeep,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: MatchPayTokens.titleMediumStyle(color: _KlooviBrand.petrol)
                .copyWith(
              fontSize: 16.5,
              height: 1.32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.25,
            ),
            children: [
              TextSpan(text: headlineBefore),
              TextSpan(
                text: headlineAccent,
                style: const TextStyle(color: _KlooviBrand.tealDeep),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: MatchPayTokens.bodySmallStyle(color: _KlooviBrand.petrolMuted)
              .copyWith(fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}

class _BenefitsSection extends StatelessWidget {
  static const double _gap = 8;

  final MatchPayStrings l10n;

  const _BenefitsSection({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final cards = <(IconData, String, String)>[
      (
        Icons.notifications_none_rounded,
        l10n.tr('paywallBenefitReminders'),
        _PaywallUxCopy.remindersDesc(context),
      ),
      (
        Icons.insights_outlined,
        l10n.tr('paywallBenefitStats'),
        _PaywallUxCopy.statsDesc(context),
      ),
      (
        Icons.calendar_month_outlined,
        l10n.tr('paywallBenefitHistory'),
        _PaywallUxCopy.historyDesc(context),
      ),
      (
        Icons.event_available_outlined,
        _PaywallUxCopy.unlimitedTitle(context),
        _PaywallUxCopy.unlimitedDesc(context),
      ),
    ];

    Widget pair(int a, int b) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _BenefitCard(
                icon: cards[a].$1,
                title: cards[a].$2,
                description: cards[a].$3,
              ),
            ),
            const SizedBox(width: _gap),
            Expanded(
              child: _BenefitCard(
                icon: cards[b].$1,
                title: cards[b].$2,
                description: cards[b].$3,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        pair(0, 1),
        const SizedBox(height: _gap),
        pair(2, 3),
      ],
    );
  }
}

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _KlooviBrand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: _KlooviBrand.mintSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: _KlooviBrand.petrol),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      MatchPayTokens.titleSmallStyle(color: _KlooviBrand.petrol)
                          .copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MatchPayTokens.bodySmallStyle(color: _KlooviBrand.petrolMuted)
                .copyWith(fontSize: 11, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _TrialBanner extends StatelessWidget {
  final MatchPayStrings l10n;

  const _TrialBanner({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: _KlooviBrand.mintWash,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _KlooviBrand.teal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('paywallTrialTitle'),
            style: MatchPayTokens.titleSmallStyle(
              color: _KlooviBrand.petrol,
            ).copyWith(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.check, size: 15, color: _KlooviBrand.tealDeep),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.tr('paywallTrialFullAccess'),
                  style: MatchPayTokens.bodySmallStyle(
                    color: _KlooviBrand.petrol,
                  ).copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _PaywallUxCopy.trialCancelLine(context),
            style: MatchPayTokens.bodySmallStyle(color: _KlooviBrand.petrolMuted)
                .copyWith(fontSize: 12, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _PlansRow extends StatelessWidget {
  final PaywallPlanId selected;
  final MatchPayStrings l10n;
  final ValueChanged<PaywallPlanId> onSelect;

  const _PlansRow({
    required this.selected,
    required this.l10n,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final yearly = PaywallCatalog.offerFor(PaywallPlanId.yearly);
    final monthly = PaywallCatalog.offerFor(PaywallPlanId.monthly);
    final sideBySide = MediaQuery.sizeOf(context).width >= 360;

    if (!sideBySide) {
      return Column(
        children: [
          _PlanCard(
            offer: yearly,
            selected: selected == yearly.id,
            l10n: l10n,
            onTap: () => onSelect(yearly.id),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            offer: monthly,
            selected: selected == monthly.id,
            l10n: l10n,
            onTap: () => onSelect(monthly.id),
          ),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: _PlanCard(
              offer: yearly,
              selected: selected == yearly.id,
              l10n: l10n,
              onTap: () => onSelect(yearly.id),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 9,
            child: _PlanCard(
              offer: monthly,
              selected: selected == monthly.id,
              l10n: l10n,
              onTap: () => onSelect(monthly.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PaywallPlanOffer offer;
  final bool selected;
  final MatchPayStrings l10n;
  final VoidCallback onTap;

  const _PlanCard({
    required this.offer,
    required this.selected,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isYearly = offer.id == PaywallPlanId.yearly;
    final period =
        isYearly ? l10n.tr('paywallPerYear') : l10n.tr('paywallPerMonth');

    final borderColor =
        selected ? _KlooviBrand.tealDeep : _KlooviBrand.line;
    final borderWidth = selected ? 2.0 : 1.0;
    final shadows = selected
        ? [
            BoxShadow(
              color: _KlooviBrand.tealDeep.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ]
        : <BoxShadow>[];

    if (isYearly) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: selected ? _KlooviBrand.mintWash : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: shadows,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      color: _KlooviBrand.tealDeep,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 15, color: Colors.white),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                l10n.tr('paywallFounderBadge').toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: _KlooviBrand.mintWash,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Column(
                          children: [
                            Text(
                              _PaywallUxCopy.launchOffer(context),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _KlooviBrand.tealDeep,
                                letterSpacing: -0.1,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _PaywallUxCopy.founderStripLine1(context),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _KlooviBrand.petrol,
                                height: 1.2,
                              ),
                            ),
                            Text(
                              _PaywallUxCopy.founderStripLine2(context),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _KlooviBrand.petrol,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: offer.formattedPrice,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: _KlooviBrand.tealDeep,
                                    letterSpacing: -0.6,
                                    height: 1,
                                  ),
                                ),
                                TextSpan(
                                  text: ' $period',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _KlooviBrand.petrolMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _PaywallUxCopy.yearlyEquiv(context),
                            style: MatchPayTokens.bodySmallStyle(
                              color: _KlooviBrand.petrolMuted,
                            ).copyWith(fontSize: 12, height: 1.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _PaywallUxCopy.yearlySavings(context),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: _KlooviBrand.tealDeep,
                              height: 1.2,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (selected)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: _CornerCheck(),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: selected ? _KlooviBrand.mintWash : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: shadows,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('paywallPlanMonthly'),
                      style: MatchPayTokens.titleSmallStyle(
                        color: _KlooviBrand.petrol,
                      ).copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.tr('paywallMonthlyIdeal'),
                      style: MatchPayTokens.bodySmallStyle(
                        color: _KlooviBrand.petrolMuted,
                      ).copyWith(fontSize: 12.5, height: 1.3),
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: offer.formattedPrice,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _KlooviBrand.tealDeep,
                              letterSpacing: -0.5,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: ' $period',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _KlooviBrand.petrolMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Perk(l10n.tr('paywallMonthlyCancel')),
                    const SizedBox(height: 4),
                    _Perk(_PaywallUxCopy.monthlyFlex(context)),
                  ],
                ),
              ),
              if (selected)
                const Positioned(
                  top: 10,
                  right: 10,
                  child: _CornerCheck(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerCheck extends StatelessWidget {
  const _CornerCheck();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _KlooviBrand.tealDeep, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _KlooviBrand.petrol.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Icon(Icons.check, size: 13, color: _KlooviBrand.tealDeep),
    );
  }
}

class _Perk extends StatelessWidget {
  final String text;

  const _Perk(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, size: 15, color: _KlooviBrand.tealDeep),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: MatchPayTokens.bodySmallStyle(color: _KlooviBrand.petrol)
                .copyWith(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _LegalFooter extends StatefulWidget {
  final MatchPayStrings l10n;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  const _LegalFooter({
    required this.l10n,
    required this.onTerms,
    required this.onPrivacy,
  });

  @override
  State<_LegalFooter> createState() => _LegalFooterState();
}

class _LegalFooterState extends State<_LegalFooter> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = widget.onTerms;
    _privacyTap = TapGestureRecognizer()..onTap = widget.onPrivacy;
  }

  @override
  void didUpdateWidget(covariant _LegalFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _termsTap.onTap = widget.onTerms;
    _privacyTap.onTap = widget.onPrivacy;
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = MatchPayTokens.bodySmallStyle(color: _KlooviBrand.petrolMuted)
        .copyWith(fontSize: 11.5, height: 1.4);
    final link = base.copyWith(
      color: _KlooviBrand.tealDeep,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: _KlooviBrand.tealDeep.withValues(alpha: 0.45),
    );

    return Text.rich(
      textAlign: TextAlign.center,
      TextSpan(
        style: base,
        children: [
          TextSpan(text: widget.l10n.tr('paywallLegalAcceptPrefix')),
          TextSpan(
            text: widget.l10n.termsOfService,
            style: link,
            recognizer: _termsTap,
          ),
          TextSpan(text: widget.l10n.tr('paywallLegalAcceptAnd')),
          TextSpan(
            text: widget.l10n.tr('privacyPolicy'),
            style: link,
            recognizer: _privacyTap,
          ),
          TextSpan(text: widget.l10n.tr('paywallLegalAcceptSuffix')),
        ],
      ),
    );
  }
}
