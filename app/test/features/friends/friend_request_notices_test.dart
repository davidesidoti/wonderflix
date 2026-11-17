import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friend_request_notices.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/invite_card_frame.dart';

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

  test('la richiesta resta finché la carta non la chiude', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider)?.fromName, 'Luigi');
      expect(c.read(newestInviteProvider), InviteKind.friend);
      async.elapse(inviteCardShowFor);
      expect(c.read(friendRequestNoticesProvider), isNotNull);
      c.read(friendRequestNoticesProvider.notifier).dismiss();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('aprire il pannello Amici toglie la carta', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNotNull);
      c.read(shellPanelProvider.notifier).open(ShellPanel.friends);
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('una richiesta più recente sostituisce la precedente', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      events.add(friendRequestReceived('u3', 'Peach'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider)?.fromName, 'Peach');
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
