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
    await pumpApp(tester, const SettingsScreen(), overrides: [
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
}
