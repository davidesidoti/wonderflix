import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  ProviderContainer container(
    FakeAccountApi api, {
    bool available = true,
    SessionState session = const SessionSignedIn(testUser),
  }) {
    final c = ProviderContainer.test(
      overrides: [
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(session)),
        accountApiProvider.overrideWithValue(api),
        accountAvailableProvider.overrideWithValue(available),
      ],
      retry: (_, _) => null,
    );
    c.listen(accountContactsProvider, (_, _) {});
    return c;
  }

  test('senza la funzione account: niente contatti e nessuna chiamata',
      () async {
    final api = FakeAccountApi();
    final c = container(api, available: false);
    expect(await c.read(accountContactsProvider.future), isNull);
    expect(api.contactsCalls, 0);
  });

  test('senza un utente aperto: nessuna chiamata', () async {
    final api = FakeAccountApi();
    final c = container(api, session: const SessionSignedOut());
    expect(await c.read(accountContactsProvider.future), isNull);
    expect(api.contactsCalls, 0);
  });

  test('legge i contatti; replace li sostituisce, reload li rilegge',
      () async {
    final api = FakeAccountApi()
      ..contactsResult =
          const AccountContacts(discordAvailable: true, discordName: 'garg');
    final c = container(api);

    final contacts = await c.read(accountContactsProvider.future);
    expect(contacts!.contactOf(AccountChannel.discord), 'garg');

    c.read(accountContactsProvider.notifier).replace(
        const AccountContacts(emailAvailable: true, email: 'a@example.com'));
    expect(c.read(accountContactsProvider).value!.email, 'a@example.com');

    api.contactsResult = const AccountContacts(discordAvailable: true);
    await c.read(accountContactsProvider.notifier).reload();
    expect(c.read(accountContactsProvider).value!.discordName, isNull);
    expect(api.contactsCalls, 2);
  });

  test('un errore della lettura resta nello stato', () async {
    final api = FakeAccountApi()..contactsFailure = AccountFailure.network;
    final c = container(api);
    await expectLater(c.read(accountContactsProvider.future),
        throwsA(isA<AccountException>()));
    expect(c.read(accountContactsProvider).hasError, isTrue);
  });

  test('accountAvailableProvider segue la funzione account', () {
    final c = ProviderContainer.test(overrides: [
      socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(const SocialFeatures(account: true))),
    ]);
    expect(c.read(accountAvailableProvider), isTrue);
  });
}
