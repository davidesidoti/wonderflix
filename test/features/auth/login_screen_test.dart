import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';

void main() {
  Future<FakeSessionController> pumpLogin(
    WidgetTester tester, {
    SessionState initial = const SessionSignedOut(),
    Object? loginError,
    bool quickConnect = false,
    MotionLevel motion = MotionLevel.reduced,
  }) async {
    final fake = FakeSessionController(initial, loginError: loginError);
    await pumpApp(tester, const LoginScreen(), motion: motion, overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
    ]);
    await tester.pump();
    return fake;
  }

  testWidgets('invia nome utente e password', (tester) async {
    final fake = await pumpLogin(tester);

    await tester.enterText(find.byKey(const Key('login-username')), 'mario');
    await tester.enterText(find.byKey(const Key('login-password')), 'segreta');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(fake.loginAttempts, [('mario', 'segreta')]);
  });

  testWidgets('credenziali errate: mostra il messaggio', (tester) async {
    await pumpLogin(tester, loginError: const UnauthorizedException());

    await tester.enterText(find.byKey(const Key('login-username')), 'mario');
    await tester.enterText(find.byKey(const Key('login-password')), 'x');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('Nome utente o password errati.'), findsOneWidget);
  });

  testWidgets('sessione scaduta: mostra l\'avviso', (tester) async {
    await pumpLogin(tester, initial: const SessionSignedOut(expired: true));
    expect(find.text('Sessione scaduta, accedi di nuovo.'), findsOneWidget);
  });

  testWidgets('scheda Quick Connect solo se attivo sul server', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Quick Connect'), findsNothing);
  });

  testWidgets('link di supporto visibile', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Scrivi all\'admin'), findsOneWidget);
  });

  testWidgets(
      'mentre verifica Quick Connect mostra uno spinner e non perde il testo digitato',
      (tester) async {
    final completer = Completer<bool>();
    final fake = FakeSessionController(const SessionSignedOut());
    await pumpApp(tester, const LoginScreen(), overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      quickConnectEnabledProvider.overrideWith((ref) => completer.future),
    ]);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('login-username')), findsNothing);

    completer.complete(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Quick Connect'), findsOneWidget);
  });

  testWidgets('completa: logo e pannello entrano uno dopo l\'altro',
      (tester) async {
    await pumpLogin(tester, motion: MotionLevel.full);
    expect(find.byType(StaggerGroup), findsOneWidget);
    double panelOpacity() => tester
        .widget<Opacity>(find
            .ancestor(
                of: find.byKey(const Key('login-username')),
                matching: find.byType(Opacity))
            .first)
        .opacity;
    expect(panelOpacity(), lessThan(1));
    // Senza Quick Connect nessuno spinner: nessuna animazione continua.
    await tester.pumpAndSettle();
    expect(panelOpacity(), 1);
  });
}
