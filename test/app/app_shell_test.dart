import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_screen.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  testWidgets('mostra utente e Home, e fa il logout dal menu', (tester) async {
    final fake = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: HomeScreen()),
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
    );

    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ciao, Mario'), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();

    expect(fake.logoutCalls, 1);
  });
}
