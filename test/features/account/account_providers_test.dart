import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
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

  test('la rilettura non passa dallo spinner: restano i contatti di prima',
      () async {
    final api = FakeAccountApi()
      ..contactsResult =
          const AccountContacts(discordAvailable: true, discordName: 'garg');
    final c = container(api);
    await c.read(accountContactsProvider.future);

    api.contactsGate = Completer<void>();
    api.contactsResult = const AccountContacts(discordAvailable: true);
    final reload = c.read(accountContactsProvider.notifier).reload();
    await pumpEventQueue();

    // La lettura è in sospeso, ma lo stato non è tornato in caricamento.
    final during = c.read(accountContactsProvider);
    expect(during, isA<AsyncData<AccountContacts?>>());
    expect(during.isLoading, isFalse);
    expect(during.value!.discordName, 'garg');

    api.contactsGate!.complete();
    await reload;
    expect(c.read(accountContactsProvider).value!.discordName, isNull);
  });

  test('la funzione account si accende con il provider aperto', () async {
    final api = FakeAccountApi()
      ..contactsResult =
          const AccountContacts(discordAvailable: true, discordName: 'garg');
    final c = ProviderContainer.test(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        accountApiProvider.overrideWithValue(api),
        socialAvailabilityProvider
            .overrideWith(() => FakeSocialAvailability(SocialFeatures.none)),
      ],
      retry: (_, _) => null,
    );
    c.listen(accountContactsProvider, (_, _) {});

    expect(await c.read(accountContactsProvider.future), isNull);
    expect(api.contactsCalls, 0);

    (c.read(socialAvailabilityProvider.notifier) as FakeSocialAvailability)
        .set(const SocialFeatures(account: true));
    await pumpEventQueue();

    final contacts = await c.read(accountContactsProvider.future);
    expect(contacts!.contactOf(AccountChannel.discord), 'garg');
    expect(api.contactsCalls, 1);
  });

  test('un cambio di utente a metà rilettura: restano i contatti del nuovo',
      () async {
    final api = FakeAccountApi()
      ..contactsResult =
          const AccountContacts(discordAvailable: true, discordName: 'garg');
    final session = FakeSessionController(const SessionSignedIn(testUser));
    final c = ProviderContainer.test(
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        accountApiProvider.overrideWithValue(api),
        accountAvailableProvider.overrideWithValue(true),
      ],
      retry: (_, _) => null,
    );
    c.listen(accountContactsProvider, (_, _) {});
    // I contatti dell'utente A.
    await c.read(accountContactsProvider.future);

    // La rilettura di A parte e resta in sospeso (ogni lettura ha il suo
    // gate: la risposta si legge quando il gate si completa).
    final readingA = Completer<void>();
    api.contactsGate = readingA;
    final reload = c.read(accountContactsProvider.notifier).reload();
    await pumpEventQueue();

    // Cambia l'utente: il `build` di B legge anche lui, dietro un altro gate.
    final readingB = Completer<void>();
    api.contactsGate = readingB;
    session.set(const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
    await pumpEventQueue();
    expect(api.contactsCalls, 3);

    // Risponde prima B...
    api.contactsResult =
        const AccountContacts(emailAvailable: true, email: 'luigi@example.com');
    readingB.complete();
    await c.read(accountContactsProvider.future);

    // ...poi arriva la risposta tardiva di A, che non va scritta.
    api.contactsResult =
        const AccountContacts(discordAvailable: true, discordName: 'garg');
    readingA.complete();
    await reload;

    final contacts = c.read(accountContactsProvider).value!;
    expect(contacts.email, 'luigi@example.com');
    expect(contacts.discordName, isNull);
  });

  test('accountAvailableProvider segue la funzione account', () {
    final c = ProviderContainer.test(
      overrides: [
        socialAvailabilityProvider.overrideWith(
            () => FakeSocialAvailability(const SocialFeatures(account: true))),
      ],
      retry: (_, _) => null,
    );
    expect(c.read(accountAvailableProvider), isTrue);
  });
}
