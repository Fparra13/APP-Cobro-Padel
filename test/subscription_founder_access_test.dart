import 'package:flutter_test/flutter_test.dart';

import 'package:matchpay/core/subscription_service.dart';

void main() {
  test('email founder local NO otorga Pro (autoridad = backend/staff)', () {
    final sub = SubscriptionService.instance;
    sub.syncFromProfile(
      accesoIlimitado: false,
      email: 'fparram13@gmail.com',
    );
    expect(sub.hasUnlimitedAccess, isFalse);
    expect(sub.isPro, isFalse);
    expect(sub.can(ProFeature.createMatch), isFalse);

    sub.clearProfileEntitlements();
  });

  test('acceso_ilimitado en perfil desbloquea Pro (bypass admin)', () {
    final sub = SubscriptionService.instance;
    sub.syncFromProfile(
      accesoIlimitado: true,
      email: 'otro@example.com',
    );
    expect(sub.hasUnlimitedAccess, isTrue);
    expect(sub.isPro, isTrue);
    expect(sub.can(ProFeature.createMatch), isTrue);

    sub.clearProfileEntitlements();
  });
}
