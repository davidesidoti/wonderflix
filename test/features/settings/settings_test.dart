import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/window_setup.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/diagnostics.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/ui/user_avatar.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';

void main() {
  test('LocaleController salva e rilegge la lingua', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer.test(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(container.read(localeProvider), isNull);
    await container.read(localeProvider.notifier).set(const Locale('en'));
    expect(container.read(localeProvider), const Locale('en'));
    expect(prefs.getString('locale'), 'en');
    await container.read(localeProvider.notifier).set(null);
    expect(prefs.getString('locale'), isNull);
  });

  testWidgets('schermata: utente, lingua, versione, esci', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = FakeSessionController(const SessionSignedIn(testUser));
    // Alta abbastanza da avere i pulsanti dell'account (sotto l'avatar)
    // senza scorrere.
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 1700),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(() => session),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
      // "Cambia profilo" legge il watch party: niente eventi del server.
      watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
    ]);

    expect(find.text('Accesso come Mario'), findsOneWidget);
    expect(find.byType(UserAvatar), findsOneWidget);
    await tester.tap(find.text('Cambia immagine'));
    await tester.pumpAndSettle();
    expect(find.text('Immagine del profilo'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Versione 0.0.1'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pump();
    expect(prefs.getString('locale'), 'en');

    await tester.tap(find.text('Cambia profilo'));
    await tester.pump();
    expect(session.switchCalls, 1);
    // Il fake è passato a "Chi guarda?": di nuovo dentro, per provare Esci.
    session.set(const SessionSignedIn(testUser));
    await tester.pump();

    await tester.tap(find.text('Esci'));
    await tester.pump();
    expect(session.logoutCalls, 1);
  });

  testWidgets('sezione Player: qualità, sottotitoli, interruttori',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 1600),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
    ]);

    expect(find.text('Player'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media (8 Mbps)').last);
    await tester.pumpAndSettle();
    expect(prefs.getString('player.quality'), 'mbps8');

    await tester.tap(find.text('Grandi'));
    await tester.pump();
    expect(prefs.getDouble('player.subtitleScale'), 1.0);
    await tester.tap(find.text('Molto piccoli'));
    await tester.pump();
    expect(prefs.getDouble('player.subtitleScale'), 0.45);

    await tester.tap(find.text('Decodifica hardware'));
    await tester.pump();
    expect(prefs.getBool('player.hardwareDecoding'), isFalse);

    await tester.tap(find.text('Salta automaticamente intro e riassunti'));
    await tester.pump();
    expect(prefs.getBool('player.autoSkipIntro'), isTrue);

    await tester.tap(find.text('Avvia automaticamente il prossimo episodio'));
    await tester.pump();
    expect(prefs.getBool('player.autoplayNext'), isFalse);
  });

  testWidgets('dimensioni dei sottotitoli nella finestra più stretta',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: Size(minWindowSize.width, 1600),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Molto piccoli'), findsOneWidget);
  });

  Future<FakeUserConfigApi> pumpSettings(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final configApi = FakeUserConfigApi();
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 1600),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(configApi),
    ]);
    await tester.pump();
    return configApi;
  }

  testWidgets('lingue: valori dal server, salvataggio completo',
      (tester) async {
    final configApi = await pumpSettings(tester);
    expect(find.text('Lingue di riproduzione'), findsOneWidget);
    expect(find.text('Italiano'), findsWidgets);

    await tester.tap(find.byKey(const Key('subtitle-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mai').last);
    await tester.pumpAndSettle();

    final (userId, saved) = configApi.saved.single;
    expect(userId, 'u1');
    expect(saved['SubtitleMode'], 'None');
    expect(saved['AudioLanguagePreference'], 'ita');
    expect(saved['HidePlayedInLatest'], isTrue,
        reason: 'gli altri campi restano');
  });

  testWidgets('lingue: errore di salvataggio, avviso e valore precedente',
      (tester) async {
    final configApi = await pumpSettings(tester);
    configApi.saveError = const ServerUnreachableException();

    await tester.tap(find.byKey(const Key('subtitle-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sempre').last);
    await tester.pumpAndSettle();

    expect(find.text('Impossibile salvare. Riprova.'), findsOneWidget);
    expect(
        tester
            .widget<DropdownButton<String>>(find.byKey(const Key('subtitle-mode')))
            .value,
        'Default',
        reason: 'torna al valore di prima');
    expect(configApi.saved, isEmpty);
  });

  group('LanguagePreferencesController', () {
    late FakeUserConfigApi configApi;
    late ProviderContainer container;

    setUp(() {
      configApi = FakeUserConfigApi();
      container = ProviderContainer.test(overrides: [
        userConfigApiProvider.overrideWithValue(configApi),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ]);
      container.listen(languagePreferencesProvider, (_, _) {});
    });

    test('salvataggi in fila; un errore non annulla una scelta successiva',
        () async {
      final initial = await container.read(languagePreferencesProvider.future);
      final modes = <String?>[];
      container.listen(languagePreferencesProvider,
          (_, next) => modes.add(next.value?.subtitleMode));
      final notifier = container.read(languagePreferencesProvider.notifier);
      configApi
        ..saveGate = Completer<void>()
        ..failSaves = 1;

      final first = notifier.save(initial.copyWith(subtitleMode: 'Always'));
      final second = notifier.save(initial.copyWith(subtitleMode: 'None'));
      configApi.saveGate!.complete();
      await expectLater(first, throwsStateError);
      await second;

      expect(modes, ['Always', 'None'],
          reason: 'la scelta più recente resta visibile');
      expect(configApi.saved.single.$2['SubtitleMode'], 'None');
    });

    test('errore sull\'ultima scelta: torna al valore salvato', () async {
      final initial = await container.read(languagePreferencesProvider.future);
      configApi.failSaves = 1;
      await expectLater(
          container
              .read(languagePreferencesProvider.notifier)
              .save(initial.copyWith(subtitleMode: 'Always')),
          throwsStateError);
      expect(container.read(languagePreferencesProvider).value?.subtitleMode,
          'Default');
    });

    test('prima di salvare rilegge la configurazione dal server', () async {
      final initial = await container.read(languagePreferencesProvider.future);
      // Modificata da un altro client dopo l'apertura delle impostazioni.
      configApi.config = {
        ...configApi.config,
        'HidePlayedInLatest': false,
        'EnableNextEpisodeAutoPlay': false,
      };
      await container
          .read(languagePreferencesProvider.notifier)
          .save(initial.copyWith(subtitleMode: 'Smart'));
      final saved = configApi.saved.single.$2;
      expect(saved['SubtitleMode'], 'Smart');
      expect(saved['HidePlayedInLatest'], isFalse);
      expect(saved['EnableNextEpisodeAutoPlay'], isFalse);
    });
  });

  testWidgets('lingue: la sezione resta caricata scorrendo la pagina',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final configApi = FakeUserConfigApi();
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 300),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(configApi),
    ]);
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 2; i++) {
      await tester.drag(scrollable, const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.drag(scrollable, const Offset(0, 3000));
      await tester.pumpAndSettle();
    }
    await tester.drag(scrollable, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(configApi.configurationCalls, 1);
  });

  testWidgets('sezione Discord: interruttori salvati e collegati tra loro',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 2400),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
    ]);

    final enabled = find.byKey(const Key('discord-enabled'));
    final showTitle = find.byKey(const Key('discord-show-title'));
    final showPoster = find.byKey(const Key('discord-show-poster'));
    expect(find.text('Mostra su Discord cosa sto guardando'), findsOneWidget);

    await tester.ensureVisible(showPoster);
    await tester.tap(showPoster);
    await tester.pump();
    expect(prefs.getBool('discord.showPoster'), isFalse);

    await tester.tap(showTitle);
    await tester.pump();
    expect(prefs.getBool('discord.showTitle'), isFalse);
    // Senza titolo la locandina non si può attivare.
    expect(tester.widget<SwitchListTile>(showPoster).onChanged, isNull);

    await tester.tap(enabled);
    await tester.pump();
    expect(prefs.getBool('discord.enabled'), isFalse);
    expect(tester.widget<SwitchListTile>(showTitle).onChanged, isNull);
  });

  testWidgets('sezione Supporto: copia la diagnostica e apre i log',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    var opened = 0;

    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 2400),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
      collectDiagnosticsProvider.overrideWithValue(() async => 'DIAGNOSTICA'),
      openLogsFolderProvider.overrideWithValue(() async => opened++),
    ]);

    final copy = find.text('Copia diagnostica');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    await tester.pump();
    expect(copied, ['DIAGNOSTICA']);
    expect(find.text('Diagnostica copiata negli appunti'), findsOneWidget);

    await tester.tap(find.text('Apri la cartella dei log'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('sezione Supporto: errore nel raccogliere la diagnostica',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final warnings = <LogRecord>[];
    final sub = Logger.root.onRecord
        .where((r) => r.level >= Level.WARNING)
        .listen(warnings.add);
    addTearDown(sub.cancel);

    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 2400),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
      collectDiagnosticsProvider
          .overrideWithValue(() async => throw StateError('boom')),
    ]);

    final copy = find.text('Copia diagnostica');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    await tester.pump();
    expect(find.text('Impossibile copiare la diagnostica.'), findsOneWidget);
    expect(find.text('Diagnostica copiata negli appunti'), findsNothing);
    expect(warnings, hasLength(1));
  });
}
