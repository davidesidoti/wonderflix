import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../support/avatar_fakes.dart';
import '../support/fake_session_controller.dart';
import '../support/profile_fakes.dart';
import '../support/pump_app.dart';
import '../support/social_fakes.dart';
import '../support/test_data.dart';
import '../support/watch_party_fakes.dart';

/// Un watch party in corso: l'uscita lo chiude subito.
class _InParty extends WatchPartySession {
  int leaveCalls = 0;

  @override
  WatchPartyState build() =>
      const WatchPartyState(phase: WatchPartyPhase.inGroup);

  @override
  Future<void> leave() async {
    leaveCalls++;
    state = const WatchPartyState();
  }
}

void main() {
  testWidgets('mostra utente e Home, e fa il logout dal menu', (tester) async {
    final fake = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );

    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Film'), findsOneWidget);
    expect(find.text('Serie'), findsOneWidget);
    expect(find.text('La mia lista'), findsOneWidget);
    expect(find.text('Cerca'), findsOneWidget);
    expect(find.text('Richieste'), findsNothing);

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();

    expect(fake.logoutCalls, 1);
  });

  testWidgets('voce "Richieste" solo con la funzione delle richieste',
      (tester) async {
    await pumpApp(
      tester,
      const AppShell(location: '/requests', child: SizedBox()),
      overrides: [
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        socialAvailabilityProvider.overrideWith(
            () => FakeSocialAvailability(const SocialFeatures(requests: true))),
      ],
    );

    expect(find.text('Richieste'), findsOneWidget);
  });

  testWidgets('menu: Cambia profilo e Aggiungi profilo', (tester) async {
    final fake = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Aggiungi profilo'), findsOneWidget);
    await tester.tap(find.text('Cambia profilo'));
    await tester.pumpAndSettle();
    expect(fake.switchCalls, 1);
  });

  testWidgets('menu: Aggiungi profilo apre l\'accesso', (tester) async {
    final fake = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi profilo'));
    await tester.pumpAndSettle();
    expect(fake.addProfileCalls, 1);
    expect(fake.switchCalls, 0);
  });

  testWidgets('menu in un party: "Cambia profilo" chiede conferma',
      (tester) async {
    final fake = FakeSessionController(const SessionSignedIn(testUser));
    final party = _InParty();
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        watchPartySessionProvider.overrideWith(() => party),
      ],
    );

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambia profilo'));
    await tester.pumpAndSettle();
    // Il menu si è chiuso: la conferma si apre lo stesso.
    expect(find.text('Uscirai dal watch party.'), findsOneWidget);
    expect(fake.switchCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Cambia profilo'));
    await tester.pumpAndSettle();
    expect(party.leaveCalls, 1);
    expect(fake.switchCalls, 1);
  });

  testWidgets('menu con 5 profili: niente "Aggiungi profilo"', (tester) async {
    var book = const ProfileBook();
    for (var i = 1; i <= ProfileBook.maxProfiles; i++) {
      book = book.upsert(testProfile(userId: 'u$i'));
    }
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        profilesProvider.overrideWith(() =>
            FixedProfiles(ProfilesState(book: book, activeUserId: 'u1'))),
      ],
    );

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Cambia profilo'), findsOneWidget);
    expect(find.text('Aggiungi profilo'), findsNothing);
  });

  testWidgets('l\'avatar del menu è l\'immagine dell\'utente', (tester) async {
    final urls = <String>[];
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            const SessionSignedIn(
                JellyfinUser(id: 'u1', name: 'Mario', primaryImageTag: 't1')))),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        captureImageUrls(urls),
      ],
    );

    expect(urls, contains('https://media.example.com/UserImage?userId=u1&tag=t1'));
  });
}
