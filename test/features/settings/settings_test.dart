import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
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
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    await pumpApp(tester, const Scaffold(body: SettingsScreen()), overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(() => session),
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
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    await pumpApp(tester, const Scaffold(body: SettingsScreen()), overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
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
}
