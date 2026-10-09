import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/features/account/account_texts.dart';
import 'package:wonderflix/features/admin/account_admin_controllers.dart';
import 'package:wonderflix/features/admin/set_password_dialog.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late FakeSessionController session;
  Future<bool>? result;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    result = null;
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result =
                showSetPasswordDialog(context, userId: 'u3', name: 'lucia'),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        ...adminTestOverrides(FakeAdminApi(),
            session: session,
            features: const SocialFeatures(inbox: true, account: true)),
        authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
            baseUrl: testServerUrl,
            clientInfo: testClientInfo,
            adapter: adapter))),
      ],
    );
    // Come nella scheda Utenti, che lo guarda: il controller resta vivo.
    ProviderScope.containerOf(tester.element(find.text('apri')))
        .listen(accountUsersControllerProvider, (_, _) {});
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester,
      {required String next, String? confirm}) async {
    await tester.enterText(find.byKey(const Key('set-password-new')), next);
    await tester.enterText(
        find.byKey(const Key('set-password-confirm')), confirm ?? next);
    await tester.tap(find.byKey(const Key('set-password-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('titolo e avviso sulle sessioni', (tester) async {
    await open(tester);
    expect(find.text('Imposta la password di lucia'), findsOneWidget);
    expect(find.text('Le sessioni di lucia verranno chiuse.'), findsOneWidget);
    final field =
        tester.widget<TextField>(find.byKey(const Key('set-password-new')));
    expect(field.decoration!.errorMaxLines, accountErrorMaxLines);
  });

  testWidgets('password corta e conferma diversa: errori, nessuna chiamata',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'abc');
    expect(find.text('Almeno 6 caratteri'), findsOneWidget);

    await fill(tester, next: 'nuova123', confirm: 'nuova124');
    expect(find.text('Le password non coincidono'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('riuscita: senza la password attuale, e chiude con true',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'nuova123');

    final request = adapter.requests.single;
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u3'});
    expect(request.data, {'NewPw': 'nuova123'});
    expect(await result, isTrue);
  });

  testWidgets('403: l\'errore sopra i campi e l\'utente riletto',
      (tester) async {
    adapter.handler = (_) => const FakeResponse(403);
    await open(tester);

    await fill(tester, next: 'nuova123');

    expect(find.text('Account disabilitato o accesso non consentito.'),
        findsOneWidget);
    expect(session.refreshUserCalls, 1);
    expect(find.byKey(const Key('set-password-submit')), findsOneWidget);
  });

  testWidgets('durante la richiesta Esc non chiude', (tester) async {
    final gate = Completer<void>();
    adapter.handler = (_) async {
      await gate.future;
      return const FakeResponse(204);
    };
    await open(tester);

    await tester.enterText(find.byKey(const Key('set-password-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('set-password-confirm')), 'nuova123');
    await tester.tap(find.byKey(const Key('set-password-submit')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    // Fino a fine animazione: senza il `PopScope` la finestra sarebbe ancora
    // lì durante la dissolvenza d'uscita.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('set-password-submit')), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });
}
