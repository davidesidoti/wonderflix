import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/friends/friend_search.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<void> pumpPanel(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
        ),
      ),
      overrides: socialTestOverrides(api),
    );
    // Il primo caricamento parte da un microtask.
    await tester.pump();
  }

  testWidgets('amici: prima gli online, poi in ordine; pallino verde',
      (tester) async {
    api.snapshot = FriendsSnapshot(friends: [
      testFriend('u5', 'Zelda'),
      testFriend('u2', 'Luigi', online: true),
      testFriend('u4', 'daisy'),
    ]);
    await pumpPanel(tester);

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('Luigi'), lessThan(y('daisy')));
    expect(y('daisy'), lessThan(y('Zelda')));
    expect(find.byKey(const Key('online-dot')), findsOneWidget);
    expect(find.text('AMICI'), findsOneWidget);
    expect(find.textContaining('RICHIESTE'), findsNothing);
  });

  testWidgets('nessun amico: invito a cercare', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Nessun amico ancora. Cerca qualcuno per nome qui sopra.'),
        findsOneWidget);
  });

  testWidgets('richieste: accetta, rifiuta, annulla', (tester) async {
    api.snapshot = FriendsSnapshot(
      incoming: [testPerson('u3', 'Peach')],
      outgoing: [testPerson('u4', 'Daisy')],
    );
    await pumpPanel(tester);
    expect(find.text('RICHIESTE (2)'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);

    await tester.tap(find.text('Accetta'));
    await tester.pump();
    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    await tester.tap(find.text('Annulla'));
    await tester.pump();

    expect(api.calls.where((call) => call != 'friends'),
        ['accept u3', 'decline u3', 'cancel u4']);
  });

  testWidgets('ricerca: l\'azione giusta per ogni risultato, poi rilegge',
      (tester) async {
    api.searchResults['lu'] = [
      testSearchResult('u2', 'Luigi'),
      testSearchResult('u6', 'Lucia', FriendRelation.outgoing),
      testSearchResult('u7', 'Ludovico', FriendRelation.incoming),
      testSearchResult('u8', 'Lucky', FriendRelation.friend),
    ];
    await pumpPanel(tester);

    await tester.enterText(find.byKey(const Key('friends-search')), 'lu');
    await tester.pump(FriendSearch.debounce);
    await tester.pump();

    Finder inRow(String userId, String text) => find.descendant(
        of: find.byKey(ValueKey('search-$userId')), matching: find.text(text));
    expect(inRow('u2', 'Aggiungi'), findsOneWidget);
    expect(inRow('u6', 'Inviata'), findsOneWidget);
    expect(inRow('u6', 'Annulla'), findsOneWidget);
    expect(inRow('u7', 'Accetta'), findsOneWidget);
    expect(inRow('u8', 'Amici'), findsOneWidget);
    expect(find.text('AMICI'), findsNothing, reason: 'liste nascoste');

    await tester.tap(inRow('u2', 'Aggiungi'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, containsAllInOrder(['search lu', 'request u2', 'search lu']));

    // Una sola ripetizione (il limite del plugin è 30 ricerche al minuto):
    // la ripete la lista amici riletta dopo l'azione, non l'azione stessa.
    await tester.pumpAndSettle();
    expect(api.calls.where((call) => call == 'search lu'), hasLength(2));
  });

  testWidgets('ricerca senza risultati', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byKey(const Key('friends-search')), 'zz');
    await tester.pump(FriendSearch.debounce);
    await tester.pump();
    expect(find.text('Nessun utente trovato'), findsOneWidget);
  });

  testWidgets('rimozione: conferma per 4 s', (tester) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await pumpPanel(tester);

    Future<void> askRemoval() async {
      await tester.tap(find.byTooltip('Altre azioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi dagli amici'));
      await tester.pumpAndSettle();
    }

    await askRemoval();
    expect(find.byKey(const Key('friend-remove-confirm')), findsOneWidget);
    await tester.pump(FriendsPanel.removeConfirmFor);
    expect(find.byKey(const Key('friend-remove-confirm')), findsNothing);
    expect(api.calls, isNot(contains('remove u2')));

    await askRemoval();
    await tester.tap(find.byKey(const Key('friend-remove-confirm')));
    await tester.pump();
    expect(api.calls, contains('remove u2'));
  });

  testWidgets('caricamento fallito: Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpPanel(tester);
    await tester.pump();
    expect(find.text('Amici non disponibili'), findsOneWidget);

    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Luigi'), findsOneWidget);
  });

  testWidgets('azione rifiutata: lo dice', (tester) async {
    api.snapshot = FriendsSnapshot(incoming: [testPerson('u3', 'Peach')]);
    await pumpPanel(tester);
    api.nextFailure = SocialFailure.rateLimited;
    await tester.tap(find.text('Accetta'));
    await tester.pumpAndSettle();
    expect(find.text('Troppe richieste, riprova più tardi'), findsOneWidget);
  });

  group('party', () {
    late FakeSyncPlayApi syncPlay;
    late StreamController<ServerEvent> events;

    setUp(() {
      syncPlay = FakeSyncPlayApi();
      events = StreamController<ServerEvent>.broadcast();
      syncPlay.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
        }
      };
    });

    tearDown(() => events.close());

    Future<void> pumpPartyPanel(WidgetTester tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
          ),
        ),
        overrides: [
          ...socialTestOverrides(api,
              events: events.stream,
              features: const SocialFeatures(friends: true, parties: true)),
          syncPlayApiProvider.overrideWithValue(syncPlay),
          partyChannelApiProvider
              .overrideWithValue(FakePartyChannelApi()..install()),
        ],
      );
      await tester.pump();
    }

    Future<void> leaveParty(WidgetTester tester) async {
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      await container.read(watchPartySessionProvider.notifier).leave();
      await tester.pump();
    }

    testWidgets('"Ho un codice": il trattino da sé, poi entra e il pannello '
        'si chiude', (tester) async {
      api.codes['K7PQ2X'] = 'g1';
      await pumpPartyPanel(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      container.listen(shellPanelProvider, (_, _) {});
      container.read(shellPanelProvider.notifier).open(ShellPanel.friends);
      await tester.pump();
      await tester.tap(find.text('Ho un codice'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('party-code-field')), 'k7pq2x');
      await tester.pump();
      expect(find.text('K7P-Q2X'), findsOneWidget);
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('code K7PQ2X'));
      expect(syncPlay.calls, contains('join g1'));
      expect(container.read(shellPanelProvider), ShellPanel.none);
      await leaveParty(tester);
    });

    testWidgets('codice sbagliato o troppi tentativi: lo dice',
        (tester) async {
      await pumpPartyPanel(tester);
      await tester.tap(find.text('Ho un codice'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('party-code-field')), 'ZZZZZZ');
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(find.text('Codice non valido o party finito'), findsOneWidget);

      api.joinFailure = SocialFailure.rateLimited;
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(find.text('Troppi tentativi, riprova tra un minuto'),
          findsOneWidget);

      // Rete o plugin sparito: non è colpa del codice.
      api.joinFailure = SocialFailure.network;
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(find.text('Operazione non riuscita'), findsOneWidget);
    });

    testWidgets('un codice a metà resta durante una ricerca', (tester) async {
      await pumpPartyPanel(tester);
      await tester.tap(find.text('Ho un codice'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('party-code-field')), 'K7P');
      await tester.enterText(find.byKey(const Key('friends-search')), 'lu');
      await tester.pump(FriendSearch.debounce);
      await tester.pump();
      expect(find.byKey(const Key('party-code-field')), findsNothing,
          reason: 'i risultati prendono il suo posto');
      await tester.enterText(find.byKey(const Key('friends-search')), '');
      await tester.pump();
      expect(find.text('K7P'), findsOneWidget);
    });

    testWidgets('"Conferma rimozione": Unisciti si nasconde', (tester) async {
      api.snapshot = const FriendsSnapshot(friends: [
        FriendEntry(
          userId: 'u2',
          name: 'Luigi',
          online: true,
          party: FriendParty(groupId: 'g1', title: 'Dune'),
        ),
      ]);
      await pumpPartyPanel(tester);
      await tester.tap(find.byTooltip('Altre azioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi dagli amici'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('friend-remove-confirm')), findsOneWidget);
      expect(find.byKey(const Key('friend-join-u2')), findsNothing);
      await tester.pump(FriendsPanel.removeConfirmFor);
      await tester.pump();
      expect(find.byKey(const Key('friend-join-u2')), findsOneWidget);
    });

    testWidgets('Unisciti nascosto anche con l\'id del gruppo scritto in un '
        'altro modo', (tester) async {
      syncPlay.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(
              GroupJoined('0a1b2c3d', testGroup(id: '0a1b2c3d'))));
        }
      };
      api.snapshot = const FriendsSnapshot(friends: [
        FriendEntry(
          userId: 'u2',
          name: 'Luigi',
          online: true,
          party: FriendParty(groupId: '0A1B-2C3D', title: 'Dune'),
        ),
      ]);
      await pumpPartyPanel(tester);
      await tester.tap(find.byKey(const Key('friend-join-u2')));
      await tester.pumpAndSettle();
      expect(syncPlay.calls, contains('join 0A1B-2C3D'));
      expect(find.byKey(const Key('friend-join-u2')), findsNothing);
      await leaveParty(tester);
    });

    testWidgets('codice incompleto: lo dice senza chiedere al plugin',
        (tester) async {
      await pumpPartyPanel(tester);
      await tester.tap(find.text('Ho un codice'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('party-code-field')), 'K7P');
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(find.text('Codice non valido o party finito'), findsOneWidget);
      expect(api.calls, isNot(contains(startsWith('code'))));
    });

    testWidgets('amico in un party visibile: "Nel watch party" e Unisciti',
        (tester) async {
      api.snapshot = const FriendsSnapshot(friends: [
        FriendEntry(
          userId: 'u2',
          name: 'Luigi',
          online: true,
          party: FriendParty(groupId: 'g1', title: 'Dune'),
        ),
      ]);
      await pumpPartyPanel(tester);
      expect(find.text('Nel watch party: Dune'), findsOneWidget);
      await tester.tap(find.byKey(const Key('friend-join-u2')));
      await tester.pumpAndSettle();
      expect(syncPlay.calls, contains('join g1'));
      expect(find.byKey(const Key('friend-join-u2')), findsNothing,
          reason: 'già nel gruppo');
      await leaveParty(tester);
    });

    group('Unisciti cliccato due volte di fila', () {
      // Il gruppo conferma l'ingresso solo quando lo dice il test.
      setUp(() => syncPlay.onCall = null);

      Finder joinButton() => find.descendant(
          of: find.byKey(const Key('friend-join-u2')),
          matching: find.byType(TextButton));

      /// Pannello aperto con Luigi nel party g1; Unisciti cliccato due volte.
      Future<ProviderContainer> doubleTapJoin(WidgetTester tester) async {
        api.snapshot = const FriendsSnapshot(friends: [
          FriendEntry(
            userId: 'u2',
            name: 'Luigi',
            online: true,
            party: FriendParty(groupId: 'g1', title: 'Dune'),
          ),
        ]);
        await pumpPartyPanel(tester);
        final container = ProviderScope.containerOf(
            tester.element(find.byType(FriendsPanel)));
        container.listen(shellPanelProvider, (_, _) {});
        container.read(shellPanelProvider.notifier).open(ShellPanel.friends);
        await tester.pump();
        await tester.tap(joinButton());
        await tester.pump();
        await tester.tap(joinButton());
        await tester.pump();
        return container;
      }

      testWidgets('un solo ingresso; il pannello si chiude quando riesce',
          (tester) async {
        final container = await doubleTapJoin(tester);
        expect(syncPlay.calls.where((call) => call == 'join g1'), hasLength(1));
        expect(tester.widget<TextButton>(joinButton()).onPressed, isNull,
            reason: 'Unisciti spento finché l\'ingresso è in corso');
        expect(container.read(shellPanelProvider), ShellPanel.friends);

        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
        await tester.pumpAndSettle();
        expect(container.read(shellPanelProvider), ShellPanel.none);
        await leaveParty(tester);
      });

      testWidgets('ingresso fallito: il pannello resta aperto con l\'errore',
          (tester) async {
        final container = await doubleTapJoin(tester);
        await tester.pump(WatchPartySession.joinTimeout);
        await tester.pump();
        expect(find.text('Non è stato possibile entrare nel watch party.'),
            findsOneWidget);
        expect(container.read(shellPanelProvider), ShellPanel.friends);
        expect(tester.widget<TextButton>(joinButton()).onPressed, isNotNull,
            reason: 'si può riprovare');
      });
    });

    testWidgets('senza la funzione parties: niente "Ho un codice"',
        (tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
          ),
        ),
        overrides: socialTestOverrides(api),
      );
      await tester.pump();
      expect(find.text('Ho un codice'), findsNothing);
    });
  });
}
