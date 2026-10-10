import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/acquisition_controller.dart';
import 'package:matchpay/core/app_settings_controller.dart';
import 'package:matchpay/core/feature_gate.dart';
import 'package:matchpay/core/subscription_service.dart';
import 'package:matchpay/l10n/translation_maps.dart';
import 'package:matchpay/widgets/paywall_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSettings extends AppSettingsController {
  @override
  Locale get locale => const Locale('es');
}

Widget _wrapGateHarness(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSettingsController>.value(
        value: _TestSettings(),
      ),
      ChangeNotifierProvider<SubscriptionService>.value(
        value: SubscriptionService.instance,
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SubscriptionService.debugValidatorOverride = null;
    final sub = SubscriptionService.instance;
    sub.clearProfileEntitlements();
    await sub.clearCommercialEntitlement();
  });

  tearDown(() async {
    SubscriptionService.debugValidatorOverride = null;
    final sub = SubscriptionService.instance;
    sub.clearProfileEntitlements();
    await sub.clearCommercialEntitlement();
  });

  group('Organizer flow source contract', () {
    test('openOrganizerSubscriptionFlow no usa requirePro ni paywall', () {
      final source = File('lib/utils/organizer_subscription_flow.dart')
          .readAsStringSync();
      expect(source.contains("import '../core/feature_gate.dart'"), isFalse);
      expect(source.contains('requirePro'), isFalse);
      expect(source.contains('showPaywallSheet'), isFalse);
      expect(source.contains('becomeOrganizer()'), isTrue);
      expect(source.contains('paywall/trial'), isFalse);
    });

    test('app_navigation gates create vs edit correctamente', () {
      final source =
          File('lib/utils/app_navigation.dart').readAsStringSync();
      // Nuevo encuentro: gate dentro de partidoId == null.
      expect(
        source.contains('if (partidoId == null)'),
        isTrue,
      );
      expect(
        RegExp(
          r'if \(partidoId == null\)[\s\S]*?FeatureGate\.requirePro',
        ).hasMatch(source),
        isTrue,
      );
      // Registrar jugado siempre gated.
      expect(
        RegExp(
          r'abrirNuevoPartidoJugado[\s\S]*?FeatureGate\.requirePro',
        ).hasMatch(source),
        isTrue,
      );
    });

    test('FeatureGate no consulta isOrganizer', () {
      final source = File('lib/core/feature_gate.dart').readAsStringSync();
      expect(source.contains('isOrganizer'), isFalse);
      expect(source.contains('AuthService'), isFalse);
      expect(source.contains('SubscriptionService'), isTrue);
    });

    test('main.dart named routes de crear requieren partidoId int', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source.contains("'/editar-convocatoria'"), isTrue);
      expect(source.contains("'/editar-partido'"), isTrue);
      // No hay ruta named de "crear convocatoria" sin id.
      expect(source.contains("'/organizar-partido'"), isFalse);
      expect(source.contains("'/crear-convocatoria'"), isFalse);
      expect(
        source.contains(
          'Crear encuentro/partido solo vía FeatureGate',
        ),
        isTrue,
      );
    });

    test('notification_service abre Organizar solo con partidoId', () {
      final source =
          File('lib/services/notification_service.dart').readAsStringSync();
      expect(
        RegExp(
          r'_abrirPartidoOrganizador\(int partidoId\)',
        ).hasMatch(source),
        isTrue,
      );
      expect(
        RegExp(
          r'OrganizarPartidoScreen\(\s*partidoId:\s*partidoId',
        ).hasMatch(source),
        isTrue,
      );
    });
  });

  group('Copy Organizer ≠ Pro', () {
    test('ES/EN/PT no exigen Pro para ser Organizer', () {
      final locales = <String, Map<String, String>>{
        'es': TranslationMaps.es,
        'en': TranslationMaps.en,
        'pt': TranslationMaps.pt,
      };
      for (final entry in locales.entries) {
        final locale = entry.key;
        final map = entry.value;
        final paywallMsg = map['becomeOrganizerPaywallMessage']!;
        final done = map['becomeOrganizerDone']!;
        final createMsg = map['proRequiredCreateMatch']!;

        expect(
          paywallMsg.toLowerCase().contains('gratis') ||
              paywallMsg.toLowerCase().contains('free') ||
              paywallMsg.toLowerCase().contains('grátis'),
          isTrue,
          reason: '$locale paywall message should say organizer is free',
        );
        expect(
          createMsg.toLowerCase().contains('pro'),
          isTrue,
          reason: '$locale create message should mention Pro',
        );
        // Done confirma rol y aclara creación Pro.
        expect(
          done.toLowerCase().contains('pro'),
          isTrue,
          reason: '$locale done should mention Pro for creating',
        );
      }
    });
  });

  group('FeatureGate / Pro entitlement', () {
    test('can(createMatch) no depende de un rol Organizer', () {
      final sub = SubscriptionService.instance;
      sub.syncFromProfile(accesoIlimitado: false, email: 'player@example.com');
      expect(sub.can(ProFeature.createMatch), isFalse);

      sub.syncFromProfile(accesoIlimitado: true, email: 'staff@example.com');
      expect(sub.can(ProFeature.createMatch), isTrue);
      // Sigue sin haber noción de isOrganizer en SubscriptionService.
      expect(sub.isPro, isTrue);
    });

    testWidgets('sin Pro, requirePro muestra paywall scaffolding',
        (tester) async {
      final sub = SubscriptionService.instance;
      sub.syncFromProfile(accesoIlimitado: false, email: 'nopro@example.com');
      await sub.clearCommercialEntitlement();

      bool? allowed;
      await tester.pumpWidget(
        _wrapGateHarness(
          Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    allowed = await FeatureGate.requirePro(
                      context,
                      feature: ProFeature.createMatch,
                      message: 'Crear requiere Pro',
                    );
                  },
                  child: const Text('gate'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('gate'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallSheet), findsOneWidget);
      // Cerrar sheet sin ser Pro → no concede acceso.
      Navigator.of(tester.element(find.byType(PaywallSheet))).pop(false);
      await tester.pumpAndSettle();
      expect(allowed, isFalse);
    });

    testWidgets('con Pro (staff), requirePro permite sin paywall',
        (tester) async {
      final sub = SubscriptionService.instance;
      sub.syncFromProfile(accesoIlimitado: true, email: 'staff@example.com');

      bool? allowed;
      await tester.pumpWidget(
        _wrapGateHarness(
          Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    allowed = await FeatureGate.requirePro(
                      context,
                      feature: ProFeature.createMatch,
                    );
                  },
                  child: const Text('gate'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('gate'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallSheet), findsNothing);
      expect(allowed, isTrue);
    });
  });

  group('createFirstGroup acquisition', () {
    test('marca pending organizer y no abre crear encuentro', () async {
      SharedPreferences.setMockInitialValues({});
      final acq = AcquisitionController.instance;
      await acq.initialize();
      await acq.chooseCreateFirstGroup();

      expect(acq.intent, MatchPayAcquisitionIntent.createFirstGroup);

      acq.markPendingOpenOrganizer();
      // Consumir el pending no navega a OrganizarPartidoScreen (solo limpia flag).
      expect(acq.consumePendingOpenOrganizer(), isTrue);
      expect(acq.consumePendingOpenOrganizer(), isFalse);
    });
  });
}
