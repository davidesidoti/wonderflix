import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/notifications_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/inbox/inbox_controller.dart';
import 'package:wonderflix/features/inbox/inbox_toaster.dart';
import 'package:wonderflix/features/inbox/windows_toasts.dart';
import 'package:wonderflix/features/inbox/windows_toasts_web.dart' as web;
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/settings/notification_prefs_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/notifications_fakes.dart';
import '../../support/social_fakes.dart';

class _FakeToasts implements Toasts {
  final shown = <({String title, String body, void Function() onClick})>[];

  @override
  void show(String title, String body, void Function() onClick) =>
      shown.add((title: title, body: body, onClick: onClick));
}

class _FakeRouter extends Fake implements GoRouter {
  final went = <String>[];

  @override
  void go(String location, {Object? extra}) => went.add(location);
}

class _FixedLocale extends LocaleController {
  @override
  Locale? build() => const Locale('it');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocialApi api;
  late StreamController<ServerEvent> events;
  late _FakeToasts toasts;
  late _FakeRouter router;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
    toasts = _FakeToasts();
    router = _FakeRouter();
  });

  ProviderContainer container({List<NotificationTypePref> prefs = const []}) {
    final c = ProviderContainer.test(
      overrides: [
        ...socialTestOverrides(
          api,
          events: events.stream,
          features: const SocialFeatures(inbox: true, push: true),
        ),
        notificationsApiProvider.overrideWithValue(
          FakeNotificationsApi(types: prefs),
        ),
        toastsProvider.overrideWithValue(toasts),
        routerProvider.overrideWithValue(router),
        localeProvider.overrideWith(_FixedLocale.new),
      ],
    );
    c.listen(inboxControllerProvider, (_, _) {});
    c.listen(inboxToasterProvider, (_, _) {});
    return c;
  }

  InboxSnapshot inbox(List<InboxEntry> entries) =>
      InboxSnapshot(entries: entries, unread: entries.length);

  test('arrival_afterInboxChanged_toasts', () async {
    api.inboxSnapshot = inbox([testAnnouncement(id: 'a1', seq: 1)]);
    container();
    await pumpEventQueue();
    expect(toasts.shown, isEmpty);

    api.inboxSnapshot = inbox([
      testInvite(id: 'i2', seq: 2),
      testAnnouncement(id: 'a1', seq: 1),
    ]);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(toasts.shown.map((t) => t.title), [
      startsWith(testInvite().fromName),
    ]);
  });

  test('firstLoad_noToast', () async {
    api.inboxSnapshot = inbox([
      testInvite(id: 'i2', seq: 2),
      testAnnouncement(id: 'a1', seq: 1),
    ]);
    container();
    await pumpEventQueue();
    expect(toasts.shown, isEmpty);
  });

  test('reconnectReload_noToast, anche con 5 voci nuove', () async {
    api.inboxSnapshot = inbox([testAnnouncement(id: 'a0', seq: 1)]);
    container();
    await pumpEventQueue();

    api.inboxSnapshot = inbox([
      for (var seq = 2; seq <= 6; seq++)
        testAnnouncement(id: 'a$seq', seq: seq),
      testAnnouncement(id: 'a0', seq: 1),
    ]);
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(toasts.shown, isEmpty);

    // Dopo la riconnessione le voci viste non suonano più.
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(toasts.shown, isEmpty);
  });

  test('profilo cambiato: le voci del nuovo profilo non suonano', () async {
    api.inboxSnapshot = inbox([testAnnouncement(id: 'a1', seq: 1)]);
    final c = container();
    await pumpEventQueue();

    // Il primo caricamento del nuovo profilo non riesce: la prima lettura
    // riuscita, anche se nata da un InboxChanged, fissa solo il massimo.
    api.nextFailure = SocialFailure.network;
    (c.read(sessionControllerProvider.notifier) as FakeSessionController).set(
      const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Bea')),
    );
    await pumpEventQueue();
    api.inboxSnapshot = inbox([testAnnouncement(id: 'b9', seq: 9)]);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(toasts.shown, isEmpty);
  });

  test('disabledType_noToast', () async {
    api.inboxSnapshot = inbox([testAnnouncement(id: 'a1', seq: 1)]);
    container(
      prefs: const [
        NotificationTypePref(type: 'Invite', enabled: false),
        NotificationTypePref(type: 'Announcement', enabled: true),
      ],
    );
    await pumpEventQueue();

    api.inboxSnapshot = inbox([
      testInvite(id: 'i3', seq: 3),
      testAnnouncement(id: 'a2', seq: 2),
      testAnnouncement(id: 'a1', seq: 1),
    ]);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(toasts.shown.map((t) => t.title), ['Annuncio']);
  });

  test('click_focusesWindowAndGoesToRoute', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call.method);
          return call.method == 'isMinimized' ? false : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          ),
    );
    api.inboxSnapshot = inbox(const []);
    container();
    await pumpEventQueue();

    api.inboxSnapshot = inbox([testAnnouncement(id: 'a1', seq: 1)]);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    toasts.shown.single.onClick();
    await pumpEventQueue();
    expect(calls, containsAllInOrder(['show', 'focus']));
    expect(router.went, ['/inbox']);
  });

  test('web_noToasts', () {
    // Lo stub del sito non fa niente, nemmeno chiamare il tocco.
    var clicked = false;
    web.createToasts().show('t', 'b', () => clicked = true);
    expect(clicked, isFalse);
  });
}
