import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/social/notifications_models.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/settings/notification_prefs_controller.dart';
import 'package:wonderflix/features/settings/notifications_settings_section.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/notifications_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/settings_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeNotificationsApi api;

  setUp(
    () => api = FakeNotificationsApi(
      types: const [
        NotificationTypePref(type: 'Invite', enabled: true),
        NotificationTypePref(type: 'NewTitles', enabled: false),
        NotificationTypePref(type: 'RequestPending', enabled: true),
        NotificationTypePref(type: 'DiskAlmostFull', enabled: true),
        NotificationTypePref(type: 'FutureType', enabled: true),
      ],
    ),
  );

  List<Override> overrides({bool push = true}) => [
    sessionControllerProvider.overrideWith(
      () => FakeSessionController(const SessionSignedIn(testUser)),
    ),
    notificationsApiProvider.overrideWithValue(api),
    socialAvailabilityProvider.overrideWith(
      () => FakeSocialAvailability(SocialFeatures(push: push)),
    ),
  ];

  Future<void> pumpSection(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: NotificationsSettingsSection()),
      ),
      overrides: overrides(),
      surfaceSize: const Size(1440, 1700),
    );
    await tester.pump();
  }

  SwitchListTile tile(WidgetTester tester, String type) =>
      tester.widget<SwitchListTile>(find.byKey(Key('notification-pref-$type')));

  testWidgets('solo i tipi del plugin, con le etichette e i gruppi', (
    tester,
  ) async {
    await pumpSection(tester);
    expect(find.text('Per te'), findsOneWidget);
    // Il gruppo e l'etichetta del suo unico tipo.
    expect(find.text('Richieste da approvare'), findsNWidgets(2));
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Inviti ai watch party'), findsOneWidget);
    expect(find.text('Nuovi titoli'), findsOneWidget);
    expect(find.text('Disco quasi pieno'), findsOneWidget);
    expect(find.text('Annunci'), findsNothing);
    expect(find.text('Segnalazioni nuove'), findsNothing);
    expect(find.byKey(const Key('notification-pref-FutureType')), findsNothing);
    expect(tile(tester, 'Invite').value, isTrue);
    expect(tile(tester, 'NewTitles').value, isFalse);
  });

  testWidgets('senza tipi admin o richieste non ci sono i loro gruppi', (
    tester,
  ) async {
    api.types = const [NotificationTypePref(type: 'Invite', enabled: true)];
    await pumpSection(tester);
    expect(find.text('Per te'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);
    expect(find.text('Richieste da approvare'), findsNothing);
  });

  testWidgets('un interruttore spento manda setEnabled false', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('notification-pref-Invite')));
    await tester.pump();
    expect(api.calls, contains('setEnabled Invite false'));
    expect(tile(tester, 'Invite').value, isFalse);
  });

  testWidgets('errore: torna acceso e dice che non e salvato', (tester) async {
    await pumpSection(tester);
    api.failure = const ServerUnreachableException();
    await tester.tap(find.byKey(const Key('notification-pref-Invite')));
    await tester.pump();
    await tester.pump();
    expect(tile(tester, 'Invite').value, isTrue);
    expect(find.text('Impostazione non salvata'), findsOneWidget);
  });

  testWidgets('lettura non riuscita: il messaggio e Riprova', (tester) async {
    api.failure = const ServerUnreachableException();
    await pumpSection(tester);
    expect(find.text("Impossibile caricare l'impostazione"), findsOneWidget);
    api.failure = null;
    await tester.tap(find.byKey(const Key('notification-prefs-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('notification-pref-Invite')), findsOneWidget);
  });

  testWidgets('isEnabled: vero se un tipo e sconosciuto', (tester) async {
    await pumpSection(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotificationsSettingsSection)),
    );
    final prefs = container.read(notificationPrefsProvider.notifier);
    expect(prefs.isEnabled('NewTitles'), isFalse);
    expect(prefs.isEnabled('Invite'), isTrue);
    expect(prefs.isEnabled('Sconosciuto'), isTrue);
  });

  ProviderContainer container({
    bool push = true,
    FakeSessionController? session,
  }) => ProviderContainer.test(
    overrides: [
      sessionControllerProvider.overrideWith(
        () => session ?? FakeSessionController(const SessionSignedIn(testUser)),
      ),
      notificationsApiProvider.overrideWithValue(api),
      socialAvailabilityProvider.overrideWith(
        () => FakeSocialAvailability(SocialFeatures(push: push)),
      ),
    ],
  );

  test('senza push non chiede niente, anche letto direttamente; con push '
      'dopo, legge', () async {
    final c = container(push: false);
    final info = await c.read(notificationPrefsProvider.future);
    expect(info.types, isEmpty);
    expect(api.calls, isEmpty);
    expect(
      c.read(notificationPrefsProvider.notifier).isEnabled('Invite'),
      isTrue,
    );
    (c.read(socialAvailabilityProvider.notifier) as FakeSocialAvailability).set(
      const SocialFeatures(push: true),
    );
    final next = await c.read(notificationPrefsProvider.future);
    expect(api.calls, ['get']);
    expect(next.types, hasLength(5));
  });

  test('senza utente non chiede niente', () async {
    final c = container(
      session: FakeSessionController(const SessionSignedOut()),
    );
    await c.read(notificationPrefsProvider.future);
    expect(api.calls, isEmpty);
  });

  testWidgets('cambio di profilo: gli interruttori del precedente non si '
      'vedono mentre si rilegge', (tester) async {
    final session = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: NotificationsSettingsSection()),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        notificationsApiProvider.overrideWithValue(api),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(const SocialFeatures(push: true)),
        ),
      ],
      surfaceSize: const Size(1440, 1700),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('notification-pref-NewTitles')),
      findsOneWidget,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotificationsSettingsSection)),
    );

    api.getGate = Completer<void>();
    session.set(const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Anna')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('notification-pref-NewTitles')), findsNothing);
    expect(find.text('Nuovi titoli'), findsNothing);
    expect(
      container.read(notificationPrefsProvider.notifier).isEnabled('NewTitles'),
      isTrue,
    );

    api.getGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('notification-pref-NewTitles')),
      findsOneWidget,
    );
  });

  test('due tocchi sullo stesso tipo, tutti e due falliti: torna a quello '
      'del plugin', () async {
    final c = container();
    await c.read(notificationPrefsProvider.future);
    final prefs = c.read(notificationPrefsProvider.notifier);
    api.setGate = Completer<void>();
    api.failure = const ServerUnreachableException();
    final first = prefs.setEnabled('Invite', false);
    final second = prefs.setEnabled('Invite', true);
    expect(prefs.isEnabled('Invite'), isTrue);
    api.setGate!.complete();
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(prefs.isEnabled('Invite'), isTrue);
  });

  test('un salvataggio fallito dopo il cambio di profilo non tocca il nuovo '
      'utente', () async {
    final session = FakeSessionController(const SessionSignedIn(testUser));
    final c = container(session: session);
    await c.read(notificationPrefsProvider.future);
    final prefs = c.read(notificationPrefsProvider.notifier);
    api.setGate = Completer<void>();
    final pending = prefs.setEnabled('Invite', false);
    session.set(const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Anna')));
    api.types = const [NotificationTypePref(type: 'Invite', enabled: false)];
    await c.read(notificationPrefsProvider.future);
    // Il salvataggio del primo utente fallisce quando il nuovo è già letto.
    api.failure = const ServerUnreachableException();
    api.setGate!.complete();
    expect(await pending, isFalse);
    expect(prefs.isEnabled('Invite'), isFalse);
  });

  for (final push in [true, false]) {
    testWidgets('Impostazioni con push=$push', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpApp(
        tester,
        const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 2400),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountAvailableProvider.overrideWithValue(false),
          clientInfoProvider.overrideWithValue(testClientInfo),
          userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
          ...homeSettingsOverrides(features: SocialFeatures(push: push)),
          watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
          sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser)),
          ),
          notificationsApiProvider.overrideWithValue(api),
        ],
      );
      await tester.pump();
      expect(
        find.byType(NotificationsSettingsSection),
        push ? findsOneWidget : findsNothing,
      );
      // Col push: la voce della colonna e il titolo della sezione.
      expect(find.text('Notifiche'), push ? findsNWidgets(2) : findsNothing);
      expect(api.calls.contains('get'), push);
    });
  }
}
