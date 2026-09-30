import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_invites.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late FakeWatchPartyInvites invites;
  final dune = testGroup(name: 'Davide · Dune', participants: ['Davide']);

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    invites = FakeWatchPartyInvites(dune);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', dune)));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> pumpCard(WidgetTester tester,
          {MotionLevel motion = MotionLevel.reduced}) =>
      pumpApp(
        tester,
        const Scaffold(
            body: Align(
                alignment: Alignment.topRight, child: WatchPartyInviteCard())),
        motion: motion,
        overrides: [
          watchPartyInvitesProvider.overrideWith(() => invites),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
      );

  testWidgets('chi l\'ha avviato e cosa si guarda; "Unisciti" entra',
      (tester) async {
    await pumpCard(tester);
    expect(find.text('Davide ha avviato un watch party'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(api.calls, ['join g1']);
    expect(invites.dismissed, 1);
    expect(find.byKey(const Key('watch-party-invite')), findsNothing);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('la X chiude l\'invito', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pump();
    expect(invites.dismissed, 1);
    // La card sparisce in dissolvenza (`fast` con le animazioni ridotte):
    // non c'è più a dissolvenza finita.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('watch-party-invite')), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('completa: l\'invito entra da destra e sparisce in dissolvenza',
      (tester) async {
    invites = FakeWatchPartyInvites();
    await pumpCard(tester, motion: MotionLevel.full);
    final card = find.byKey(const Key('watch-party-invite'));
    expect(card, findsNothing);

    invites.show(dune);
    await tester.pump();
    Offset slide() => tester
        .widget<SlideTransition>(
            find.ancestor(of: card, matching: find.byType(SlideTransition)).first)
        .position
        .value;
    expect(slide().dx, greaterThan(0));
    await tester.pumpAndSettle();
    expect(slide(), Offset.zero);

    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pump();
    expect(card, findsOneWidget, reason: 'sta ancora sfumando');
    await tester.pumpAndSettle();
    expect(card, findsNothing);
  });
}
