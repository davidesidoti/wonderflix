import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/player/player_handover.dart';
import 'package:wonderflix/features/player/player_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_routing.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/playback_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late FakePartyNavigator navigator;
  late FakePlayerWindow window;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    navigator = FakePartyNavigator();
    window = FakePlayerWindow();
    container = ProviderContainer.test(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      partyNavigatorProvider.overrideWithValue(navigator),
      playerWindowProvider.overrideWithValue(window),
    ]);
    container.listen(watchPartyRoutingProvider, (_, _) {});
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> joinAndQueue(PlayQueue queue) async {
    await container.read(watchPartySessionProvider.notifier).join('g1');
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', queue)));
    await pumpEventQueue();
  }

  test('la coda del gruppo apre il player', () async {
    await joinAndQueue(testQueue(start: const Duration(minutes: 1)));
    expect(navigator.opened, ['/play/m1?start=60000&party=p1']);
    expect(navigator.replaced, isEmpty);
  });

  test('con un player già aperto lo sostituisce', () async {
    navigator.location = Uri.parse('/play/m9');
    await joinAndQueue(testQueue());
    expect(navigator.replaced, ['/play/m1?party=p1']);
    expect(navigator.opened, isEmpty);
  });

  test('stesso elemento già aperto: niente', () async {
    navigator.location = Uri.parse('/play/m1?party=p1');
    await joinAndQueue(testQueue());
    expect(navigator.opened, isEmpty);
    expect(navigator.replaced, isEmpty);
  });

  test('una coda di un altro gruppo non apre nulla', () async {
    events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', testQueue())));
    await pumpEventQueue();
    expect(navigator.opened, isEmpty);
  });

  test('un player del gruppo già aperto: lo cambia lui, non il routing',
      () async {
    navigator.location = Uri.parse('/play/e4?party=p1');
    await joinAndQueue(testSeriesQueue(playingIndex: 1));
    expect(navigator.opened, isEmpty);
    expect(navigator.replaced, isEmpty);
  });

  test('player da solo che entra nel gruppo a schermo intero: resta così',
      () async {
    navigator.location = Uri.parse('/play/m1');
    window.fullScreen = true;
    await joinAndQueue(testQueue());
    expect(navigator.replaced, ['/play/m1?fs=1&party=p1']);
  });

  test('il player da solo sostituito lo sa (non esce dallo schermo intero)',
      () async {
    navigator.location = Uri.parse('/play/m9');
    await joinAndQueue(testQueue());
    final handover = container.read(playerHandoverProvider);
    expect(handover.consume('m1'), isFalse);
    expect(handover.consume('m9'), isTrue);
    expect(handover.consume('m9'), isFalse, reason: 'vale una volta sola');
  });

  test('pagina cambiata mentre si legge lo schermo intero: niente', () async {
    navigator.location = Uri.parse('/play/m9');
    window.onIsFullScreen = () => navigator.location = Uri.parse('/home');
    await joinAndQueue(testQueue());
    expect(navigator.replaced, isEmpty);
    expect(container.read(playerHandoverProvider).consume('m9'), isFalse);
  });
}
