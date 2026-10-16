import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/features/match/match_invites.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_invites.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeMatchApi match;
  late StreamController<ServerEvent> events;

  setUp(() {
    match = FakeMatchApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  tearDown(() => events.close());

  List<Override> overrides() => [
        ...socialTestOverrides(FakeSocialApi(),
            events: events.stream,
            features: const SocialFeatures(friends: true, parties: true, match: true)),
        matchApiProvider.overrideWithValue(match),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      ];

  test('un invito resta 10 s; non con il player aperto né dentro una sala', () {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: overrides(), retry: (_, _) => null);
      addTearDown(container.dispose);
      container.listen(matchInvitesProvider, (_, _) {});
      async.flushMicrotasks();

      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider)?.roomId, 'r2');
      async.elapse(MatchInvites.showFor);
      expect(container.read(matchInvitesProvider), isNull);

      container.read(playerActiveProvider.notifier).enter();
      async.flushMicrotasks();
      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider), isNull);
      container.read(playerActiveProvider.notifier).leave();
      async.flushMicrotasks();

      unawaited(container.read(matchRoomProvider.notifier).open());
      async.flushMicrotasks();
      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider), isNull);
    });
  });

  test('un invito alla volta: il match chiude il party e viceversa', () {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: overrides(), retry: (_, _) => null);
      addTearDown(container.dispose);
      container.listen(matchInvitesProvider, (_, _) {});
      container.listen(watchPartyInvitesProvider, (_, _) {});
      async.flushMicrotasks();

      events.add(partyInviteReceived('g1', 'Peach · Up', 'Peach'));
      async.flushMicrotasks();
      expect(container.read(watchPartyInvitesProvider), isNotNull);

      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider)?.roomId, 'r2');
      expect(container.read(watchPartyInvitesProvider), isNull);

      events.add(partyInviteReceived('g2', 'Toad · Alien', 'Toad'));
      async.flushMicrotasks();
      expect(container.read(watchPartyInvitesProvider), isNotNull);
      expect(container.read(matchInvitesProvider), isNull);
    });
  });

  testWidgets('la carta: chi invita, X chiude, Unisciti entra e apre la sala',
      (tester) async {
    match.rooms['r2'] = testMatchState(
        roomId: 'r2', creatorId: 'u2', creatorName: 'Luigi');
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
              body: Align(
                  alignment: Alignment.topRight, child: MatchInviteCard()))),
      GoRoute(
          path: '/match/:id',
          builder: (_, state) => Text('pagina ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router, overrides: overrides());

    events.add(matchInviteReceived('r2', 'Luigi'));
    await tester.pumpAndSettle();
    expect(find.text('Luigi ti invita a un match'), findsOneWidget);

    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(match.calls, ['join r2']);
    expect(find.text('pagina r2'), findsOneWidget);
  });
}
