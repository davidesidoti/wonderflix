import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/push/web_push.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/device_push_controller.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/settings/notification_prefs_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/notifications_fakes.dart';
import '../../support/profile_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

class MockAuthService extends Mock implements AuthService {}

const _key = 'push.endpoint./wonderflix/.u1';
const _keyU2 = 'push.endpoint./wonderflix/.u2';

/// La chiave dello stesso profilo nel sito di prova (stessa origine).
const _keyProva = 'push.endpoint./wonderflix-prova/.u1';

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

  ProviderContainer container() => ProviderContainer.test(
        overrides: [
          sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser)),
          ),
          profilesProvider.overrideWith(
            () => FixedProfiles(const ProfilesState(activeUserId: 'u1')),
          ),
          notificationsApiProvider.overrideWithValue(api),
          webPushProvider.overrideWithValue(web),
          sharedPreferencesProvider.overrideWithValue(prefs),
          socialAvailabilityProvider.overrideWith(
            () => FakeSocialAvailability(const SocialFeatures(push: true)),
          ),
        ],
      );

  /// Il pulsante si vede con le preferenze caricate: c'è la chiave VAPID.
  Future<ProviderContainer> ready() async {
    final c = container();
    await c.read(notificationPrefsProvider.future);
    await c.read(devicePushProvider.future);
    return c;
  }

  test('activate: iscrive il browser e il plugin, con la lingua', () async {
    final c = await ready();
    await c.read(localeProvider.notifier).set(const Locale('it'));

    expect(await c.read(devicePushProvider.notifier).activate(), isTrue);

    expect(web.subscribeKeys, ['BKey']);
    expect(api.calls.last, 'subscribe ${testPushKeys.endpoint} it');
    expect(c.read(devicePushProvider).value, PushAvailability.active);
    expect(prefs.getString(_key), testPushKeys.endpoint);
  });

  test('activate senza permesso: denied, niente al plugin', () async {
    web.keys = null;
    final c = await ready();
    web.state = PushAvailability.denied;

    await c.read(devicePushProvider.notifier).activate();

    expect(c.read(devicePushProvider).value, PushAvailability.denied);
    expect(api.calls, ['get']);
    expect(prefs.getString(_key), isNull);
  });

  test('richiesta del permesso chiusa senza scegliere: di nuovo ready',
      () async {
    web.keys = null;
    final c = await ready();

    await c.read(devicePushProvider.notifier).activate();

    expect(c.read(devicePushProvider).value, PushAvailability.ready);
  });

  test("chiave dell'altro sito: per questo è ready", () async {
    web.state = PushAvailability.active;
    await prefs.setString(_keyProva, testPushKeys.endpoint);
    final c = await ready();
    expect(c.read(devicePushProvider).value, PushAvailability.ready);
  });

  test("deactivate: la chiave dell'altro sito non tiene il browser iscritto",
      () async {
    final c = await ready();
    await c.read(devicePushProvider.notifier).activate();
    await prefs.setString(_keyProva, 'https://push.example/prova');

    await c.read(devicePushProvider.notifier).deactivate();

    expect(web.unsubscribeCalls, 1);
    expect(prefs.getString(_keyProva), 'https://push.example/prova');
  });

  test('iscrizione del browser di un altro profilo: per questo è ready',
      () async {
    web.state = PushAvailability.active;
    await prefs.setString(_keyU2, testPushKeys.endpoint);
    final c = await ready();
    expect(c.read(devicePushProvider).value, PushAvailability.ready);
  });

  test('cambio di lingua con le push attive: di nuovo al plugin', () async {
    final c = await ready();
    await c.read(localeProvider.notifier).set(const Locale('it'));
    await c.read(devicePushProvider.notifier).activate();

    await c.read(localeProvider.notifier).set(const Locale('en'));
    await pumpEventQueue();

    expect(api.calls.last, 'subscribe ${testPushKeys.endpoint} en');
  });

  test('cambio di lingua senza push attive: niente al plugin', () async {
    final c = await ready();
    await c.read(localeProvider.notifier).set(const Locale('en'));
    await pumpEventQueue();
    expect(api.calls, ['get']);
  });

  test('deactivate: DELETE e chiave tolta; il browser resta per un altro '
      'profilo', () async {
    final c = await ready();
    await c.read(devicePushProvider.notifier).activate();
    await prefs.setString(_keyU2, testPushKeys.endpoint);

    expect(await c.read(devicePushProvider.notifier).deactivate(), isTrue);

    expect(api.calls.last, 'unsubscribe ${testPushKeys.endpoint}');
    expect(prefs.getString(_key), isNull);
    expect(web.unsubscribeCalls, 0);
    expect(c.read(devicePushProvider).value, PushAvailability.ready);
  });

  test('deactivate dell\'ultimo profilo: anche il browser', () async {
    final c = await ready();
    await c.read(devicePushProvider.notifier).activate();
    await c.read(devicePushProvider.notifier).deactivate();
    expect(web.unsubscribeCalls, 1);
  });

  test('deactivate con il DELETE che fallisce: restano attive', () async {
    final c = await ready();
    await c.read(devicePushProvider.notifier).activate();
    api.failure = const ServerUnreachableException();

    expect(await c.read(devicePushProvider.notifier).deactivate(), isFalse);

    expect(prefs.getString(_key), testPushKeys.endpoint);
    expect(c.read(devicePushProvider).value, PushAvailability.active);
  });

  group('uscita', () {
    late MockAuthService auth;
    late ProviderContainer c;
    String? active;

    setUp(() async {
      auth = MockAuthService();
      active = null;
      when(() => auth.book).thenReturn(const ProfileBook());
      when(() => auth.activeUserId).thenAnswer((_) => active);
      when(() => auth.isActive(any()))
          .thenAnswer((i) => i.positionalArguments.single == active);
      when(() => auth.logout()).thenAnswer((_) async {
        api.calls.add('logout');
        active = null;
        return 'u1';
      });
      when(() => auth.removeProfile(any())).thenAnswer((_) async {
        api.calls.add('removeProfile');
        active = null;
      });
      c = ProviderContainer.test(overrides: [
        authServiceProvider.overrideWithValue(auth),
        jellyfinHttpProvider.overrideWithValue(
          JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo),
        ),
        notificationsApiProvider.overrideWithValue(api),
        webPushProvider.overrideWithValue(web),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      active = 'u1';
      c.read(sessionControllerProvider.notifier).quickConnectApproved(testUser);
      await prefs.setString(_key, testPushKeys.endpoint);
    });

    test('logout: il DELETE prima di annullare il token', () async {
      await prefs.setString(_keyProva, 'https://push.example/prova');
      await c.read(sessionControllerProvider.notifier).logout();

      expect(api.calls, ['unsubscribe ${testPushKeys.endpoint}', 'logout']);
      expect(prefs.getString(_key), isNull);
      // La chiave dell'altro sito resta; questo browser si disiscrive.
      expect(prefs.getString(_keyProva), 'https://push.example/prova');
      expect(web.unsubscribeCalls, 1);
    });

    test('logout con il DELETE che fallisce: si esce lo stesso', () async {
      api.failure = const ServerUnreachableException();

      await c.read(sessionControllerProvider.notifier).logout();

      expect(api.calls, ['unsubscribe ${testPushKeys.endpoint}', 'logout']);
      expect(c.read(sessionControllerProvider), isA<SessionSignedOut>());
      expect(prefs.getString(_key), isNull);
    });

    test('DELETE che fallisce con un altro profilo iscritto: browser '
        'disiscritto e tutte le chiavi tolte', () async {
      api.failure = const ServerUnreachableException();
      await prefs.setString(_keyU2, testPushKeys.endpoint);
      await prefs.setString(_keyProva, 'https://push.example/prova');

      await c.read(sessionControllerProvider.notifier).logout();

      expect(web.unsubscribeCalls, 1);
      expect(prefs.getKeys().where((k) => k.startsWith('push.endpoint.')),
          isEmpty);
      expect(prefs.getString(_keyProva), isNull);
      expect(c.read(sessionControllerProvider), isA<SessionSignedOut>());
    });

    test('rimozione del profilo aperto: il DELETE prima', () async {
      await c.read(sessionControllerProvider.notifier).removeProfile('u1');
      expect(api.calls,
          ['unsubscribe ${testPushKeys.endpoint}', 'removeProfile']);
    });
  });
}
