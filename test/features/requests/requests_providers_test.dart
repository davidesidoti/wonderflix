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

  test('richieste sparite: solo con le funzioni note e senza `requests`', () {
    final availability = FakeSocialAvailability(SocialFeatures.unknown);
    final container = ProviderContainer.test(overrides: [
      socialAvailabilityProvider.overrideWith(() => availability),
    ]);
    // Funzioni non ancora note: non si sa nulla, la pagina non va via.
    expect(container.read(requestsGoneProvider), isFalse);

    availability.set(const SocialFeatures(inbox: true));
    expect(container.read(requestsGoneProvider), isTrue);

    availability.set(const SocialFeatures(inbox: true, requests: true));
    expect(container.read(requestsGoneProvider), isFalse);

    // Un nuovo accesso le rende di nuovo non note: nemmeno qui va via.
    availability.set(SocialFeatures.unknown);
    expect(container.read(requestsGoneProvider), isFalse);
  });

  test('Me: dal plugin solo con la funzione', () async {
    final api = FakeRequestsApi()
      ..meValue =
          const RequestsMe(canRequest: true, canManage: true, hasAccount: true);
    final off = ProviderContainer.test(
        overrides: requestsTestOverrides(api, available: false));
    // Provider autoDispose: senza un ascoltatore si butterebbe via a metà.
    off.listen(requestsMeProvider, (_, _) {});
    expect((await off.read(requestsMeProvider.future)).canRequest, isFalse);
    expect(api.calls, isEmpty);

    final on = ProviderContainer.test(overrides: requestsTestOverrides(api));
    on.listen(requestsMeProvider, (_, _) {});
    expect((await on.read(requestsMeProvider.future)).canManage, isTrue);
    expect(api.calls, ['me']);
  });
}
