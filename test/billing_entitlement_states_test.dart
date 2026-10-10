import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:matchpay/core/billing/billing_entitlement.dart';
import 'package:matchpay/core/billing/play_purchase_validation_result.dart';
import 'package:matchpay/core/subscription_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  BillingEntitlement entitlement({
    required bool isPro,
    required String source,
    String? status,
  }) {
    return BillingEntitlement(
      isPro: isPro,
      source: source,
      status: status,
      productId: isPro ? 'kloovi_pro_monthly' : null,
      expiresAt: isPro
          ? DateTime.now().toUtc().add(const Duration(days: 30))
          : null,
      isTrial: status == 'trial',
      isFounder: false,
      autoRenewing: isPro,
      lastVerifiedAt: DateTime.now().toUtc(),
    );
  }

  test('gratuito sin suscripción: sin Pro', () async {
    final sub = SubscriptionService.forTesting();
    await sub.clearCommercialEntitlement();
    sub.syncFromProfile(accesoIlimitado: false, email: 'free@example.com');
    expect(sub.isPro, isFalse);
    expect(sub.can(ProFeature.createMatch), isFalse);
  });

  test('suscripción activa verificada: Pro', () {
    final sub = SubscriptionService.forTesting();
    sub.syncFromProfile(accesoIlimitado: false, email: 'a@b.com');
    sub.applyEntitlement(
      entitlement(isPro: true, source: 'subscription', status: 'active'),
    );
    expect(sub.isPro, isTrue);
    expect(sub.can(ProFeature.createMatch), isTrue);
  });

  test('pending / on_hold / expired / revoked: sin Pro comercial', () {
    final sub = SubscriptionService.forTesting();
    sub.syncFromProfile(accesoIlimitado: false, email: 'a@b.com');

    for (final status in ['pending', 'on_hold', 'expired', 'revoked']) {
      sub.applyEntitlement(
        entitlement(isPro: false, source: 'none', status: status),
      );
      expect(sub.isPro, isFalse, reason: status);
      expect(sub.can(ProFeature.createMatch), isFalse, reason: status);
    }
  });

  test('grace con is_pro del backend: Pro', () {
    final sub = SubscriptionService.forTesting();
    sub.syncFromProfile(accesoIlimitado: false, email: 'a@b.com');
    sub.applyEntitlement(
      entitlement(isPro: true, source: 'subscription', status: 'grace'),
    );
    expect(sub.entitlement.status, 'grace');
    expect(sub.isPro, isTrue);
  });

  test('respuesta inválida / failure: no concede Pro', () {
    final failure = PlayPurchaseValidationResult.failure(
      errorCode: PlayPurchaseValidationErrorCode.serverError,
      httpStatus: 500,
    );
    expect(failure.ok, isFalse);
    expect(failure.shouldCompletePurchase, isFalse);
    expect(failure.entitlement, isNull);
  });

  test('acceso administrativo legítimo: Pro sin compra', () {
    final sub = SubscriptionService.forTesting();
    sub.applyEntitlement(BillingEntitlement.none);
    sub.syncFromProfile(accesoIlimitado: true, email: 'staff@example.com');
    expect(sub.hasUnlimitedAccess, isTrue);
    expect(sub.isPro, isTrue);
    expect(sub.can(ProFeature.createMatch), isTrue);
  });

  test('BillingEntitlement.fromJson respeta is_pro del servidor', () {
    final pro = BillingEntitlement.fromJson({
      'is_pro': true,
      'source': 'subscription',
      'status': 'canceled',
      'product_id': 'kloovi_pro_monthly',
      'expires_at': '2099-01-01T00:00:00.000Z',
      'is_trial': false,
      'is_founder': false,
      'auto_renewing': false,
      'last_verified_at': '2026-10-09T00:00:00.000Z',
    });
    expect(pro.isPro, isTrue);
    expect(pro.status, 'canceled');

    final none = BillingEntitlement.fromJson({
      'is_pro': false,
      'source': 'none',
      'status': 'pending',
    });
    expect(none.isPro, isFalse);
    expect(none.status, 'pending');
  });

  test('expires_at pasado: no concede Pro aunque isPro en memoria sea true', () {
    final sub = SubscriptionService.forTesting();
    sub.syncFromProfile(accesoIlimitado: false, email: 'a@b.com');
    sub.applyEntitlement(
      BillingEntitlement(
        isPro: true,
        source: 'subscription',
        status: 'expired',
        productId: 'kloovi_pro_monthly',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        isTrial: false,
        isFounder: false,
        autoRenewing: false,
        lastVerifiedAt: DateTime.now().toUtc(),
      ),
    );
    expect(sub.entitlement.isPro, isTrue);
    expect(sub.isPro, isFalse);
    expect(sub.can(ProFeature.createMatch), isFalse);
  });
}
