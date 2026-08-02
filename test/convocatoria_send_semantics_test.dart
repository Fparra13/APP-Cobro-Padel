import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/convocatoria_send_semantics.dart';
import 'package:matchpay/l10n/translation_maps.dart';

void main() {
  group('ConvocatoriaSendSemantics.run', () {
    test('save OK + deadlines OK + notifications OK → sent, close UI', () async {
      var saveCalls = 0;
      var deadlineCalls = 0;
      var notifyCalls = 0;

      final status = await ConvocatoriaSendSemantics.run(
        save: () async {
          saveCalls++;
          return true;
        },
        activateDeadlines: () async {
          deadlineCalls++;
        },
        notify: () async {
          notifyCalls++;
        },
      );

      expect(status, ConvocatoriaSendStatus.sent);
      expect(ConvocatoriaSendSemantics.isConsideredSent(status), isTrue);
      expect(ConvocatoriaSendSemantics.shouldCloseUi(status), isTrue);
      expect(
        ConvocatoriaSendSemantics.snackMessageKey(status),
        'organizeInviteSentSnack',
      );
      expect(saveCalls, 1);
      expect(deadlineCalls, 1);
      expect(notifyCalls, 1);
    });

    test(
      'save OK + deadlines OK + notifications fail → sentWithNotificationGaps',
      () async {
        var notifyCalls = 0;

        final status = await ConvocatoriaSendSemantics.run(
          save: () async => true,
          activateDeadlines: () async {},
          notify: () async {
            notifyCalls++;
            throw Exception('FCM down');
          },
        );

        expect(status, ConvocatoriaSendStatus.sentWithNotificationGaps);
        expect(ConvocatoriaSendSemantics.isConsideredSent(status), isTrue);
        expect(ConvocatoriaSendSemantics.shouldCloseUi(status), isTrue);
        expect(
          ConvocatoriaSendSemantics.snackMessageKey(status),
          'organizeInviteSentPartialNoticesSnack',
        );
        expect(notifyCalls, 1);
        // No retry from semantics — caller must not re-send on this outcome.
      },
    );

    test('save fails → notSent; deadlines/notify not called', () async {
      var deadlineCalls = 0;
      var notifyCalls = 0;

      final status = await ConvocatoriaSendSemantics.run(
        save: () async => false,
        activateDeadlines: () async {
          deadlineCalls++;
        },
        notify: () async {
          notifyCalls++;
        },
      );

      expect(status, ConvocatoriaSendStatus.notSent);
      expect(ConvocatoriaSendSemantics.isConsideredSent(status), isFalse);
      expect(ConvocatoriaSendSemantics.shouldCloseUi(status), isFalse);
      expect(deadlineCalls, 0);
      expect(notifyCalls, 0);
    });

    test('deadlines throw → propagates; notify not called', () async {
      var notifyCalls = 0;

      await expectLater(
        () => ConvocatoriaSendSemantics.run(
          save: () async => true,
          activateDeadlines: () async {
            throw StateError('deadline write failed');
          },
          notify: () async {
            notifyCalls++;
          },
        ),
        throwsStateError,
      );
      expect(notifyCalls, 0);
    });
  });

  group('partial-success copy ES/EN/PT', () {
    test('organizeInviteSentPartialNoticesSnack exists in all locales', () {
      for (final lang in ['es', 'en', 'pt']) {
        final text = TranslationMaps.lookup(
          lang,
          'organizeInviteSentPartialNoticesSnack',
        );
        expect(text, isNot(equals('organizeInviteSentPartialNoticesSnack')));
        expect(text.toLowerCase(), anyOf(contains('envi'), contains('sent')));
      }
    });
  });
}
