import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/features/account/change_password_dialog.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  Future<bool>? result;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    result = null;
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showChangePasswordDialog(context),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
            baseUrl: testServerUrl,
            clientInfo: testClientInfo,
            adapter: adapter))),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester,
      {String current = '', required String next, String? confirm}) async {
    await tester.enterText(
        find.byKey(const Key('change-password-current')), current);
    await tester.enterText(find.byKey(const Key('change-password-new')), next);
    await tester.enterText(
        find.byKey(const Key('change-password-confirm')), confirm ?? next);
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pump();
  }

  testWidgets('password corta e conferma diversa: errori, nessuna chiamata',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'abc');
    expect(find.text('Almeno 6 caratteri'), findsOneWidget);

    await fill(tester, next: 'nuova123', confirm: 'nuova124');
    expect(find.text('Le password non coincidono'), findsOneWidget);
    expect(find.text('Almeno 6 caratteri'), findsNothing);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('password attuale sbagliata: errore sotto il campo',
      (tester) async {
    adapter.handler = (_) => const FakeResponse(403);
    await open(tester);

    await fill(tester, current: 'sbagliata', next: 'nuova123');
    await tester.pumpAndSettle();

    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(find.byKey(const Key('change-password-submit')), findsOneWidget);
  });

  testWidgets('riuscito: manda le password e chiude con true', (tester) async {
    await open(tester);

    await fill(tester, current: 'vecchia', next: 'nuova123');
    await tester.pumpAndSettle();

    final request = adapter.requests.single;
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, {'CurrentPw': 'vecchia', 'NewPw': 'nuova123'});
    expect(await result, isTrue);
    expect(find.byKey(const Key('change-password-submit')), findsNothing);
  });

  testWidgets('account senza password: la password attuale va vuota',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'nuova123');
    await tester.pumpAndSettle();

    expect(
        adapter.requests.single.data, {'CurrentPw': '', 'NewPw': 'nuova123'});
  });

  testWidgets('server irraggiungibile: avviso sopra i campi', (tester) async {
    adapter.handler = (_) => throw const SocketException('giù');
    await open(tester);

    await fill(tester, current: 'vecchia', next: 'nuova123');
    await tester.pumpAndSettle();

    expect(
        find.text(
            'WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);
  });

  testWidgets('con la richiesta in volo, Esc e Annulla non chiudono',
      (tester) async {
    final reply = Completer<void>();
    adapter.handler = (_) async {
      await reply.future;
      return const FakeResponse(204);
    };
    await open(tester);
    await fill(tester, current: 'vecchia', next: 'nuova123');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('change-password-submit')), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Annulla'))
            .onPressed,
        isNull);

    // La password cambia: la finestra si chiude con `true`, e chi l'ha
    // aperta può dare l'avviso.
    reply.complete();
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(find.byKey(const Key('change-password-submit')), findsNothing);
  });

  testWidgets('Annulla chiude con false', (tester) async {
    await open(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
