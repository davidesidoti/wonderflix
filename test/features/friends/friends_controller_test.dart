import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friends_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi()
      ..snapshot = FriendsSnapshot(
        friends: [testFriend('u2', 'Luigi', online: true)],
        incoming: [testPerson('u3', 'Peach')],
      );
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  ProviderContainer container(
      {SocialFeatures features = const SocialFeatures(friends: true)}) {
    final c = ProviderContainer.test(
        overrides: socialTestOverrides(api,
            events: events.stream, features: features));
    c.listen(friendsControllerProvider, (_, _) {});
    return c;
  }

  test('carica amici e richieste appena nasce', () async {
    final c = container();
    await pumpEventQueue();
    final state = c.read(friendsControllerProvider);
    expect(state.loaded, isTrue);
    expect(state.snapshot.friends.single.name, 'Luigi');
    expect(state.incomingCount, 1);
    expect(api.calls, ['friends']);
  });

  test('senza la funzione amici non chiama il plugin', () async {
    final c = container(features: SocialFeatures.none);
    await pumpEventQueue();
    await c.read(friendsControllerProvider.notifier).reload();
    expect(c.read(friendsControllerProvider).loaded, isFalse);
    expect(api.calls, isEmpty);
  });

  test('rilegge agli avvisi del plugin e alla riconnessione', () async {
    container();
    await pumpEventQueue();
    events.add(friendRequestReceived('u4', 'Daisy'));
    await pumpEventQueue();
    events.add(friendsChangedReceived());
    await pumpEventQueue();
    events
      ..add(const ServerConnected(false))
      ..add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, ['friends', 'friends', 'friends', 'friends']);
  });

  test('un caricamento fallito lascia l\'elenco di prima', () async {
    final c = container();
    await pumpEventQueue();
    api.nextFailure = SocialFailure.network;
    await c.read(friendsControllerProvider.notifier).reload();
    final state = c.read(friendsControllerProvider);
    expect(state.failed, isTrue);
    expect(state.loaded, isTrue);
    expect(state.snapshot.friends.single.name, 'Luigi');
  });

  test('vale solo la risposta dell\'ultimo caricamento', () async {
    final c = container();
    await pumpEventQueue();
    final gate = api.friendsGate = Completer<void>();
    final slow = c.read(friendsControllerProvider.notifier).reload();
    api
      ..friendsGate = null
      ..snapshot = FriendsSnapshot.empty;
    await c.read(friendsControllerProvider.notifier).reload();
    gate.complete();
    await slow;
    expect(c.read(friendsControllerProvider).snapshot.friends, isEmpty);
  });

  test('azioni: chiamano il plugin, rileggono e dicono come è andata',
      () async {
    final c = container();
    await pumpEventQueue();
    final friends = c.read(friendsControllerProvider.notifier);
    expect(await friends.request('u4'), isNull);
    expect(await friends.accept('u3'), isNull);
    expect(await friends.decline('u3'), isNull);
    expect(await friends.cancel('u4'), isNull);
    expect(await friends.remove('u2'), isNull);
    api.nextFailure = SocialFailure.conflict;
    expect(await friends.request('u4'), SocialFailure.conflict);
    await pumpEventQueue();
    expect(api.calls.where((call) => call != 'friends'), [
      'request u4',
      'accept u3',
      'decline u3',
      'cancel u4',
      'remove u2',
      'request u4',
    ]);
    expect(api.calls.where((call) => call == 'friends'), hasLength(7));
  });
}
