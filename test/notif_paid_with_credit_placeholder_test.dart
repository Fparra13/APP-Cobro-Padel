import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/l10n/translation_maps.dart';

/// A10: placeholders en notifMatchPaidWithCredit* deben coincidir con
/// los params que pasa [CobroNotificacionService] (`matchAmount`, `credit`).
void main() {
  const callerParams = {
    'matchAmount': r'$10.000',
    'credit': r'$4.000',
  };

  RegExp placeholderPattern(String name) => RegExp('\\{$name\\}');

  Set<String> placeholdersIn(String template) {
    return RegExp(r'\{([a-zA-Z0-9_]+)\}')
        .allMatches(template)
        .map((m) => m.group(1)!)
        .toSet();
  }

  group('notifMatchPaidWithCreditBody', () {
    for (final lang in ['es', 'en', 'pt']) {
      test('$lang declares only caller-known placeholders and renders', () {
        final template = TranslationMaps.lookup(
          lang,
          'notifMatchPaidWithCreditBody',
        );
        final declared = placeholdersIn(template);
        expect(
          declared.difference(callerParams.keys.toSet()),
          isEmpty,
          reason: '$lang has undeclared placeholders: $declared',
        );
        expect(
          template.contains('{sessionAmount}'),
          isFalse,
          reason: 'EN historically used {sessionAmount}; must be {matchAmount}',
        );

        final rendered = TranslationMaps.lookup(
          lang,
          'notifMatchPaidWithCreditBody',
          params: callerParams,
        );
        expect(rendered, contains(callerParams['matchAmount']!));
        expect(rendered, contains(callerParams['credit']!));
        expect(placeholderPattern('matchAmount').hasMatch(rendered), isFalse);
        expect(placeholderPattern('credit').hasMatch(rendered), isFalse);
        expect(placeholderPattern('sessionAmount').hasMatch(rendered), isFalse);
      });
    }
  });

  group('notifMatchChargeDetailVenue {venue}', () {
    test('caller param venue matches template in ES/EN/PT', () {
      const venue = 'Club Norte';
      for (final lang in ['es', 'en', 'pt']) {
        final template = TranslationMaps.lookup(
          lang,
          'notifMatchChargeDetailVenue',
        );
        expect(placeholdersIn(template), equals({'venue'}));
        final rendered = TranslationMaps.lookup(
          lang,
          'notifMatchChargeDetailVenue',
          params: {'venue': venue},
        );
        expect(rendered, contains(venue));
        expect(rendered.contains('{venue}'), isFalse);
      }
    });
  });
}
