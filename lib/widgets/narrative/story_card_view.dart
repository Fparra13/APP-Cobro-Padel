import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/matchpay_design_tokens.dart';
import '../../domain/story_models.dart';
import '../../l10n/matchpay_strings.dart';
import '../../utils/matchpay_context.dart';

/// Orquestador visual de una [StoryCard] del motor narrativo.
///
/// Delega por [NarrativeFamily] a tarjetas con intención emocional distinta.
/// No conoce el motor: solo consume el contrato de dominio.
class StoryCardView extends StatelessWidget {
  final StoryCard card;

  /// Eyebrow opcional sobre el contenido (p. ej. «Hoy para ti»).
  final String? sectionLabel;

  const StoryCardView({
    super.key,
    required this.card,
    this.sectionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final child = switch (card.family) {
      NarrativeFamily.momento => _MomentoCard(card: card),
      NarrativeFamily.memoria => _MemoriaCard(card: card),
      NarrativeFamily.recordatorio => _RecordatorioCard(card: card),
    };

    if (sectionLabel == null || sectionLabel!.trim().isEmpty) {
      return child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            sectionLabel!,
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkMuted,
            ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        ),
        child,
      ],
    );
  }
}

// ── Intensidad (métricas menores compartidas) ───────────────────────────────

class _IntensityMetrics {
  final EdgeInsets padding;
  final double emojiSize;
  final double titleSize;
  final double radius;
  final double elevation;
  final double borderWidth;

  const _IntensityMetrics({
    required this.padding,
    required this.emojiSize,
    required this.titleSize,
    required this.radius,
    required this.elevation,
    required this.borderWidth,
  });

  factory _IntensityMetrics.of(StoryIntensity intensity) {
    return switch (intensity) {
      StoryIntensity.hero => const _IntensityMetrics(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
          emojiSize: 36,
          titleSize: 19,
          radius: 22,
          elevation: 10,
          borderWidth: 1.4,
        ),
      StoryIntensity.high => const _IntensityMetrics(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
          emojiSize: 30,
          titleSize: 17,
          radius: 20,
          elevation: 6,
          borderWidth: 1.2,
        ),
      StoryIntensity.medium => const _IntensityMetrics(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
          emojiSize: 26,
          titleSize: 16,
          radius: 18,
          elevation: 3,
          borderWidth: 1,
        ),
      StoryIntensity.low => const _IntensityMetrics(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
          emojiSize: 22,
          titleSize: 15,
          radius: 16,
          elevation: 0,
          borderWidth: 1,
        ),
    };
  }
}

String _localizedTitle(BuildContext context, StoryCard card) {
  final l10n = context.l10n;
  final title = l10n.tr(card.title);
  final emoji = card.emoji.trim();
  if (emoji.isEmpty) return title;
  return '$emoji $title';
}

String _localizedBody(BuildContext context, StoryCard card) {
  final params = Map<String, String>.from(card.params);
  if (params.containsKey('day')) {
    params['day'] = _localizeWeekdayParam(context, params['day']!);
  }
  return context.l10n.tr(card.subtitle, params: params);
}

String _localizeWeekdayParam(BuildContext context, String raw) {
  final weekday = int.tryParse(raw);
  if (weekday == null || weekday < 1 || weekday > 7) return raw;
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.EEEE(locale).format(DateTime(2024, 1, weekday));
}

String? _temporalAnchorLabel(BuildContext context, StoryCard card) {
  final anchor = card.anchor;
  if (anchor == null) return null;

  final fromMeta = anchor.meta['anchorLabel']?.trim();
  if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;

  final origin = anchor.anniversaryOf ?? anchor.occurredAt;
  if (origin == null) return null;

  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(origin.year, origin.month, origin.day))
      .inDays;
  if (days < 0) return null;

  final lang = Localizations.localeOf(context).languageCode;
  if (days == 0) {
    return switch (lang) {
      'en' => 'Today',
      'pt' => 'Hoje',
      _ => 'Hoy',
    };
  }
  if (days == 1) {
    return switch (lang) {
      'en' => 'Yesterday',
      'pt' => 'Ontem',
      _ => 'Ayer',
    };
  }
  if (days < 30) {
    return switch (lang) {
      'en' => days == 1 ? '1 day ago' : '$days days ago',
      'pt' => days == 1 ? 'Há 1 dia' : 'Há $days dias',
      _ => 'Hace $days días',
    };
  }
  if (days < 365) {
    final months = (days / 30).floor().clamp(1, 11);
    return switch (lang) {
      'en' => months == 1 ? '1 month ago' : '$months months ago',
      'pt' => months == 1 ? 'Há 1 mês' : 'Há $months meses',
      _ => months == 1 ? 'Hace 1 mes' : 'Hace $months meses',
    };
  }
  final years = (days / 365).floor().clamp(1, 99);
  return switch (lang) {
    'en' => years == 1 ? '1 year ago' : '$years years ago',
    'pt' => years == 1 ? 'Há 1 ano' : 'Há $years anos',
    _ => years == 1 ? 'Hace 1 año' : 'Hace $years años',
  };
}

