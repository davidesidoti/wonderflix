import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/current_party.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/watch_party_actions.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeLibraryApi library;
  late FakePartyChannelApi channelApi;
  late StreamController<ServerEvent> events;
  final pilot = testItem(
      id: 'e4',
      name: 'Pilot',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'Breaking Bad');

  setUp(() {
    api = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi()..install();
    events = StreamController<ServerEvent>.broadcast();
    library = FakeLibraryApi()
      ..seriesEpisodes['s1'] = [
        pilot,
        testItem(id: 'e5', kind: ItemKind.episode, seriesId: 's1'),
      ];
    api.onCall = (call) {
      if (call.startsWith('create') || call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> pumpButton(WidgetTester tester) => pumpApp(
        tester,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => unawaited(startWatchParty(context, ref, pilot,
                  start: const Duration(minutes: 3))),
              child: const Text('via'),
            ),
          ),
        ),
        overrides: [
          libraryApiProvider.overrideWithValue(library),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          partyChannelApiProvider.overrideWithValue(channelApi),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
      );

  late FakeSocialApi social;

  Future<void> pumpModeButton(WidgetTester tester, PartyMode mode) async {
    social = FakeSocialApi();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => unawaited(
                startWatchParty(context, ref, pilot, mode: mode)),
            child: const Text('via'),
          ),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider.overrideWithValue(channelApi),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.text('via')));

  /// Esce dal gruppo: ferma l'orologio (i suoi timer non devono restare).
  Future<void> leave(WidgetTester tester) async {
    await container(tester).read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('fuori da un gruppo: crea il gruppo con la coda della serie',
      (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['create Mario · Breaking Bad', 'queue e4,e5']);
    expect(api.queues.single.start, const Duration(minutes: 3));
    await leave(tester);
  });

  testWidgets('dentro un gruppo: solo la nuova coda', (tester) async {
    await pumpButton(tester);
    unawaited(container(tester).read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['join g1', 'queue e4,e5']);
    await leave(tester);
  });

  testWidgets('dentro un gruppo: la nuova coda si annuncia (spec E §7.4)',
      (tester) async {
    await pumpButton(tester);
    // Come nell'app, dove lo tiene vivo `watchPartyRoutingProvider`.
    container(tester).listen(partyChannelProvider, (_, _) {});
    unawaited(container(tester)
        .read(watchPartySessionProvider.notifier)
        .join('g1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect([for (final event in channelApi.sent) event.toJson()], [
      {'Type': 'Action', 'Action': 'NewQueue'},
    ]);
    await leave(tester);
  });

  testWidgets('coda non disponibile: avviso, nessun gruppo', (tester) async {
    library.error = const ServerUnreachableException();
    await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(find.text('Non è stato possibile avviare il watch party.'),
        findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('con una modalità: registra il party prima della coda',
      (tester) async {
    await pumpModeButton(tester, PartyMode.friends);
    var queuesAtRegister = -1;
    social.onRegister = () =>
        queuesAtRegister = api.calls.where((c) => c.startsWith('queue')).length;
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(social.calls, contains('register g1 Friends'));
    expect(queuesAtRegister, 0, reason: 'la coda arriva dopo la registrazione');
    expect(api.calls, ['create Mario · Breaking Bad', 'queue e4,e5']);
    await leave(tester);
  });

  testWidgets('privato: il codice resta nel party corrente, da annunciare',
      (tester) async {
    await pumpModeButton(tester, PartyMode.private);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    final current = container(tester).read(currentPartyProvider);
    expect(current?.groupId, 'g1');
    expect(current?.mode, PartyMode.private);
    expect(current?.code, 'K7PQ2X');
    expect(current?.announceCode, isTrue);
    await leave(tester);
  });

  testWidgets('registrazione finita dopo l\'uscita dal gruppo: niente coda',
      (tester) async {
    await pumpModeButton(tester, PartyMode.private);
    final gate = social.registerGate = Completer<void>();
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(social.calls, ['register g1 Private']);
    expect(container(tester).read(watchPartySessionProvider).inGroup, isTrue);

    // Il server ci toglie dal gruppo mentre la registrazione è in corso.
    events.add(SyncPlayGroupUpdated(const GroupLeft('g1')));
    await tester.pump();
    expect(container(tester).read(watchPartySessionProvider).inGroup, isFalse);

    gate.complete();
    await tester.pumpAndSettle();
    expect(api.calls, ['create Mario · Breaking Bad'],
        reason: 'niente coda per un gruppo che non è più il nostro');
    expect(container(tester).read(currentPartyProvider), isNull);
    expect(find.text('Questo watch party non esiste più.'), findsOneWidget);
  });

  testWidgets('registrazione fallita: esce dal gruppo e lo dice',
      (tester) async {
    await pumpModeButton(tester, PartyMode.private);
    social.registerFailure = SocialFailure.network;
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['create Mario · Breaking Bad', 'leave']);
    expect(find.text('Non è stato possibile creare il watch party'),
        findsOneWidget);
    expect(container(tester).read(watchPartySessionProvider).inGroup, isFalse);
  });
}
