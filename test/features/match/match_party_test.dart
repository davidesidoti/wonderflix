import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeMatchApi match;
  late FakeSocialApi social;
  late FakeSyncPlayApi syncPlay;
  late FakeLibraryApi library;
  late FakePartyChannelApi channelApi;
  late StreamController<ServerEvent> events;
  bool? result;

  setUp(() {
    match = FakeMatchApi();
    social = FakeSocialApi();
    syncPlay = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi()..install();
    events = StreamController<ServerEvent>.broadcast();
    library = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', name: 'Dune')
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Heat');
    syncPlay.onCall = (call) {
      if (call.startsWith('create') || call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    match.rooms['r1'] = testMatchState(
        phase: MatchPhase.voting, rev: 2, matches: ['m1', 'm2']);
    result = null;
  });

  tearDown(() => events.close());

  Future<ProviderContainer> pumpButton(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async => result = await startMatchParty(context, ref),
            child: const Text('via'),
          ),
        ),
      ),
      overrides: [
        ...socialTestOverrides(social,
            events: events.stream,
            features: const SocialFeatures(
                friends: true, parties: true, match: true)),
        matchApiProvider.overrideWithValue(match),
        libraryApiProvider.overrideWithValue(library),
        syncPlayApiProvider.overrideWithValue(syncPlay),
        partyChannelApiProvider.overrideWithValue(channelApi),
      ],
    );
    final container =
        ProviderScope.containerOf(tester.element(find.text('via')));
    container.listen(matchRoomProvider, (_, _) {});
    await container.read(matchRoomProvider.notifier).open();
    return container;
  }

  Future<void> leave(WidgetTester tester, ProviderContainer container) async {
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets(
      'startMatchPartyStartsAPrivatePartyWithTheMatchesAndTellsThePlugin',
      (tester) async {
    final container = await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(syncPlay.queues.single.itemIds, ['m1', 'm2']);
    expect(social.calls, contains('register g1 Private'));
    expect(match.calls, contains('party r1 g1'));
    await leave(tester, container);
  });

  testWidgets('aFailingMatchPartyCallKeepsTheParty', (tester) async {
    match.failures['party r1 g1'] = const MatchException(MatchFailure.network);
    final container = await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(container.read(watchPartySessionProvider).inGroup, isTrue);
    await leave(tester, container);
  });

  testWidgets('startMatchPartyWithoutTitlesFails', (tester) async {
    library.itemsById.clear();
    await pumpButton(tester);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('Non riuscito, riprova'), findsOneWidget);
    expect(syncPlay.calls.where((c) => c.startsWith('create')), isEmpty);
  });
}
