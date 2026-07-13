import 'package:flutter_test/flutter_test.dart';

import 'package:matchpay/core/subscription_service.dart';

void main() {
  test('founder email tiene acceso ilimitado sin flag Pro', () {
    final sub = SubscriptionService.instance;
    sub.syncFromProfile(
      accesoIlimitado: false,
      email: 'fparram13@gmail.com',
    );
    expect(sub.hasUnlimitedAccess, isTrue);
    expect(sub.isPro, isTrue);
    expect(sub.can(ProFeature.createMatch), isTrue);

    sub.clearProfileEntitlements();
    expect(sub.hasUnlimitedAccess, isFalse);
  });

  test('acceso_ilimitado en perfil desbloquea sin email founder', () {
    final sub = SubscriptionService.instance;
    sub.syncFromProfile(
      accesoIlimitado: true,
      email: 'otro@example.com',
    );
    expect(sub.hasUnlimitedAccess, isTrue);
    expect(sub.isPro, isTrue);

    sub.clearProfileEntitlements();
  });
}
