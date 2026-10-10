import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/app_settings_controller.dart';
import 'package:matchpay/core/billing/billing_entitlement.dart';
import 'package:matchpay/core/billing/play_purchase_payload.dart';
import 'package:matchpay/core/billing/play_purchase_validation_result.dart';
import 'package:matchpay/core/billing/play_purchase_validator.dart';
import 'package:matchpay/core/feature_gate.dart';
import 'package:matchpay/core/subscription_service.dart';
import 'package:matchpay/widgets/paywall_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSettings extends AppSettingsController {
  @override
  Locale get locale => const Locale('es');
}

class _FakeValidator implements PlayPurchaseValidator {
  BillingEntitlement next = BillingEntitlement.none;
  Object? throwOnFetch;
  int fetchCount = 0;

  @override
  Future<BillingEntitlement> fetchEntitlement() async {
    fetchCount++;
    final err = throwOnFetch;
    if (err != null) throw err;
    return next;
  }

  @override
  Future<PlayPurchaseValidationResult> validate(PlayPurchasePayload payload) {
    throw UnimplementedError();
  }
}

BillingEntitlement _proEntitlement({DateTime? expiresAt, String status = 'active'}) {
  return BillingEntitlement(
    isPro: true,
    source: 'subscription',
    status: status,
    productId: 'kloovi_pro_monthly',
    expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(days: 14)),
    isTrial: status == 'trial',
    isFounder: false,
    autoRenewing: true,
    lastVerifiedAt: DateTime.now().toUtc(),
  );
}

Widget _wrap(Widget child) {
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
  late _FakeValidator fake;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fake = _FakeValidator();
    SubscriptionService.debugValidatorOverride = fake;
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

  testWidgets(
    'Pro en memoria + RPC is_pro=false → requirePro no autoriza',
    (tester) async {
      final sub = SubscriptionService.instance;
      sub.syncFromProfile(accesoIlimitado: false, email: 'u@example.com');
      sub.applyEntitlement(_proEntitlement());
      expect(sub.isPro, isTrue);

      fake.next = BillingEntitlement.none;

      bool? allowed;
      await tester.pumpWidget(
        _wrap(
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

      expect(fake.fetchCount, greaterThanOrEqualTo(1));
      expect(sub.isPro, isFalse);
      expect(find.byType(PaywallSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(PaywallSheet))).pop(false);
      await tester.pumpAndSettle();
      expect(allowed, isFalse);
    },
  );

  test('suscripción con expires_at pasado retira Pro localmente', () {
    final sub = SubscriptionService.instance;
    sub.syncFromProfile(accesoIlimitado: false, email: 'u@example.com');
    sub.applyEntitlement(
      _proEntitlement(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        status: 'expired',
      ),
    );
    expect(sub.entitlement.isPro, isTrue);
    expect(sub.isPro, isFalse);
  });

  test('reanudación / refreshEntitlementBestEffort actualiza entitlement',
      () async {
    final sub = SubscriptionService.instance;
    sub.syncFromProfile(accesoIlimitado: false, email: 'u@example.com');
    sub.applyEntitlement(_proEntitlement());
    expect(sub.isPro, isTrue);

    fake.next = BillingEntitlement.none;
    await sub.refreshEntitlementBestEffort();

    expect(fake.fetchCount, 1);
    expect(sub.isPro, isFalse);
  });

  test(
    'error de red: no borra entitlement; expires_at pasado sigue bloqueando',
    () async {
      final sub = SubscriptionService.instance;
      sub.syncFromProfile(accesoIlimitado: false, email: 'u@example.com');
      final past = DateTime.now().toUtc().subtract(const Duration(days: 1));
      sub.applyEntitlement(_proEntitlement(expiresAt: past, status: 'active'));
      expect(sub.isPro, isFalse);

      fake.throwOnFetch = Exception('network_down');
      await sub.refreshEntitlementBestEffort();

      expect(sub.entitlement.isPro, isTrue);
      expect(sub.entitlement.expiresAt, past);
      expect(sub.isPro, isFalse);
    },
  );

  test(
    'error de red: entitlement vigente no se revoca permanentemente',
    () async {
      final sub = SubscriptionService.instance;
      sub.syncFromProfile(accesoIlimitado: false, email: 'u@example.com');
      final future = DateTime.now().toUtc().add(const Duration(days: 7));
      sub.applyEntitlement(_proEntitlement(expiresAt: future));
      expect(sub.isPro, isTrue);

      fake.throwOnFetch = Exception('network_down');
      await expectLater(sub.refreshEntitlement(), throwsA(isA<Exception>()));
      expect(sub.isPro, isTrue);
      expect(sub.entitlement.expiresAt, future);

      await sub.refreshEntitlementBestEffort();
      expect(sub.isPro, isTrue);
    },
  );

  test('refresh concurrente coalescido: un solo fetch', () async {
    final sub = SubscriptionService.instance;
    fake.next = _proEntitlement();
    final a = sub.refreshEntitlement();
    final b = sub.refreshEntitlement();
    await Future.wait([a, b]);
    expect(fake.fetchCount, 1);
  });
}
