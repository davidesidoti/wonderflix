import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/push/web_push.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/device_push_controller.dart';
import 'package:wonderflix/features/settings/device_push_tile.dart';
import 'package:wonderflix/features/settings/notification_prefs_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/notifications_fakes.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeWebPush web;
  late FakeNotificationsApi api;
  late SharedPreferences prefs;

  setUp(() async {
    web = FakeWebPush();
    api = FakeNotificationsApi();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpTile(WidgetTester tester,
      {bool inBrowser = true, bool fakeWeb = true}) async {
    await pumpApp(
      tester,
      Scaffold(body: DevicePushTile(inBrowser: inBrowser)),
      overrides: <Override>[
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
        profilesProvider.overrideWith(
          () => FixedProfiles(const ProfilesState(activeUserId: 'u1')),
        ),
        notificationsApiProvider.overrideWithValue(api),
        sharedPreferencesProvider.overrideWithValue(prefs),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(const SocialFeatures(push: true)),
        ),
        if (fakeWeb) webPushProvider.overrideWithValue(web),
      ],
    );
    await tester.pump();
  }

  const messages = {
    PushAvailability.unsupported:
        'Le notifiche non sono disponibili in questo browser',
    PushAvailability.needsHomeScreen:
        'Per ricevere le notifiche aggiungi WonderFlix alla schermata Home '
            'e aprilo da lì',
    PushAvailability.denied:
        'Notifiche bloccate: riattivale dalle impostazioni del telefono o del '
            'browser',
  };

  for (final MapEntry(key: availability, value: text) in messages.entries) {
    testWidgets('$availability: il messaggio', (tester) async {
      web.state = availability;
      await pumpTile(tester);
      expect(find.text(text), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  }

  testWidgets('ready: il pulsante attiva, poi attive con Disattiva',
      (tester) async {
    await pumpTile(tester);
    expect(find.text('Notifiche attive su questo dispositivo'), findsNothing);

    await tester.tap(find.text('Attiva notifiche su questo dispositivo'));
    await tester.pump();
    await tester.pump();

    expect(web.subscribeKeys, hasLength(1));
    expect(find.text('Notifiche attive su questo dispositivo'), findsOneWidget);
    expect(find.text('Disattiva'), findsOneWidget);

    await tester.tap(find.text('Disattiva'));
    await tester.pump();
    await tester.pump();

    expect(api.calls.last, 'unsubscribe ${testPushKeys.endpoint}');
    expect(find.text('Attiva notifiche su questo dispositivo'), findsOneWidget);
  });

  testWidgets('sull\'app Windows non c\'è (stub io: unsupported)',
      (tester) async {
    await pumpTile(tester, inBrowser: false, fakeWeb: false);
    for (final text in messages.values) {
      expect(find.text(text), findsNothing);
    }
    expect(find.text('Attiva notifiche su questo dispositivo'), findsNothing);
  });
}
