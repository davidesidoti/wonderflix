import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/config/app_config.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/field_focus.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAccountApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAccountApi();
    session = FakeSessionController(const SessionSignedOut());
  });

  /// Un `AppConfig` senza `supportUrl`: nessun "Scrivi all'admin".
  final noSupportConfig = AppConfig(
    serverUrl: Uri.parse('https://media.example.com'),
    githubRepo: 'owner/repo',
    discordAppId: '1',
    supportUrl: null,
  );

  Future<void> pumpLogin(
    WidgetTester tester, {
    bool quickConnect = false,
    bool supportUrl = true,
  }) async {
    await pumpApp(tester, const LoginScreen(), overrides: [
      sessionControllerProvider.overrideWith(() => session),
      quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
      profilesProvider
          .overrideWith(() => FixedProfiles(const ProfilesState())),
      ...accountTestOverrides(api),
      if (!supportUrl) appConfigProvider.overrideWithValue(noSupportConfig),
    ]);
    await tester.pump();
  }

  Future<void> openRecovery(
    WidgetTester tester, {
    String username = 'garg',
  }) async {
    await tester.enterText(find.byKey(const Key('login-username')), username);
    await tester.tap(find.byKey(const Key('login-forgot')));
    await tester.pump();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('si apre con il nome scritto e torna indietro con quello',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);

    expect(find.text('Recupera la password'), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsNothing);
    expect(fieldText(tester, 'recovery-username'), 'garg');

    await tester.enterText(find.byKey(const Key('recovery-username')), 'garg2');
    await tapKey(tester, 'recovery-back');

    expect(fieldText(tester, 'login-username'), 'garg2');
    expect(find.text('Recupera la password'), findsNothing);
  });

  testWidgets('con Quick Connect il recupero prende tutto il pannello',
      (tester) async {
    await pumpLogin(tester, quickConnect: true);
    await openRecovery(tester);

    expect(find.text('Quick Connect'), findsNothing);
    expect(find.byKey(const Key('recovery-username')), findsOneWidget);
  });

  testWidgets('primo passo: nome vuoto, poi la risposta neutra',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester, username: '');

    await tapKey(tester, 'recovery-send');
    expect(find.text('Scrivi il nome utente'), findsOneWidget);
    expect(api.recoveryStarts, isEmpty);

    await tester.enterText(
        find.byKey(const Key('recovery-username')), ' garg ');
    await tapKey(tester, 'recovery-send');

    expect(api.recoveryStarts.single, ('garg', 'it'));
    expect(
        find.text("Se l'account esiste e ha un contatto collegato, ti abbiamo "
            'mandato un codice su Discord o per email.'),
        findsOneWidget);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
  });

  testWidgets('primo passo: troppe richieste, poi plugin vecchio',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);

    api.startRecoveryFailure = AccountFailure.rateLimited;
    await tapKey(tester, 'recovery-send');
    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsNothing);

    api.startRecoveryFailure = AccountFailure.unavailable;
    await tapKey(tester, 'recovery-send');
    expect(
        find.text('Il recupero automatico non è disponibile su questo server: '
            "contatta l'amministratore"),
        findsOneWidget);
    expect(find.text("Scrivi all'admin"), findsOneWidget);
    expect(find.text('Nessun contatto collegato?'), findsNothing);
    expect(find.byKey(const Key('recovery-send')), findsNothing);
  });

  testWidgets('secondo passo: controlli ed errori, nessun accesso',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'abc');
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Almeno 6 caratteri'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova124');
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Le password non coincidono'), findsOneWidget);
    expect(api.recoveryCompletes, isEmpty);

    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');
    api.completeRecoveryFailure = AccountFailure.invalidCode;
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Codice non valido o scaduto'), findsOneWidget);
    expect(api.recoveryCompletes.single, (
      username: 'garg',
      code: '012345',
      newPassword: 'nuova123',
      language: 'it',
    ));

    api.completeRecoveryFailure = AccountFailure.rateLimited;
    await tapKey(tester, 'recovery-submit');
    expect(
        find.text(
            "Troppi tentativi: riprova più tardi o contatta l'amministratore"),
        findsOneWidget);

    // Il 500 di un codice già usato.
    api.completeRecoveryFailure = AccountFailure.serverError;
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Cambio non riuscito: chiedi un nuovo codice'),
        findsOneWidget);

    // Senza rete il codice può essere ancora buono: non se ne chiede un altro.
    api.completeRecoveryFailure = AccountFailure.network;
    await tapKey(tester, 'recovery-submit');
    expect(
        find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);
    expect(find.text('Cambio non riuscito: chiedi un nuovo codice'),
        findsNothing);

    expect(session.loginAttempts, isEmpty);
  });

  testWidgets('secondo passo riuscito: entra con la password nuova',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');
    await tapKey(tester, 'recovery-submit');

    expect(session.loginAttempts, [('garg', 'nuova123')]);
  });

  testWidgets("mentre il cambio è in volo, 'Torna all'accesso' è spento",
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');

    api.gate = Completer<void>();
    await tapKey(tester, 'recovery-submit');
    await tapKey(tester, 'recovery-back');
    expect(find.text('Recupera la password'), findsOneWidget);

    api.gate!.complete();
    await tester.pump();
    expect(session.loginAttempts, [('garg', 'nuova123')]);
  });

  testWidgets("accesso non riuscito dopo il cambio: si riprova solo l'accesso",
      (tester) async {
    session = FakeSessionController(const SessionSignedOut(),
        loginError: const ServerUnreachableException());
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');

    await tapKey(tester, 'recovery-submit');
    expect(
        find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);

    // La password è già cambiata: restano l'avviso e "ACCEDI", senza campi
    // da riscrivere (una password nuova sarebbe ignorata) né un codice da
    // rimandare.
    expect(find.text('Password cambiata: accedi con quella nuova.'),
        findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsNothing);
    expect(find.byKey(const Key('recovery-new')), findsNothing);
    expect(find.byKey(const Key('recovery-confirm')), findsNothing);
    expect(find.byKey(const Key('resend-code')), findsNothing);
    expect(find.byKey(const Key('recovery-back')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('recovery-submit')),
            matching: find.text('ACCEDI')),
        findsOneWidget);
    // Il campo che aveva il fuoco è sparito: lo prende "ACCEDI", così Invio
    // riprova l'accesso e Tab non parte da "Torna all'accesso".
    expect(Focus.of(tester.element(find.text('ACCEDI'))).hasPrimaryFocus,
        isTrue);

    // Il codice è già usato: il secondo tentativo non lo rimanda.
    await tapKey(tester, 'recovery-submit');
    expect(api.recoveryCompletes, hasLength(1));
    expect(session.loginAttempts,
        [('garg', 'nuova123'), ('garg', 'nuova123')]);
  });

  testWidgets('accesso lento dopo il cambio: finito l\'errore, "ACCEDI" ha il '
      'fuoco', (tester) async {
    session = FakeSessionController(const SessionSignedOut(),
        loginError: const ServerUnreachableException());
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');

    // Il cambio passa e l'accesso resta in volo: il pulsante c'è già, ma
    // spento; il fuoco deve arrivargli quando l'accesso finisce.
    session.loginGate = Completer<void>();
    await tapKey(tester, 'recovery-submit');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Password cambiata: accedi con quella nuova.'),
        findsOneWidget);

    session.loginGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);
    bool signInHasFocus() =>
        Focus.of(tester.element(find.text('ACCEDI'))).hasPrimaryFocus;
    expect(signInHasFocus(), isTrue);

    // Un altro tentativo lento: il fuoco cade ancora con il pulsante spento
    // e torna a fine accesso.
    session.loginGate = Completer<void>();
    await tapKey(tester, 'recovery-submit');
    await tester.pump(const Duration(milliseconds: 100));
    session.loginGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(signInHasFocus(), isTrue);
  });

  testWidgets('con un accesso in volo "Password dimenticata?" è spento',
      (tester) async {
    await pumpLogin(tester);
    session.loginGate = Completer<void>();
    await tester.enterText(find.byKey(const Key('login-username')), 'garg');
    await tester.enterText(find.byKey(const Key('login-password')), 'x');
    await tapKey(tester, 'login-submit');

    TextButton forgot() =>
        tester.widget<TextButton>(find.byKey(const Key('login-forgot')));
    expect(forgot().onPressed, isNull);
    await tapKey(tester, 'login-forgot');
    expect(find.text('Recupera la password'), findsNothing);

    session.loginGate!.complete();
    await tester.pump();
    expect(forgot().onPressed, isNotNull);
  });

  testWidgets('senza supportUrl il link c\'è, "Scrivi all\'admin" no',
      (tester) async {
    await pumpLogin(tester, supportUrl: false);

    expect(find.byKey(const Key('login-forgot')), findsOneWidget);
    expect(find.text("Scrivi all'admin"), findsNothing);

    await openRecovery(tester);
    expect(find.text('Recupera la password'), findsOneWidget);
    expect(find.text("Scrivi all'admin"), findsNothing);
    expect(find.text('Nessun contatto collegato?'), findsNothing);

    await tapKey(tester, 'recovery-send');
    expect(find.byKey(const Key('recovery-code')), findsOneWidget);
    expect(find.text("Scrivi all'admin"), findsNothing);
  });

  testWidgets('primo passo senza rete: avviso, e si resta al primo passo',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);

    api.startRecoveryFailure = AccountFailure.network;
    await tapKey(tester, 'recovery-send');

    expect(
        find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);
    expect(find.byKey(const Key('recovery-send')), findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsNothing);
  });

  testWidgets('password troppo corta per il server: errore sotto il campo',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');
    api.completeRecoveryFailure = AccountFailure.weakPassword;
    await tapKey(tester, 'recovery-submit');

    expect(
        find.descendant(
            of: find.byKey(const Key('recovery-new')),
            matching: find.text('Almeno 6 caratteri')),
        findsOneWidget);
    expect(api.recoveryCompletes, hasLength(1));
    expect(session.loginAttempts, isEmpty);
  });

  testWidgets('Rimanda dopo 60 s chiede un codice nuovo', (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.pump(const Duration(seconds: 60));
    await tapKey(tester, 'resend-code');

    expect(api.recoveryStarts, [('garg', 'it'), ('garg', 'it')]);
  });

  testWidgets('codice non valido: il fuoco torna al codice, selezionato',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');
    api.completeRecoveryFailure = AccountFailure.invalidCode;
    // Invio nell'ultimo campo toglie il fuoco: l'errore deve ridarlo al
    // codice.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Codice non valido o scaduto'), findsOneWidget);
    expectFocusedAndSelected(tester, 'recovery-code', '012345'.length);
  });

  testWidgets('Rimanda riuscito: il codice vecchio esce dal campo',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');
    String codeText() => fieldText(tester, 'recovery-code');
    await tester.enterText(find.byKey(const Key('recovery-code')), '111111');

    // Con un 429 nessun codice nuovo è partito: quello scritto vale ancora.
    await tester.pump(const Duration(seconds: 60));
    api.startRecoveryFailure = AccountFailure.rateLimited;
    await tapKey(tester, 'resend-code');
    expect(codeText(), '111111');

    // Un codice nuovo sostituisce il vecchio sul server: con quello vecchio
    // nel campo, "Cambia password" darebbe "Codice non valido o scaduto".
    await tester.pump(const Duration(seconds: 60));
    api.startRecoveryFailure = null;
    await tapKey(tester, 'resend-code');
    expect(api.recoveryStarts, hasLength(3));
    expect(codeText(), isEmpty);
  });

  testWidgets('Rimanda con troppe richieste: avviso, e il conto riparte',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.pump(const Duration(seconds: 60));
    api.startRecoveryFailure = AccountFailure.rateLimited;
    await tapKey(tester, 'resend-code');

    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsOneWidget);
  });

  testWidgets('Ho già un codice: il secondo passo senza chiederne un altro',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);

    await tapKey(tester, 'recovery-have-code');

    expect(api.recoveryStarts, isEmpty);
    expect(
        find.text('Scrivi il codice che hai ricevuto su Discord o per email.'),
        findsOneWidget);
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');
    await tapKey(tester, 'recovery-submit');

    expect(api.recoveryCompletes.single.username, 'garg');
    expect(api.recoveryCompletes.single.code, '012345');
    expect(session.loginAttempts, [('garg', 'nuova123')]);
  });

  testWidgets('Ho già un codice senza il nome: l\'errore, si resta lì',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester, username: '');

    await tapKey(tester, 'recovery-have-code');

    expect(find.text('Scrivi il nome utente'), findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsNothing);
  });

  testWidgets('Ho già un codice, poi Rimanda: un codice nuovo, il testo '
      'torna quello di "mandato"', (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-have-code');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');

    await tester.pump(const Duration(seconds: 60));
    await tapKey(tester, 'resend-code');

    // Il codice nuovo sostituisce quello dell'admin: non è più "quello che
    // hai ricevuto".
    expect(api.recoveryStarts.single, ('garg', 'it'));
    expect(
        find.text("Se l'account esiste e ha un contatto collegato, ti abbiamo "
            'mandato un codice su Discord o per email.'),
        findsOneWidget);
    expect(
        find.text('Scrivi il codice che hai ricevuto su Discord o per email.'),
        findsNothing);
    expect(fieldText(tester, 'recovery-code'), isEmpty);
  });

  testWidgets('Ho già un codice, Rimanda non riuscito: resta il testo del '
      'codice che si ha', (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-have-code');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');

    api.startRecoveryFailure = AccountFailure.network;
    await tester.pump(const Duration(seconds: 60));
    await tapKey(tester, 'resend-code');

    // Nessun codice è partito: quello dell'admin vale ancora.
    expect(
        find.text('Scrivi il codice che hai ricevuto su Discord o per email.'),
        findsOneWidget);
    expect(fieldText(tester, 'recovery-code'), '012345');
  });

  testWidgets('Ho già un codice con un plugin senza recupero: non '
      'disponibile', (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-have-code');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');

    // Il 404 arriva solo qui: "Ho già un codice" non chiama `Start`.
    api.completeRecoveryFailure = AccountFailure.unavailable;
    await tapKey(tester, 'recovery-submit');

    expect(
        find.text('Il recupero automatico non è disponibile su questo server: '
            "contatta l'amministratore"),
        findsOneWidget);
    expect(find.text('Cambio non riuscito: chiedi un nuovo codice'),
        findsNothing);
    expect(find.byKey(const Key('recovery-code')), findsNothing);
    expect(session.loginAttempts, isEmpty);
  });
}
