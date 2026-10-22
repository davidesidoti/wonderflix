import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/fake_session_controller.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';

/// Quick Connect che non arriva mai al codice: registra quante
/// preparazioni dell'accesso c'erano state quando è partito.
class _RecordingRunner implements QuickConnectRunner {
  _RecordingRunner(this.prepareCalls);

  final int Function() prepareCalls;
  final prepareCallsAtRun = <int>[];

  @override
  Stream<QcState> run() {
    prepareCallsAtRun.add(prepareCalls());
    return const Stream.empty();
  }
}

void main() {
  Future<FakeSessionController> pumpLogin(
    WidgetTester tester, {
    SessionState initial = const SessionSignedOut(),
    Object? loginError,
    bool quickConnect = false,
    MotionLevel motion = MotionLevel.reduced,
    List<StoredProfile> profiles = const [],
  }) async {
    final fake = FakeSessionController(initial, loginError: loginError);
    final book = profiles.fold(const ProfileBook(), (b, p) => b.upsert(p));
    await pumpApp(tester, const LoginScreen(), motion: motion, overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
      profilesProvider
          .overrideWith(() => FixedProfiles(ProfilesState(book: book))),
    ]);
    await tester.pump();
    return fake;
  }

  /// Il campo con la chiave [key] ha il fuoco.
  bool hasFocus(WidgetTester tester, String key) => tester
      .widget<EditableText>(find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(EditableText)))
      .focusNode
      .hasFocus;

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

  testWidgets('aprendo il login si prepara l\'accesso', (tester) async {
    final fake = await pumpLogin(tester);
    expect(fake.prepareLoginCalls, 1);
    // Senza profili: niente "Annulla".
    expect(find.byKey(const Key('login-cancel')), findsNothing);
  });

  testWidgets('Quick Connect parte dopo la preparazione dell\'accesso',
      (tester) async {
    final fake = FakeSessionController(const SessionSignedOut());
    final runner = _RecordingRunner(() => fake.prepareLoginCalls);
    await pumpApp(tester, const LoginScreen(), overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      quickConnectEnabledProvider.overrideWith((ref) async => true),
      quickConnectRunnerProvider.overrideWithValue(runner),
    ]);
    await tester.pump();
    await tester.tap(find.text('Quick Connect'));
    // Il pannello resta sullo spinner: niente pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Il codice si chiede con il DeviceId nuovo dell'accesso.
    expect(runner.prepareCallsAtRun, [1]);
  });

  testWidgets('aggiungere un profilo: "Annulla" torna a "Chi guarda?"',
      (tester) async {
    final fake = await pumpLogin(tester,
        initial: const SessionSignedOut(adding: true),
        profiles: [testProfile(userId: 'u1')]);
    await tester.tap(find.byKey(const Key('login-cancel')));
    await tester.pump();
    expect(fake.cancelLoginCalls, 1);
  });

  testWidgets('accedi di nuovo: nome già scritto, avviso, "Annulla"',
      (tester) async {
    await pumpLogin(tester,
        initial: const SessionSignedOut(expired: true, reloginUserId: 'u2'),
        profiles: [
          testProfile(userId: 'u1'),
          testProfile(userId: 'u2', name: 'Luigi', expired: true),
        ]);
    expect(find.text('Sessione scaduta, accedi di nuovo.'), findsOneWidget);
    final username = tester.widget<TextField>(
        find.byKey(const Key('login-username')));
    expect(username.controller!.text, 'Luigi');
    // Con il nome già scritto il fuoco va alla password.
    expect(hasFocus(tester, 'login-password'), isTrue);
    expect(find.byKey(const Key('login-cancel')), findsOneWidget);
  });

  testWidgets('accedi di nuovo senza nome salvato: il fuoco al nome',
      (tester) async {
    // Un profilo migrato il cui primo `/Users/Me` non è riuscito.
    await pumpLogin(tester,
        initial: const SessionSignedOut(expired: true, reloginUserId: 'u1'),
        profiles: [testProfile(userId: 'u1', name: '', expired: true)]);
    final username = tester.widget<TextField>(
        find.byKey(const Key('login-username')));
    expect(username.controller!.text, isEmpty);
    expect(hasFocus(tester, 'login-username'), isTrue);
    expect(hasFocus(tester, 'login-password'), isFalse);
  });

  testWidgets('accedi di nuovo con un solo profilo: niente "Annulla"',
      (tester) async {
    await pumpLogin(tester,
        initial: const SessionSignedOut(expired: true, reloginUserId: 'u1'),
        profiles: [testProfile(userId: 'u1', expired: true)]);
    expect(find.byKey(const Key('login-cancel')), findsNothing);
  });

  testWidgets('sesto profilo: "Massimo 5 profili"', (tester) async {
    await pumpLogin(tester, loginError: const ProfileLimitException());
    await tester.enterText(find.byKey(const Key('login-username')), 'toad');
    await tester.enterText(find.byKey(const Key('login-password')), 'x');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Massimo 5 profili'), findsOneWidget);
  });
}
