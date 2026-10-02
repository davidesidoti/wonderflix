import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_chat_bubble.dart';
import 'package:wonderflix/features/watch_party/party_chat_layer.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakePartyChannelApi channelApi;
  late StreamController<ServerEvent> events;
  late ValueNotifier<bool> open;

  setUp(() {
    api = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi()..install();
    events = StreamController<ServerEvent>.broadcast();
    open = ValueNotifier(false);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined(
            'g1', testGroup(participants: ['Mario', 'Luigi']))));
      }
    };
  });

  tearDown(() => events.close());

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PartyChatLayer)));

  PartyChannelState channel(WidgetTester tester) =>
      container(tester).read(partyChannelProvider);

  /// Il livello della chat in basso a sinistra, nel gruppo `g1` con il
  /// canale attivo. [open] decide se è aperta.
  Future<void> pumpChat(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Stack(children: [
          Positioned(
            left: PartyChatLayer.left,
            bottom: PartyChatLayer.bottom,
            child: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (context, isOpen, _) => PartyChatLayer(
                open: isOpen,
                onOpen: () => open.value = true,
                onClose: () => open.value = false,
              ),
            ),
          ),
        ]),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider.overrideWithValue(channelApi),
      ],
    );
    unawaited(
        container(tester).read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pump();
    await tester.pump();
    expect(channel(tester).active, isTrue);
  }

  /// Esce dal gruppo: l'orologio del gruppo non deve lasciare timer.
  Future<void> leave(WidgetTester tester) async {
    await container(tester).read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  Future<void> receive(WidgetTester tester, String text,
      {required String id, String userId = 'u2', String userName = 'Luigi'}) async {
    events.add(PartyChannelReceived(partyPayload({'Type': 'Chat', 'Text': text},
        id: id, userId: userId, userName: userName)));
    await tester.pump();
    await tester.pump();
  }

  Finder bubbles() => find.byType(PartyChatBubble);

  group('chat chiusa: bolle (spec E §9.2)', () {
    testWidgets('nome e testo; spariscono dopo 8 s', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao a tutti', id: 'c1');
      expect(bubbles(), findsOneWidget);
      expect(find.textContaining('Luigi'), findsOneWidget);
      expect(find.textContaining('ciao a tutti'), findsOneWidget);
      await tester.pump(PartyChatLayer.bubbleLifetime -
          const Duration(milliseconds: 1));
      expect(bubbles(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      // L'uscita è finita solo oltre la sua durata (la simulazione di un
      // `AnimationController` finisce quando il tempo la supera).
      await tester.pump(WfMotion.fast + const Duration(milliseconds: 1));
      await tester.pump();
      expect(bubbles(), findsNothing);
      await leave(tester);
    });

    testWidgets('al massimo 3: la più vecchia lascia il posto',
        (tester) async {
      await pumpChat(tester);
      for (var i = 1; i <= 4; i++) {
        await receive(tester, 'messaggio $i', id: 'c$i');
      }
      expect(bubbles(), findsNWidgets(PartyChatLayer.maxBubbles));
      expect(find.textContaining('messaggio 1'), findsNothing);
      expect(find.textContaining('messaggio 4'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('i nostri da un altro PC: "Tu"', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'dal portatile',
          id: 'c1', userId: 'u1', userName: 'Mario');
      expect(find.textContaining('Tu'), findsOneWidget);
      expect(find.textContaining('Mario'), findsNothing);
      await leave(tester);
    });

    testWidgets('a schermo i messaggi non contano come non letti',
        (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao', id: 'c1');
      expect(channel(tester).unread, 0);
      await leave(tester);
    });

    testWidgets('le bolle non prendono i clic', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao', id: 'c1');
      expect(
          find.ancestor(of: bubbles(), matching: find.byType(IgnorePointer)),
          findsWidgets);
      await leave(tester);
    });
  });
}
