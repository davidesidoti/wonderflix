import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/settings/appearance_settings_section.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('sceglie "Ridotte" e lo salva', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(
      tester,
      const Scaffold(body: AppearanceSettingsSection()),
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(find.text('Animazioni'), findsOneWidget);
    expect(find.text('Come Windows'), findsOneWidget);
    await tester.tap(find.text('Ridotte'));
    await tester.pumpAndSettle();
    expect(prefs.getString('appearance.motion'), 'reduced');
  });
}
