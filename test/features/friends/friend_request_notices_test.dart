import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friend_request_notices.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  ProviderContainer container(
      {SocialFeatures features = const SocialFeatures(friends: true)}) {
    final c = ProviderContainer.test(
        overrides: socialTestOverrides(api,
            events: events.stream, features: features));
    c.listen(friendRequestNoticesProvider, (_, _) {});
    return c;
  }

  test('mostra la richiesta per 10 s', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider)?.fromName, 'Luigi');
      async.elapse(FriendRequestNotices.showFor);
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('una richiesta più recente sostituisce la precedente e riavvia i 10 s',
      () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 6));
      expect(c.read(friendRequestNoticesProvider)?.fromName, 'Luigi');

      events.add(friendRequestReceived('u3', 'Peach'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider)?.fromName, 'Peach');
      // 12 s dalla prima richiesta, 6 dalla seconda: il timer è ripartito.
      async.elapse(const Duration(seconds: 6));
      expect(c.read(friendRequestNoticesProvider)?.fromName, 'Peach');
      async.elapse(const Duration(seconds: 4));
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('non con il player aperto; aprirlo la toglie', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      final player = c.read(playerActiveProvider.notifier)..enter();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);

      player.leave();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNotNull);
      player.enter();
      // enter/leave pubblicano lo stato in un microtask.
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('accettata o rifiutata altrove: se ne va', () {
    fakeAsync((async) {
      api.snapshot =
          FriendsSnapshot(incoming: [testPerson('u2', 'Luigi')]);
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNotNull);

      api.snapshot = FriendsSnapshot.empty;
      events.add(friendsChangedReceived());
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('senza la funzione amici: niente', () {
    fakeAsync((async) {
      final c = container(features: SocialFeatures.none);
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });
}
