import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/password_login_form.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';
import 'package:wonderflix/ui/tv_focusable.dart';
import 'package:wonderflix/ui/tv_text_field_frame.dart';
import 'package:wonderflix/ui/user_avatar.dart';

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

/// Quick Connect fermo sul codice 123456.
class _WaitingRunner implements QuickConnectRunner {
  @override
  Stream<QcState> run() => Stream.value(const QcWaiting('123456'));
}

const expiredNotice = 'La sessione è scaduta, capita dopo un po\' di tempo. '
    'Accedi di nuovo per rientrare.';

void main() {
  Future<FakeSessionController> pumpLogin(
    WidgetTester tester, {
    SessionState initial = const SessionSignedOut(),
    Object? loginError,
    bool quickConnect = false,
    MotionLevel motion = MotionLevel.reduced,
    List<StoredProfile> profiles = const [],
    bool tv = false,
  }) async {
    final fake = FakeSessionController(initial, loginError: loginError);
    final book = profiles.fold(const ProfileBook(), (b, p) => b.upsert(p));
    await pumpApp(tester, const LoginScreen(),
        motion: motion,
        tv: tv,
        surfaceSize: tv ? const Size(960, 540) : const Size(1440, 900),
        overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
      // Il codice non arriva mai: la scheda resta ferma.
      quickConnectRunnerProvider.overrideWithValue(_RecordingRunner(() => 0)),
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
    expect(find.text(expiredNotice), findsOneWidget);
  });

  testWidgets('primo accesso: "Accedi a WonderFlix", etichette, autofill',
      (tester) async {
    await pumpLogin(tester);
    expect(find.text('Accedi a WonderFlix'), findsOneWidget);
    expect(find.byType(UserAvatar), findsNothing);
    expect(find.text('Nome utente'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byKey(const Key('login-not-you')), findsNothing);
    final user = tester.widget<TextField>(find.byKey(const Key('login-username')));
    final pass = tester.widget<TextField>(find.byKey(const Key('login-password')));
    expect(user.decoration!.hintText, isNull);
    expect(pass.decoration!.hintText, isNull);
    expect(user.autofillHints, [AutofillHints.username]);
    expect(pass.autofillHints, [AutofillHints.password]);
    expect(
        find.ancestor(
            of: find.byKey(const Key('login-username')),
            matching: find.byType(AutofillGroup)),
        findsOneWidget);
    expect(
        find.ancestor(
            of: find.byKey(const Key('login-password')),
            matching: find.byType(AutofillGroup)),
        findsOneWidget);
  });

  testWidgets('l\'occhio mostra e nasconde la password', (tester) async {
    await pumpLogin(tester);
    bool obscured() => tester
        .widget<TextField>(find.byKey(const Key('login-password')))
        .obscureText;
    final eye = find.byKey(const Key('login-password-eye'));
    expect(obscured(), isTrue);
    expect(find.byTooltip('Mostra la password'), findsOneWidget);
    expect(find.byIcon(LucideIcons.eye), findsOneWidget);
    await tester.tap(eye);
    await tester.pump();
    expect(obscured(), isFalse);
    expect(find.byTooltip('Nascondi la password'), findsOneWidget);
    expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
    await tester.tap(eye);
    await tester.pump();
    expect(obscured(), isTrue);
  });

  Future<void> pumpRelogin(WidgetTester tester,
          {String name = 'Luigi', bool tv = false, bool quickConnect = false}) =>
      pumpLogin(tester,
          initial: const SessionSignedOut(expired: true, reloginUserId: 'u2'),
          profiles: [
            testProfile(userId: 'u1'),
            testProfile(userId: 'u2', name: name, expired: true),
          ],
          tv: tv,
          quickConnect: quickConnect);

  testWidgets('sessione scaduta: Ciao, avatar, avviso neutro', (tester) async {
    await pumpRelogin(tester);
    expect(find.text('Ciao, Luigi'), findsOneWidget);
    expect(find.text('Accedi a WonderFlix'), findsNothing);
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text(expiredNotice), findsOneWidget);
    expect(find.byType(ErrorBanner), findsNothing);
    expect(find.byIcon(LucideIcons.clock), findsOneWidget);
    expect(find.byKey(const Key('login-not-you')), findsOneWidget);
    // La riga col link è alta come quella della password.
    double gap(String label, String field) =>
        tester.getTopLeft(find.byKey(Key(field))).dy -
        tester.getTopLeft(find.text(label)).dy;
    expect(gap('Nome utente', 'login-username'),
        moreOrLessEquals(gap('Password', 'login-password'), epsilon: 0.5));
  });

  testWidgets('"Non sei tu?" svuota il nome e torna al titolo generico',
      (tester) async {
    await pumpRelogin(tester);
    await tester.enterText(find.byKey(const Key('login-password')), 'segreta');
    await tester.tap(find.byKey(const Key('login-password-eye')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-not-you')));
    await tester.pump();
    await tester.pump();
    final password =
        tester.widget<TextField>(find.byKey(const Key('login-password')));
    expect(password.controller!.text, isEmpty);
    expect(password.obscureText, isTrue);
    expect(find.text('Accedi a WonderFlix'), findsOneWidget);
    expect(find.text('Ciao, Luigi'), findsNothing);
    expect(find.byType(UserAvatar), findsNothing);
    expect(find.text(expiredNotice), findsNothing);
    expect(find.byKey(const Key('login-not-you')), findsNothing);
    final username =
        tester.widget<TextField>(find.byKey(const Key('login-username')));
    expect(username.controller!.text, isEmpty);
    expect(hasFocus(tester, 'login-username'), isTrue);
  });

  testWidgets('nome lunghissimo nel Ciao: una riga, nessun overflow',
      (tester) async {
    await pumpRelogin(tester, name: 'L' * 60);
    expect(tester.takeException(), isNull);
    final hello = tester.widget<Text>(find.textContaining('Ciao, LLL'));
    expect(hello.maxLines, 1);
    expect(hello.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.byKey(const Key('login-panel'))).width, 380);
  });

  testWidgets('desktop con Quick Connect: niente altezza fissa',
      (tester) async {
    await pumpLogin(tester, quickConnect: true);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.byType(IndexedStack), findsOneWidget);
    // Il nome scritto resta passando da una scheda all'altra.
    await tester.enterText(find.byKey(const Key('login-username')), 'mario');
    await tester.tap(find.widgetWithText(Tab, 'Quick Connect'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(Tab, 'Password'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-username')))
            .controller!
            .text,
        'mario');
  });

  testWidgets('TV, Ciao: Giù attraversa i campi fino ad Accedi senza tastiera',
      (tester) async {
    await pumpRelogin(tester, tv: true, quickConnect: true);
    await tester.tap(find.widgetWithText(Tab, 'Password'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ciao, Luigi'), findsOneWidget);
    expect(find.byKey(const Key('login-password-eye')), findsNothing);
    expect(find.byType(TvTextFieldFrame), findsNWidgets(2));

    FocusNode frame(String key) => Focus.of(tester.element(find.descendant(
        of: find.ancestor(
            of: find.byKey(Key(key)), matching: find.byType(TvFocusable)),
        matching: find.byType(AnimatedScale))));
    bool inField() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    bool onWidget(Key key) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return false;
      var found = false;
      ctx.visitAncestorElements((e) {
        found = e.widget.key == key;
        return !found;
      });
      return found || ctx.widget.key == key;
    }

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(inField(), isFalse);
      expect(hasFocus(tester, 'login-username'), isFalse);
      expect(hasFocus(tester, 'login-password'), isFalse);
    }

    // Dalla scheda Password Giù va al nome (il link a destra è fuori dalla
    // colonna della scheda); Su dal nome arriva al link.
    Focus.of(tester.element(find.widgetWithText(Tab, 'Password')))
        .requestFocus();
    await tester.pump();
    await press(LogicalKeyboardKey.arrowDown);
    expect(frame('login-username').hasPrimaryFocus, isTrue);
    await press(LogicalKeyboardKey.arrowUp);
    expect(onWidget(const Key('login-not-you')), isTrue);
    await press(LogicalKeyboardKey.arrowDown);
    expect(frame('login-username').hasPrimaryFocus, isTrue);
    await press(LogicalKeyboardKey.arrowDown);
    expect(frame('login-password').hasPrimaryFocus, isTrue);
    await press(LogicalKeyboardKey.arrowDown);
    expect(onWidget(const Key('login-submit')), isTrue);
    await press(LogicalKeyboardKey.arrowUp);
    expect(frame('login-password').hasPrimaryFocus, isTrue);
    await press(LogicalKeyboardKey.arrowUp);
    expect(frame('login-username').hasPrimaryFocus, isTrue);
    await press(LogicalKeyboardKey.arrowUp);
    expect(onWidget(const Key('login-not-you')), isTrue);

    // OK sul link: il link sparisce, il focus va alla cornice del nome.
    await press(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.byKey(const Key('login-not-you')), findsNothing);
    expect(frame('login-username').hasPrimaryFocus, isTrue);
    expect(inField(), isFalse);
  });

  for (final (scale, expired) in [
    for (final scale in [1.0, 1.3, 1.5])
      for (final expired in [true, false]) (scale, expired),
  ]) {
    testWidgets(
        'TV, Quick Connect (${expired ? 'scaduto, con Ciao' : 'primo accesso'}'
        ', testo ×$scale): focus sulla scheda, codice e passi nei 540',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, const LoginScreen(),
          tv: true,
          surfaceSize: const Size(960, 540),
          overrides: [
            sessionControllerProvider.overrideWith(() => FakeSessionController(
                expired
                    ? const SessionSignedOut(expired: true, reloginUserId: 'u2')
                    : const SessionSignedOut())),
            quickConnectEnabledProvider.overrideWith((ref) async => true),
            quickConnectRunnerProvider.overrideWithValue(_WaitingRunner()),
            profilesProvider.overrideWith(() => FixedProfiles(ProfilesState(
                book: expired
                    ? const ProfileBook()
                        .upsert(testProfile(userId: 'u1'))
                        .upsert(testProfile(
                            userId: 'u2', name: 'Luigi', expired: true))
                    : const ProfileBook()))),
          ]);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      if (expired) {
        expect(find.text('Ciao, Luigi'), findsOneWidget);
        expect(find.text(expiredNotice), findsOneWidget);
      }
      expect(
          Focus.of(tester.element(find.widgetWithText(Tab, 'Quick Connect')))
              .hasPrimaryFocus,
          isTrue);
      expect(tester.getRect(find.text('123 456')).bottom,
          lessThanOrEqualTo(540));
      final step2 =
          find.ancestor(of: find.text('2'), matching: find.byType(Row));
      expect(tester.getRect(step2.first).bottom, lessThanOrEqualTo(540));
      // Logo e pannello affiancati.
      expect(tester.getRect(find.byType(Image)).right,
          lessThan(tester.getRect(find.byKey(const Key('login-panel'))).left));
    });
  }

  testWidgets('TV, testo ×1.3: dalla scheda Password Giù arriva ad Accedi '
      'senza tastiera, tutto nei 540', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpRelogin(tester, tv: true, quickConnect: true);
    await tester.tap(find.widgetWithText(Tab, 'Password'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    bool inField() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    bool onSubmit() {
      var found = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        found = e.widget.key == const Key('login-submit');
        return !found;
      });
      return found;
    }

    Focus.of(tester.element(find.widgetWithText(Tab, 'Password')))
        .requestFocus();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(inField(), isFalse);
    }
    expect(onSubmit(), isTrue);
    expect(tester.getRect(find.byKey(const Key('login-submit'))).bottom,
        lessThanOrEqualTo(540));
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
      quickConnectRunnerProvider.overrideWithValue(_RecordingRunner(() => 0)),
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
    expect(find.text(expiredNotice), findsOneWidget);
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

  /// Quante volte l'app ha chiesto di uscire (`SystemNavigator.pop`).
  int Function() countExits(WidgetTester tester) {
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return () => exits;
  }

  testWidgets('TV: il telecomando passa sui campi senza tastiera, OK li apre',
      (tester) async {
    await pumpLogin(tester, tv: true);
    FocusNode frame(String key) => Focus.of(tester.element(find.descendant(
        of: find.ancestor(
            of: find.byKey(Key(key)), matching: find.byType(TvFocusable)),
        matching: find.byType(AnimatedScale))));
    bool inside(String key) =>
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<
                FilledButton>() ==
            tester.widget(find.byKey(Key(key)));

    frame('login-username').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(frame('login-password').hasPrimaryFocus, isTrue);
    expect(hasFocus(tester, 'login-password'), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(inside('login-submit'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(frame('login-username').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();
    expect(hasFocus(tester, 'login-username'), isTrue);
    // "Avanti" della tastiera apre la password.
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    await tester.pump();
    expect(hasFocus(tester, 'login-password'), isTrue);
  });

  testWidgets('TV, aggiungere un profilo: Indietro torna a "Chi guarda?"',
      (tester) async {
    final exits = countExits(tester);
    final fake = await pumpLogin(tester,
        initial: const SessionSignedOut(adding: true),
        profiles: [testProfile(userId: 'u1')],
        tv: true);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(fake.cancelLoginCalls, 1);
    expect(exits(), 0);
  });

  testWidgets('TV, senza profili: doppio Indietro per uscire', (tester) async {
    final exits = countExits(tester);
    final fake = await pumpLogin(tester, tv: true);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits(), 0);
    expect(find.text('Premi di nuovo Indietro per uscire'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits(), 1);
    expect(fake.cancelLoginCalls, 0);
  });

  testWidgets('fuori dalla TV Indietro non è intercettato', (tester) async {
    final fake = await pumpLogin(tester,
        initial: const SessionSignedOut(adding: true),
        profiles: [testProfile(userId: 'u1')]);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(fake.cancelLoginCalls, 0);
  });
}
