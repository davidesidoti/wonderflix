import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';

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
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 1600),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(() => session),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
    ]);

    expect(find.text('Accesso come Mario'), findsOneWidget);
    expect(find.text('Versione 0.0.1'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pump();
    expect(prefs.getString('locale'), 'en');

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
    await tester.tap(find.text('8 Mbps').last);
    await tester.pumpAndSettle();
    expect(prefs.getString('player.quality'), 'mbps8');

    await tester.tap(find.text('Grandi'));
    await tester.pump();
    expect(prefs.getDouble('player.subtitleScale'), 1.25);

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
}