String _familyEyebrow(BuildContext context, NarrativeFamily family) {
  final lang = Localizations.localeOf(context).languageCode;
  return switch (family) {
    NarrativeFamily.momento => switch (lang) {
        'en' => 'MOMENT',
        'pt' => 'MOMENTO',
        _ => 'MOMENTO',
      },
    NarrativeFamily.memoria => switch (lang) {
        'en' => 'MEMORY',
        'pt' => 'MEMÓRIA',
        _ => 'MEMORIA',
      },
    NarrativeFamily.recordatorio => switch (lang) {
        'en' => 'NOTE',
        'pt' => 'LEMBRETE',
        _ => 'RECORDATORIO',
      },
  };
}

// ── Momento: celebración ────────────────────────────────────────────────────

class _MomentoCard extends StatelessWidget {
  final StoryCard card;

  const _MomentoCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final palette = context.sportPalette;
    final m = _IntensityMetrics.of(card.intensity);
    final title = _localizedTitle(context, card);
    final body = _localizedBody(context, card);

    return Container(
      width: double.infinity,
      padding: m.padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.primary.withValues(alpha: 0.22),
            palette.primary.withValues(alpha: 0.08),
            MatchPayTokens.surfaceCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.45, 1],
        ),
        borderRadius: BorderRadius.circular(m.radius),
        border: Border.all(
          color: palette.primary.withValues(alpha: 0.35),
          width: m.borderWidth,
        ),
        boxShadow: m.elevation <= 0
            ? null
            : [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.18),
                  blurRadius: m.elevation,
                  offset: Offset(0, m.elevation * 0.35),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(card.emoji, style: TextStyle(fontSize: m.emojiSize)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _familyEyebrow(context, NarrativeFamily.momento),
                  style: MatchPayTokens.bodySmallStyle(
                    color: palette.primaryDark,
                  ).copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: card.intensity == StoryIntensity.low ? 8 : 12),
          Text(
            title.contains(card.emoji)
                ? title.replaceFirst('${card.emoji} ', '')
                : title,
            style: MatchPayTokens.titleSmallStyle().copyWith(
              fontSize: m.titleSize,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: MatchPayTokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkSecondary,
            ).copyWith(height: 1.4, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

// ── Recordatorio: conversación ──────────────────────────────────────────────

class _RecordatorioCard extends StatelessWidget {
  final StoryCard card;

  const _RecordatorioCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final m = _IntensityMetrics.of(card.intensity);
    final title = _localizedTitle(context, card);
    final body = _localizedBody(context, card);

    return Container(
      width: double.infinity,
      padding: m.padding,
      decoration: BoxDecoration(
        color: MatchPayTokens.surfaceInset,
        borderRadius: BorderRadius.circular(m.radius),
        border: Border.all(
          color: MatchPayTokens.borderSubtle,
          width: m.borderWidth,
        ),
        boxShadow: m.elevation <= 0
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: m.elevation * 0.6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.emoji, style: TextStyle(fontSize: m.emojiSize)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.contains(card.emoji)
                      ? title.replaceFirst('${card.emoji} ', '')
                      : title,
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: m.titleSize - 0.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: MatchPayTokens.bodySmallStyle(
                    color: MatchPayTokens.inkSecondary,
                  ).copyWith(height: 1.4, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Memoria: intimidad / postal ─────────────────────────────────────────────

class _MemoriaCard extends StatelessWidget {
  final StoryCard card;

  const _MemoriaCard({required this.card});

  static const _warmBg = Color(0xFFF7F1E8);
  static const _warmBorder = Color(0xFFD6C4A8);
  static const _warmInk = Color(0xFF5C4A32);

  @override
  Widget build(BuildContext context) {
    final m = _IntensityMetrics.of(card.intensity);
    final title = _localizedTitle(context, card);
    final body = _localizedBody(context, card);
    final anchorLabel = _temporalAnchorLabel(context, card);

    return Container(
      width: double.infinity,
      padding: m.padding,
      decoration: BoxDecoration(
        color: _warmBg,
        borderRadius: BorderRadius.circular(m.radius),
        border: Border.all(
          color: _warmBorder,
          width: m.borderWidth + 0.2,
        ),
        boxShadow: m.elevation <= 0
            ? null
            : [
                BoxShadow(
                  color: _warmBorder.withValues(alpha: 0.35),
                  blurRadius: m.elevation * 0.7,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(card.emoji, style: TextStyle(fontSize: m.emojiSize)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _familyEyebrow(context, NarrativeFamily.memoria),
                  style: MatchPayTokens.bodySmallStyle(
                    color: _warmInk,
                  ).copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          if (anchorLabel != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _warmBorder.withValues(alpha: 0.7)),
              ),
              child: Text(
                anchorLabel,
                style: MatchPayTokens.bodySmallStyle(
                  color: _warmInk,
                ).copyWith(fontWeight: FontWeight.w600, fontSize: 11.5),
              ),
            ),
          ],
          SizedBox(height: card.intensity == StoryIntensity.low ? 8 : 12),
          Text(
            title.contains(card.emoji)
                ? title.replaceFirst('${card.emoji} ', '')
                : title,
            style: MatchPayTokens.titleSmallStyle(
              color: _warmInk,
            ).copyWith(
              fontSize: m.titleSize,
              fontWeight: FontWeight.w700,
              height: 1.3,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkSecondary,
            ).copyWith(height: 1.45, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
