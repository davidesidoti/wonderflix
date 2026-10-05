import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';

void main() {
  test('la funzione segue Info del plugin', () {
    final availability =
        FakeSocialAvailability(const SocialFeatures(inbox: true));
    final container = ProviderContainer.test(overrides: [
      socialAvailabilityProvider.overrideWith(() => availability),
    ]);
    expect(container.read(requestsAvailableProvider), isFalse);
    availability.set(const SocialFeatures(inbox: true, requests: true));
    expect(container.read(requestsAvailableProvider), isTrue);
  });

  test('Me: dal plugin solo con la funzione', () async {
    final api = FakeRequestsApi()
      ..meValue =
          const RequestsMe(canRequest: true, canManage: true, hasAccount: true);
    final off = ProviderContainer.test(
        overrides: requestsTestOverrides(api, available: false));
    expect((await off.read(requestsMeProvider.future)).canRequest, isFalse);
    expect(api.calls, isEmpty);

    final on = ProviderContainer.test(overrides: requestsTestOverrides(api));
    expect((await on.read(requestsMeProvider.future)).canManage, isTrue);
    expect(api.calls, ['me']);
  });
}
