import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
        NotificationTypePref(type: 'RequestAvailable', enabled: true),
        NotificationTypePref(type: 'RequestPending', enabled: true),
        NotificationTypePref(type: 'DiskAlmostFull', enabled: true),
        NotificationTypePref(type: 'ReportPending', enabled: true),
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

  Future<void> pumpSection(
    WidgetTester tester, {
    Size size = const Size(1440, 1700),
  }) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: NotificationsSettingsSection()),
      ),
      overrides: overrides(),
      surfaceSize: size,
    );
    await tester.pump();
  }

  bool on(WidgetTester tester, Key key) =>
      tester.widget<Switch>(find.byKey(key)).value;
  bool tile(WidgetTester tester, String type) =>
      on(tester, Key('notification-pref-$type'));

  const forYouSwitch = Key('notification-group-forYou');
  Finder count(String text) => find.textContaining(text, findRichText: true);
  Iterable<String> sets() => api.calls.where((c) => c.startsWith('setEnabled'));

  testWidgets('solo i tipi del plugin, con le etichette e i gruppi', (
    tester,
  ) async {
    await pumpSection(tester);
    expect(count('Per te'), findsOneWidget);
    // Un gruppo da un solo tipo è la riga: il nome compare una volta.
    expect(find.text('Richieste da approvare'), findsOneWidget);
    expect(count('Admin'), findsOneWidget);
    expect(find.text('Inviti ai watch party'), findsOneWidget);
    expect(find.text('Nuovi titoli'), findsOneWidget);
    // "Admin" è chiuso nel largo.
    expect(find.text('Disco quasi pieno'), findsNothing);
    expect(find.text('Annunci'), findsNothing);
    expect(find.text('Segnalazioni nuove'), findsNothing);
    expect(find.byKey(const Key('notification-pref-FutureType')), findsNothing);
    expect(tile(tester, 'Invite'), isTrue);
    expect(tile(tester, 'NewTitles'), isFalse);
  });

  testWidgets('senza tipi admin o richieste non ci sono i loro gruppi', (
    tester,
  ) async {
    api.types = const [NotificationTypePref(type: 'Invite', enabled: true)];
    await pumpSection(tester);
    expect(count('Admin'), findsNothing);
    expect(find.text('Richieste da approvare'), findsNothing);
    // Un solo tipo in "Per te": la riga ha l'etichetta del tipo, non il
    // nome del gruppo.
    expect(find.text('Inviti ai watch party'), findsOneWidget);
    expect(find.text('Per te'), findsNothing);
    expect(find.byKey(forYouSwitch), findsNothing);
    expect(tile(tester, 'Invite'), isTrue);
  });

  testWidgets('il conteggio del gruppo e l interruttore misto', (tester) async {
    await pumpSection(tester);
    expect(count('2 di 3 attive'), findsOneWidget);
    expect(count('2 di 2 attive'), findsOneWidget);
    expect(on(tester, forYouSwitch), isFalse);
    await tester.tap(find.byKey(const Key('notification-pref-NewTitles')));
    await tester.pump();
    expect(count('3 di 3 attive'), findsOneWidget);
    expect(on(tester, forYouSwitch), isTrue);
  });

  testWidgets('interruttore del gruppo con un tipo spento: accende solo gli '
      'spenti', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(forYouSwitch));
    await tester.pump();
    expect(sets(), ['setEnabled NewTitles true']);
    expect(tile(tester, 'NewTitles'), isTrue);
    expect(on(tester, forYouSwitch), isTrue);
    // Toccare l'interruttore non chiude il gruppo.
    expect(find.text('Nuovi titoli'), findsOneWidget);
  });

  testWidgets('interruttore del gruppo tutto acceso: li spegne tutti', (
    tester,
  ) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(forYouSwitch));
    await tester.pump();
    api.calls.clear();
    await tester.tap(find.byKey(forYouSwitch));
    await tester.pump();
    expect(sets().toSet(), {
      'setEnabled Invite false',
      'setEnabled NewTitles false',
      'setEnabled RequestAvailable false',
    });
    expect(tile(tester, 'Invite'), isFalse);
    expect(on(tester, forYouSwitch), isFalse);
    expect(count('0 di 3 attive'), findsOneWidget);
  });

  testWidgets('due tipi su tre non salvati: un solo avviso', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(forYouSwitch));
    await tester.pump();
    api.failingTypes.addAll({'Invite', 'NewTitles'});
    await tester.tap(find.byKey(forYouSwitch));
    await tester.pump();
    await tester.pump();
    expect(find.text('Impostazione non salvata'), findsOneWidget);
    // Chi è fallito torna acceso, l'altro resta spento.
    expect(tile(tester, 'Invite'), isTrue);
    expect(tile(tester, 'NewTitles'), isTrue);
    expect(tile(tester, 'RequestAvailable'), isFalse);
    // Conta sulla durata di default dello SnackBar (4 s): un secondo avviso
    // in coda comparirebbe dopo il primo, mentre un solo avviso
    // è già sparito dopo tre passi (arriva, aspetta, esce).
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('Impostazione non salvata'), findsNothing);
  });

  testWidgets('gruppo da un tipo: riga normale, senza freccia', (tester) async {
    await pumpSection(tester);
    expect(find.byKey(const Key('notification-group-requests')), findsNothing);
    expect(tile(tester, 'RequestPending'), isTrue);
    await tester.tap(find.text('Richieste da approvare'));
    await tester.pump();
    expect(api.calls, contains('setEnabled RequestPending false'));
    expect(tile(tester, 'RequestPending'), isFalse);
  });

  testWidgets('largo: "Per te" aperto, gli altri chiusi', (tester) async {
    await pumpSection(tester);
    expect(find.text('Inviti ai watch party'), findsOneWidget);
    expect(find.text('Disco quasi pieno'), findsNothing);
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
  });

  testWidgets('stretto: tutti i gruppi chiusi', (tester) async {
    await pumpSection(tester, size: const Size(500, 1700));
    expect(find.text('Inviti ai watch party'), findsNothing);
    expect(find.text('Disco quasi pieno'), findsNothing);
    expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
    expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));
    expect(tile(tester, 'RequestPending'), isTrue);
  });

  testWidgets('toccare l intestazione apre e chiude il gruppo', (tester) async {
    await pumpSection(tester);
    await tester.tap(count('Admin'));
    await tester.pump();
    expect(find.text('Disco quasi pieno'), findsOneWidget);
    expect(tile(tester, 'DiskAlmostFull'), isTrue);
    await tester.tap(count('Per te'));
    await tester.pump();
    expect(find.text('Inviti ai watch party'), findsNothing);
    expect(find.byKey(forYouSwitch), findsOneWidget);
    await tester.tap(count('Per te'));
    await tester.pump();
    expect(find.text('Inviti ai watch party'), findsOneWidget);
  });

  testWidgets('semantica: l intestazione dice se e aperta, l interruttore ha '
      'il nome del gruppo', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpSection(tester);
    final header = find.semantics.byLabel('Per te, 2 di 3 attive');
    expect(header, findsOneWidget);
    expect(
      header,
      isSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    expect(
      find.semantics.byLabel('Per te'),
      isSemantics(hasToggledState: true, isToggled: false),
    );
    await tester.tap(count('Per te'));
    await tester.pump();
    expect(
      find.semantics.byLabel('Per te, 2 di 3 attive'),
      isSemantics(hasExpandedState: true, isExpanded: false),
    );
    semantics.dispose();
  });

  testWidgets('un interruttore di un tipo spento manda setEnabled false', (
    tester,
  ) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('notification-pref-Invite')));
    await tester.pump();
    expect(api.calls, contains('setEnabled Invite false'));
    expect(tile(tester, 'Invite'), isFalse);
  });

  testWidgets('errore: torna acceso e dice che non e salvato', (tester) async {
    await pumpSection(tester);
    api.failure = const ServerUnreachableException();
    await tester.tap(find.byKey(const Key('notification-pref-Invite')));
    await tester.pump();
    await tester.pump();
    expect(tile(tester, 'Invite'), isTrue);
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
    expect(next.types, hasLength(7));
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
