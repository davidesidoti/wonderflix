import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/match/match_entry.dart';
import 'package:wonderflix/features/friends/friends_controller.dart';
import 'package:wonderflix/ui/skeletons.dart';
import 'package:wonderflix/ui/user_avatar.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/core/social/activity_models.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/watch_party/current_party.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/friends/friend_search.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/avatar_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

/// Il titolo di sezione (12 px, 600): "Offline" è anche la scritta sotto il
/// nome.
Finder sectionTitle(String text) => find.byWidgetPredicate((w) =>
    w is Text &&
    w.data == text &&
    w.style?.fontSize == 12 &&
    w.style?.fontWeight == FontWeight.w600);

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<void> pumpPanel(WidgetTester tester,
      {List<Override> overrides = const [],
      SocialFeatures features = const SocialFeatures(friends: true)}) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
        ),
      ),
      overrides: [
        ...socialTestOverrides(api, features: features),
        ...overrides
      ],
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
    expect(sectionTitle('Online'), findsOneWidget);
    expect(sectionTitle('Offline'), findsOneWidget);
    expect(find.textContaining('Da rispondere'), findsNothing);
    expect(find.textContaining('Richieste inviate'), findsNothing);
  });

  testWidgets('righe come la bozza: nome in 600, avatar offline a 0,6',
      (tester) async {
    api.snapshot = FriendsSnapshot(friends: [
      testFriend('u2', 'Luigi', online: true),
      testFriend('u5', 'Zelda'),
    ]);
    await pumpPanel(tester);

    for (final name in ['Luigi', 'Zelda']) {
      expect(tester.widget<Text>(find.text(name)).style?.fontWeight,
          FontWeight.w600);
    }
    double avatarOpacity(String userId) => tester
        .widget<Opacity>(find
            .ancestor(
                of: find.byWidgetPredicate(
                    (w) => w is UserAvatar && w.userId == userId),
                matching: find.byType(Opacity))
            .first)
        .opacity;
    expect(avatarOpacity('u2'), 1);
    expect(avatarOpacity('u5'), 0.6);
  });

  testWidgets('un amico con un\'immagine la mostra, cercato per id; il '
      'pallino resta', (tester) async {
    final urls = <String>[];
    api.snapshot =
        FriendsSnapshot(friends: [testFriend('u2', 'Luigi', online: true)]);
    await pumpPanel(tester, overrides: [
      captureImageUrls(urls),
      // Il nome non corrisponde: l'amico si cerca per id.
      avatarsFor(const [
        UserAvatarInfo(userId: 'u2', name: 'Luigi Verdi', imageTag: 't2'),
      ]),
    ]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();

    expect(urls.toSet(), {'https://media.example.com/UserImage?userId=u2&tag=t2'});
    expect(find.byKey(const Key('online-dot')), findsOneWidget);
  });

  testWidgets('richieste e ricerca: l\'immagine cercata per id',
      (tester) async {
    final urls = <String>[];
    api.snapshot = FriendsSnapshot(
      incoming: [testPerson('u3', 'Peach')],
      outgoing: [testPerson('u4', 'Daisy')],
    );
    api.searchResults['lu'] = [testSearchResult('u6', 'Lucia')];
    await pumpPanel(tester, overrides: [
      captureImageUrls(urls),
      avatarsFor(const [
        UserAvatarInfo(userId: 'u3', name: 'x3', imageTag: 't3'),
        UserAvatarInfo(userId: 'u4', name: 'x4', imageTag: 't4'),
        UserAvatarInfo(userId: 'u6', name: 'x6', imageTag: 't6'),
      ]),
    ]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();
    expect(urls.toSet(), {
      'https://media.example.com/UserImage?userId=u3&tag=t3',
    }, reason: 'Richieste inviate è chiusa');
    await tester.tap(find.byKey(const Key('friends-outgoing-toggle')));
    await tester.pump();
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();
    expect(urls, contains('https://media.example.com/UserImage?userId=u4&tag=t4'));

    await tester.enterText(find.byKey(const Key('friends-search')), 'lu');
    await tester.pump(FriendSearch.debounce);
    await tester.pump();
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();
    expect(urls, contains('https://media.example.com/UserImage?userId=u6&tag=t6'));
  });

  testWidgets('nessun amico: invito a cercare', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Non hai ancora amici. Cerca qualcuno per nome qui sopra.'),
        findsOneWidget);
  });

  testWidgets('richieste: accetta, rifiuta, annulla', (tester) async {
    api.snapshot = FriendsSnapshot(
      incoming: [testPerson('u3', 'Peach')],
      outgoing: [testPerson('u4', 'Daisy')],
    );
    await pumpPanel(tester);
    expect(find.text('Da rispondere (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('friends-outgoing-toggle')));
    await tester.pump();
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
    expect(inRow('u6', 'In attesa'), findsOneWidget);
    expect(inRow('u6', 'Annulla'), findsOneWidget);
    expect(inRow('u7', 'Accetta'), findsOneWidget);
    expect(inRow('u7', 'Rifiuta'), findsOneWidget);
    expect(inRow('u8', 'Amici'), findsOneWidget);
    expect(find.descendant(
            of: find.byKey(const ValueKey('search-u8')),
            matching: find.byIcon(LucideIcons.check)),
        findsOneWidget);
    expect(sectionTitle('Online'), findsNothing, reason: 'liste nascoste');

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
    expect(
        find.text(
            'Nessuno si chiama così. Controlla il nome o chiedi il suo codice.'),
        findsOneWidget);
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
    expect(
        find.text(
            'Non riesco a leggere gli amici. Controlla la connessione e riprova.'),
        findsOneWidget);

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

  testWidgets('testa con gli online e sezioni nell\'ordine', (t) async {
    api.snapshot = FriendsSnapshot(
        friends: [
          testFriend('u2', 'sara', online: true),
          testFriend('u3', 'CaptainC'),
        ],
        incoming: [testPerson('u4', 'luca88')],
        outgoing: [testPerson('u5', 'marta')]);
    await pumpPanel(t);
    expect(find.text('1 online'), findsOneWidget);
    final order = [
      'Da rispondere (1)',
      'Online',
      'Offline',
      'Richieste inviate (1)'
    ].map((s) => t.getTopLeft(sectionTitle(s)).dy).toList();
    expect(order, [...order]..sort());
    expect(find.text('marta'), findsNothing, reason: 'Richieste inviate è chiusa');
    await t.tap(find.byKey(const Key('friends-outgoing-toggle')));
    await t.pump();
    expect(find.text('marta'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
  });

  testWidgets('Da rispondere ha lo stesso numero del badge', (t) async {
    api.snapshot = FriendsSnapshot(incoming: [
      testPerson('u4', 'luca88'),
      testPerson('u6', 'pia'),
    ], outgoing: [
      testPerson('u5', 'marta'),
      testPerson('u7', 'ugo'),
      testPerson('u8', 'eva'),
    ]);
    await pumpPanel(t);
    final container =
        ProviderScope.containerOf(t.element(find.byType(FriendsPanel)));
    expect(container.read(friendsControllerProvider).incomingCount, 2);
    expect(find.text('Da rispondere (2)'), findsOneWidget);
    expect(find.text('Richieste inviate (3)'), findsOneWidget);
  });

  testWidgets('offline: la scritta sotto il nome; avatar da 32', (t) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u3', 'CaptainC')]);
    await pumpPanel(t);
    final row = find
        .ancestor(of: find.text('CaptainC'), matching: find.byType(Row))
        .first;
    expect(find.descendant(of: row, matching: find.text('Offline')),
        findsOneWidget);
    expect(t.getSize(find.byType(UserAvatar).first), const Size(32, 32));
  });

  testWidgets('⋯: Invita a un Match e Rimuovi in rosso, niente Invita a '
      'guardare', (t) async {
    api.snapshot =
        FriendsSnapshot(friends: [testFriend('u2', 'sara', online: true)]);
    await pumpPanel(t, overrides: [matchEntryProvider.overrideWithValue(true)]);
    await t.tap(find.byTooltip('Altre azioni'));
    await t.pumpAndSettle();
    expect(find.text('Invita a un Match'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(t.widget<Text>(find.text('Rimuovi dagli amici')).style?.color,
        WfColors.error);
    expect(find.text('Invita a guardare'), findsNothing);
  });

  testWidgets('⋯ senza Match: solo Rimuovi', (t) async {
    api.snapshot =
        FriendsSnapshot(friends: [testFriend('u2', 'sara', online: true)]);
    await pumpPanel(t);
    await t.tap(find.byTooltip('Altre azioni'));
    await t.pumpAndSettle();
    expect(find.text('Invita a un Match'), findsNothing);
    expect(find.byType(PopupMenuDivider), findsNothing);
    expect(find.text('Rimuovi dagli amici'), findsOneWidget);
  });

  testWidgets('piede: Ho un codice e Apri un Match in fondo, non in cima',
      (t) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u3', 'CaptainC')]);
    await pumpPanel(t,
        features: const SocialFeatures(friends: true, parties: true),
        overrides: [matchEntryProvider.overrideWithValue(true)]);
    final name = t.getTopLeft(find.text('CaptainC')).dy;
    expect(t.getTopLeft(find.text('Apri un Match')).dy, greaterThan(name));
    expect(t.getTopLeft(find.text('Ho un codice')).dy, greaterThan(name));
  });

  testWidgets('ricerca: rotellina e riga grigia mentre cerca, poi le parole '
      'giuste', (t) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u3', 'CaptainC')]);
    api.searchResults['ca'] = [
      testSearchResult('u4', 'Carla', FriendRelation.incoming),
      testSearchResult('u5', 'Carlo', FriendRelation.outgoing),
      testSearchResult('u3', 'CaptainC', FriendRelation.friend),
    ];
    await pumpPanel(t,
        features: const SocialFeatures(friends: true, parties: true),
        overrides: [matchEntryProvider.overrideWithValue(true)]);
    await t.enterText(find.byKey(const Key('friends-search')), 'ca');
    await t.pump();
    expect(
        find.descendant(
            of: find.byKey(const Key('friends-search')),
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(find.byType(PanelRowsSkeleton), findsOneWidget);
    expect(find.text('Ho un codice'), findsNothing);
    expect(find.text('Apri un Match'), findsNothing);

    await t.pump(FriendSearch.debounce);
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(PanelRowsSkeleton), findsNothing);
    Finder inRow(String userId, String text) => find.descendant(
        of: find.byKey(ValueKey('search-$userId')), matching: find.text(text));
    expect(inRow('u4', 'Accetta'), findsOneWidget);
    expect(inRow('u4', 'Rifiuta'), findsOneWidget);
    expect(inRow('u5', 'In attesa'), findsOneWidget);
    expect(inRow('u5', 'Annulla'), findsOneWidget);
    expect(inRow('u3', 'Amici'), findsOneWidget);

    await t.tap(inRow('u4', 'Rifiuta'));
    await t.pump();
    expect(api.calls, contains('decline u4'));
  });

  testWidgets('nome lungo, testo a 1,5, larga 380: niente overflow',
      (t) async {
    api.snapshot = const FriendsSnapshot(friends: [
      FriendEntry(
        userId: 'u2',
        name: 'Bartolomeo Bartolomeo Bartolomeo Bartolomeo Bartolo',
        online: true,
        party: FriendParty(groupId: 'g1', title: 'Il Signore degli Anelli'),
      ),
    ], incoming: [
      PersonEntry(
          userId: 'u4',
          name: 'Massimiliano Massimiliano Massimiliano Massimilia'),
    ]);
    await pumpApp(
      t,
      const MediaQuery(
        data: MediaQueryData(
            size: Size(380, 800), textScaler: TextScaler.linear(1.5)),
        child: Scaffold(
          body: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
        ),
      ),
      surfaceSize: const Size(380, 800),
      overrides: [
        ...socialTestOverrides(api,
            features: const SocialFeatures(friends: true, parties: true)),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        matchEntryProvider.overrideWithValue(true),
      ],
    );
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('friend-join-u2')), findsOneWidget);
    expect(t.getTopRight(find.byTooltip('Altre azioni')).dx,
        lessThanOrEqualTo(380));
    expect(t.getTopRight(find.text('Unisciti')).dx, lessThanOrEqualTo(380));
    expect(t.getTopRight(find.text('Accetta')).dx, lessThanOrEqualTo(380));
    expect(t.getTopRight(find.text('Rifiuta')).dx, lessThanOrEqualTo(380));
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

    late FakeLibraryApi library;

    /// Il pannello con la libreria finta: "Guarda insieme" apre il titolo.
    Future<void> pumpWatchPanel(WidgetTester tester,
        {SyncPlayAccess? access}) async {
      library = FakeLibraryApi()
        ..itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
      syncPlay.onCall = (call) {
        if (call.startsWith('create') || call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
        }
      };
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
              features: const SocialFeatures(
                  friends: true, parties: true, friendsActivity: true)),
          syncPlayApiProvider.overrideWithValue(syncPlay),
          partyChannelApiProvider
              .overrideWithValue(FakePartyChannelApi()..install()),
          libraryApiProvider.overrideWithValue(library),
          if (access != null) syncPlayAccessProvider.overrideWithValue(access),
        ],
      );
      await tester.pump();
    }

    const dune = FriendNowPlaying(itemId: 'm1', title: 'Dune');

    testWidgets('Sta guardando: il testo e Guarda insieme', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
        testFriend('u3', 'Peach', online: true),
      ]);
      await pumpWatchPanel(tester);
      expect(find.text('Sta guardando Dune'), findsOneWidget);
      expect(find.byKey(const Key('friend-watch-u2')), findsOneWidget);
      expect(find.byKey(const Key('friend-watch-u3')), findsNothing);
    });

    testWidgets('Guarda insieme: posizione, party privato senza menu e invito',
        (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      api.nowPlayingById['u2'] =
          const FriendPosition(itemId: 'm1', position: Duration(minutes: 42));
      await pumpWatchPanel(tester);
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      expect(api.calls, containsAllInOrder(['nowPlaying u2', 'register g1 Private', 'invite g1 u2']));
      expect(syncPlay.queues.single.start, const Duration(minutes: 42),
          reason: 'la posizione dell\'amico arriva a SyncPlay');
      expect(find.text('Pubblico'), findsNothing, reason: 'niente menu delle modalità');
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      expect(container.read(currentPartyProvider)?.mode, PartyMode.private);
      await leaveParty(tester);
    });

    testWidgets('Guarda insieme quando l\'amico ha smesso: avviso e niente party',
        (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      await pumpWatchPanel(tester);
      final friendsBefore = api.calls.where((c) => c == 'friends').length;
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      expect(find.text('Non sta più guardando'), findsOneWidget);
      expect(syncPlay.calls.where((c) => c.startsWith('create')), isEmpty);
      expect(api.calls.where((c) => c == 'friends').length, friendsBefore + 1,
          reason: 'l\'elenco si rilegge');
    });

    testWidgets('errore di rete su friendNowPlaying: avviso generico, niente party',
        (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      await pumpWatchPanel(tester);
      api.nextFailure = SocialFailure.network;
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      expect(find.text('Non è stato possibile avviare il watch party.'),
          findsOneWidget);
      expect(syncPlay.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('senza permesso di creare: il testo c\'è, il tasto no',
        (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      await pumpWatchPanel(tester, access: SyncPlayAccess.joinOnly);
      expect(find.text('Sta guardando Dune'), findsOneWidget);
      expect(find.byKey(const Key('friend-watch-u2')), findsNothing);
    });

    testWidgets('invito lento: il party è già registrato, poi segue l invito',
        (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      api.nowPlayingById['u2'] =
          const FriendPosition(itemId: 'm1', position: Duration.zero);
      final gate = api.inviteGate = Completer<void>();
      await pumpWatchPanel(tester);
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);
      expect(container.read(currentPartyProvider)?.mode, PartyMode.private);
      expect(api.calls, contains('invite g1 u2'));
      // Oltre il timeout della registrazione il party regge ancora.
      await tester.pump(
          WatchPartySession.registrationTimeout + const Duration(seconds: 1));
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);
      expect(container.read(currentPartyProvider), isNotNull);
      expect(container.read(currentPartyProvider)!.invited, isEmpty);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Invito non inviato'), findsNothing);
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);
      expect(container.read(currentPartyProvider)!.invited, {'u2'});
      await leaveParty(tester);
    });

    testWidgets('invito non riuscito: il party resta e lo dice', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      api.nowPlayingById['u2'] =
          const FriendPosition(itemId: 'm1', position: Duration.zero);
      api.inviteFailure = SocialFailure.rateLimited;
      await pumpWatchPanel(tester);
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      expect(find.text('Invito non inviato'), findsOneWidget);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);
      await leaveParty(tester);
    });

    testWidgets('Guarda insieme spento mentre parte', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      final gate = api.nowPlayingGate = Completer<void>();
      await pumpWatchPanel(tester);
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('friend-watch-u2')), warnIfMissed: false);
      await tester.pump();
      expect(api.calls.where((c) => c == 'nowPlaying u2'), hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('già in un gruppo: niente Guarda insieme', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      await pumpWatchPanel(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      await container.read(watchPartySessionProvider.notifier).join('g1');
      await tester.pumpAndSettle();
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);
      expect(find.byKey(const Key('friend-watch-u2')), findsNothing);
      expect(find.text('Sta guardando Dune'), findsOneWidget);
      await leaveParty(tester);
    });
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
