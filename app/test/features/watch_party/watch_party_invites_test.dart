import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_invites.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;
  final g1 = testGroup(id: 'g1', name: 'Luigi · Arrival');
  final g2 = testGroup(id: 'g2', name: 'Davide · Dune');
  final g3 = testGroup(id: 'g3', name: 'Peach · Up');

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', g1)));
      }
    };
  });

  tearDown(() => events.close());

  /// Dentro la zona finta: container e inviti attivi.
  /// Con le funzioni del plugin [features]: di default nessuna, come la 0.5.1.
  void mount(
      {JellyfinUser user = testUser,
      SocialFeatures features = SocialFeatures.none}) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(SessionSignedIn(user))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
      socialApiProvider.overrideWithValue(FakeSocialApi()),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ]);
    container.listen(watchPartyInvitesProvider, (_, _) {});
  }

  /// Come [mount], con la funzione `parties` del plugin.
  void mountWithParties() => mount(
      features: const SocialFeatures(friends: true, parties: true));

  void groups(FakeAsync async, List<GroupInfo> list) {
    (container.read(watchPartyDirectoryProvider.notifier)
            as FakeWatchPartyDirectory)
        .set(list);
    async.flushMicrotasks();
  }

  GroupInfo? invite() => container.read(watchPartyInvitesProvider)?.group;

  test('i gruppi della prima lettura non sono inviti; uno nuovo sì, per 10 s',
      () {
    fakeAsync((async) {
      mount();
      groups(async, [g1]);
      expect(invite(), isNull);
      groups(async, [g1, g2, g3]);
      expect(invite()?.id, 'g3', reason: 'il più recente');
      async.elapse(const Duration(seconds: 9));
      expect(invite()?.id, 'g3');
      async.elapse(const Duration(seconds: 1));
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('dentro un gruppo nessun invito', () {
    fakeAsync((async) {
      mount();
      groups(async, const []);
      unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
      async.flushMicrotasks();
      groups(async, [g1, g2]);
      expect(invite(), isNull);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      container.dispose();
    });
  });

  test('con il player aperto nessun invito; aprirlo chiude l\'invito', () {
    fakeAsync((async) {
      mount();
      groups(async, const []);
      groups(async, [g2]);
      expect(invite()?.id, 'g2');
      container.read(playerActiveProvider.notifier).enter();
      async.flushMicrotasks();
      expect(invite(), isNull);
      groups(async, [g2, g3]);
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('senza il permesso di entrare nessun invito', () {
    fakeAsync((async) {
      mount(
          user: const JellyfinUser(
              id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none));
      groups(async, const []);
      groups(async, [g2]);
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('dismiss chiude l\'invito', () {
    fakeAsync((async) {
      mount();
      groups(async, const []);
      groups(async, [g2]);
      container.read(watchPartyInvitesProvider.notifier).dismiss();
      expect(invite(), isNull);
      async.elapse(const Duration(seconds: 20));
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('un gruppo in cui siamo entrati non è un invito, anche dopo l\'uscita',
      () {
    fakeAsync((async) {
      mount();
      groups(async, const []);
      unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
      async.flushMicrotasks();
      // Nessuna lettura dell'elenco mentre eravamo nel gruppo (es. player
      // aperto); gli altri restano nel gruppo dopo la nostra uscita.
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      groups(async, [g1]);
      expect(invite(), isNull);
      groups(async, [g1, g2]);
      expect(invite()?.id, 'g2');
      container.dispose();
    });
  });

  test('un gruppo creato da noi non è un invito, anche dopo l\'uscita', () {
    fakeAsync((async) {
      api.onCall = (call) {
        if (call.startsWith('create')) {
          events.add(SyncPlayGroupUpdated(GroupJoined('g2', g2)));
        }
      };
      mount();
      groups(async, const []);
      unawaited(container
          .read(watchPartySessionProvider.notifier)
          .create(testItem(id: 'm1', name: 'Dune')));
      async.flushMicrotasks();
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      groups(async, [g2]);
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('entrando in un gruppo l\'invito si chiude', () {
    fakeAsync((async) {
      // Il server non conferma: si resta in "ingresso".
      api.onCall = null;
      mount();
      groups(async, const []);
      groups(async, [g2]);
      expect(invite()?.id, 'g2');
      unawaited(container
          .read(watchPartySessionProvider.notifier)
          .join('g3')
          .catchError((Object _) {}));
      async.flushMicrotasks();
      expect(container.read(watchPartySessionProvider).phase,
          WatchPartyPhase.joining);
      expect(invite(), isNull);
      async.elapse(WatchPartySession.joinTimeout);
      container.dispose();
    });
  });

  test('con la funzione parties: schede dagli avvisi del plugin', () {
    fakeAsync((async) {
      mountWithParties();
      async.flushMicrotasks();
      events.add(partyStartedReceived('g7', 'Luigi · Arrival'));
      async.flushMicrotasks();
      expect(invite()?.id, 'g7');
      expect(container.read(watchPartyInvitesProvider)!.invitedBy, isNull);
      final directory = container.read(watchPartyDirectoryProvider.notifier)
          as FakeWatchPartyDirectory;
      expect(directory.refreshCalls, greaterThan(0),
          reason: 'il party nuovo entra subito nell\'elenco');

      events.add(partyInviteReceived('g8', 'Peach · Up', 'Peach'));
      async.flushMicrotasks();
      expect(container.read(watchPartyInvitesProvider)!.invitedBy, 'Peach');
      async.elapse(WatchPartyInvites.showFor);
      expect(invite(), isNull);
    });
  });

  test('con la funzione parties un gruppo nuovo nell\'elenco non è un invito',
      () {
    fakeAsync((async) {
      mountWithParties();
      async.flushMicrotasks();
      groups(async, [g1]);
      groups(async, [g1, g2]);
      expect(invite(), isNull);
    });
  });

  test('funzioni non ancora note: nessuna scheda, poi vale la logica giusta',
      () {
    fakeAsync((async) {
      mount(features: SocialFeatures.unknown);
      async.flushMicrotasks();
      groups(async, const []);
      groups(async, [g2]);
      groups(async, [g2, g3]);
      expect(invite(), isNull);
      events.add(partyStartedReceived('g7', 'Luigi · Arrival'));
      async.flushMicrotasks();
      expect(invite(), isNull);

      // Note le funzioni (senza parties) le schede tornano dall'elenco.
      (container.read(socialAvailabilityProvider.notifier)
              as FakeSocialAvailability)
          .set(SocialFeatures.none);
      async.flushMicrotasks();
      // Leggere fa ricostruire il provider con la logica dell'elenco.
      expect(invite(), isNull);
      groups(async, [g2]);
      expect(invite(), isNull, reason: 'la prima lettura è la base');
      groups(async, [g2, g3]);
      expect(invite()?.id, 'g3');
      container.dispose();
    });
  });

  test('con la funzione parties: niente scheda per un gruppo visitato o '
      'dentro un gruppo', () {
    fakeAsync((async) {
      mountWithParties();
      async.flushMicrotasks();
      unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
      async.flushMicrotasks();
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);

      events.add(partyStartedReceived('g5', 'Peach · Up'));
      async.flushMicrotasks();
      expect(invite(), isNull, reason: 'dentro un gruppo');

      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      events.add(partyStartedReceived('g1', 'Mario · Dune'));
      events.add(partyInviteReceived('g1', 'Mario · Dune', 'Mario'));
      async.flushMicrotasks();
      expect(invite(), isNull, reason: 'gruppo già visitato');

      events.add(partyStartedReceived('g5', 'Peach · Up'));
      async.flushMicrotasks();
      expect(invite()?.id, 'g5', reason: 'un party nuovo sì');
      container.dispose();
    });
  });

  test('nomi dal nome del gruppo', () {
    expect(partyNameParts(g2), (host: 'Davide', title: 'Dune'));
    expect(
        partyNameParts(
            testGroup(name: 'Davide · Star Wars · Episodio IV')),
        (host: 'Davide', title: 'Star Wars · Episodio IV'));
    expect(
        partyNameParts(testGroup(name: 'Serata', participants: ['Luigi'])),
        (host: 'Luigi', title: 'Serata'));
    expect(partyNameParts(testGroup(name: 'Serata', participants: const [])),
        (host: 'Serata', title: 'Serata'));
  });
}
