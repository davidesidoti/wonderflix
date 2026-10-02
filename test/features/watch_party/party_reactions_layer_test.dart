import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_reactions_layer.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  group('reactionFrame (spec E §10.4)', () {
    const ms = Duration(milliseconds: 1);

    test('animazioni complete: scala, salita, dissolvenza', () {
      final start = reactionFrame(Duration.zero, reduced: false);
      expect(start.scale, PartyReactionsLayer.popFrom);
      expect(start.lift, 0);
      expect(start.opacity, 1);
      final popped =
          reactionFrame(PartyReactionsLayer.popDuration, reduced: false);
      expect(popped.scale, closeTo(1, 1e-9));
      final fadeStart = PartyReactionsLayer.flightDuration -
          PartyReactionsLayer.fadeOutDuration;
      expect(reactionFrame(fadeStart, reduced: false).opacity, 1);
      expect(reactionFrame(fadeStart + PartyReactionsLayer.fadeOutDuration ~/ 2,
                  reduced: false)
              .opacity,
          closeTo(0.5, 0.01));
      final end =
          reactionFrame(PartyReactionsLayer.flightDuration, reduced: false);
      expect(end.lift, PartyReactionsLayer.rise);
      expect(end.opacity, 0);
      expect(reactionFrame(ms * 1200, reduced: false).lift,
          greaterThan(PartyReactionsLayer.rise / 2),
          reason: 'la salita rallenta: a metà tempo è oltre metà strada');
    });

    test('animazioni ridotte: niente scala né salita', () {
      expect(
          PartyReactionsLayer.reducedLifetime,
          PartyReactionsLayer.reducedFadeIn +
              PartyReactionsLayer.reducedHold +
              PartyReactionsLayer.reducedFadeOut);
      expect(reactionFrame(Duration.zero, reduced: true).opacity, 0);
      final shown =
          reactionFrame(PartyReactionsLayer.reducedFadeIn, reduced: true);
      expect(shown.opacity, 1);
      expect(shown.scale, 1);
      expect(shown.lift, 0);
      expect(
          reactionFrame(
                  PartyReactionsLayer.reducedFadeIn +
                      PartyReactionsLayer.reducedHold,
                  reduced: true)
              .opacity,
          1);
      expect(
          reactionFrame(PartyReactionsLayer.reducedLifetime, reduced: true)
              .opacity,
          0);
    });

    test('scostamento: da 0 a 80 px, sempre uguale per lo stesso id', () {
      for (final id in ['r1', 'local-7', 'a8f3c2e19b', '']) {
        final jitter = reactionJitter(id);
        expect(jitter, inInclusiveRange(0, PartyReactionsLayer.maxJitter));
        expect(reactionJitter(id), jitter);
      }
      expect(reactionJitter('r1'), isNot(reactionJitter('r2')));
    });
  });

  group('livello (spec E §10.4)', () {
    late FakeSyncPlayApi api;
    late FakePartyChannelApi channelApi;
    late StreamController<ServerEvent> events;

    setUp(() {
      api = FakeSyncPlayApi();
      channelApi = FakePartyChannelApi()..install();
      events = StreamController<ServerEvent>.broadcast();
      api.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(GroupJoined(
              'g1', testGroup(participants: ['Mario', 'Luigi']))));
        }
      };
    });

    tearDown(() => events.close());

    ProviderContainer container(WidgetTester tester) => ProviderScope
        .containerOf(tester.element(find.byType(PartyReactionsLayer)));

    Future<void> pumpLayer(WidgetTester tester,
        {MotionLevel motion = MotionLevel.reduced}) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Stack(children: [
            Positioned(
              right: PartyReactionsLayer.right,
              bottom: PartyReactionsLayer.bottom,
              child: PartyReactionsLayer(),
            ),
          ]),
        ),
        motion: motion,
        overrides: [
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          partyChannelApiProvider.overrideWithValue(channelApi),
        ],
      );
      unawaited(container(tester)
          .read(watchPartySessionProvider.notifier)
          .join('g1'));
      await tester.pump();
      await tester.pump();
      expect(container(tester).read(partyChannelProvider).active, isTrue);
    }

    Future<void> leave(WidgetTester tester) async {
      await container(tester).read(watchPartySessionProvider.notifier).leave();
      await tester.pump(PartyReactionsLayer.flightDuration);
    }

    Future<void> receive(WidgetTester tester, String reaction,
        {required String id}) async {
      events.add(PartyChannelReceived(
          partyPayload({'Type': 'Reaction', 'Reaction': reaction}, id: id)));
      await tester.pump();
      await tester.pump();
    }

    Finder inLayer(Finder finder) =>
        find.descendant(of: find.byType(PartyReactionsLayer), matching: finder);

    testWidgets('reazione degli altri: emoji e nome; poi sparisce',
        (tester) async {
      await pumpLayer(tester);
      await receive(tester, 'clap', id: 'r1');
      expect(inLayer(find.text('👏')), findsOneWidget);
      expect(inLayer(find.text('Luigi')), findsOneWidget);
      await tester.pump(PartyReactionsLayer.reducedLifetime);
      await tester.pump();
      expect(inLayer(find.text('👏')), findsNothing);
      await leave(tester);
    });

    testWidgets('la nostra: subito, con "Tu"', (tester) async {
      await pumpLayer(tester);
      container(tester)
          .read(partyChannelProvider.notifier)
          .sendReaction(PartyReaction.joy);
      await tester.pump();
      await tester.pump();
      expect(inLayer(find.text('😂')), findsOneWidget);
      expect(inLayer(find.text('Tu')), findsOneWidget);
      await leave(tester);
    });

    testWidgets('al massimo 12 in volo: le altre si scartano', (tester) async {
      await pumpLayer(tester);
      for (var i = 0; i < PartyReactionsLayer.maxInFlight + 2; i++) {
        events.add(PartyChannelReceived(partyPayload(
            {'Type': 'Reaction', 'Reaction': 'wow'},
            id: 'r$i')));
      }
      await tester.pump();
      await tester.pump();
      expect(inLayer(find.text('😮')),
          findsNWidgets(PartyReactionsLayer.maxInFlight));
      await leave(tester);
    });

    testWidgets('animazioni complete: sale', (tester) async {
      await pumpLayer(tester, motion: MotionLevel.full);
      await receive(tester, 'joy', id: 'r1');
      final start = tester.getTopLeft(inLayer(find.text('😂'))).dy;
      await tester.pump(const Duration(seconds: 1));
      final later = tester.getTopLeft(inLayer(find.text('😂'))).dy;
      expect(later, lessThan(start - 50));
      await leave(tester);
    });

    testWidgets('non prende i clic', (tester) async {
      await pumpLayer(tester);
      expect(
          find.descendant(
              of: find.byType(PartyReactionsLayer),
              matching: find.byType(IgnorePointer)),
          findsWidgets);
      await leave(tester);
    });
  });
}
