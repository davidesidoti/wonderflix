import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/features/account/authorize_device_dialog.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late bool enabled;
  late FakeResponse Function() authorize;
  Future<bool>? result;

  setUp(() {
    enabled = true;
    authorize = () => const FakeResponse(200, true);
    adapter = FakeAdapter(
      (request) => request.path == '/QuickConnect/Enabled'
          ? FakeResponse(200, enabled)
          : authorize(),
    );
    result = null;
  });

  Iterable<String> authorizeCalls() => adapter.requests
      .where((r) => r.path == '/QuickConnect/Authorize')
      .map((r) => r.queryParameters['code'] as String);

  Future<void> open(
    WidgetTester tester, {
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await pumpApp(
      tester,
      surfaceSize: surfaceSize,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showAuthorizeDeviceDialog(context),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
        authApiProvider.overrideWithValue(
          AuthApi(
            JellyfinHttp(
              baseUrl: testServerUrl,
              clientInfo: testClientInfo,
              adapter: adapter,
            ),
          ),
        ),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String code) async {
    await tester.enterText(
      find.byKey(const Key('authorize-device-code')),
      code,
    );
    await tester.tap(find.byKey(const Key('authorize-device-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('codice vuoto: errore sul campo, nessuna richiesta', (
    tester,
  ) async {
    await open(tester);

    await submit(tester, '   ');

    expect(find.text('Scrivi il codice.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('riuscito: manda il codice senza spazi e chiude con true', (
    tester,
  ) async {
    await open(tester);

    await submit(tester, ' 482 913 ');

    expect(authorizeCalls(), ['482913']);
    expect(adapter.requests.last.method, 'POST');
    expect(await result, isTrue);
    expect(find.byKey(const Key('authorize-device-submit')), findsNothing);
  });

  testWidgets('codice sbagliato o scaduto: errore sul campo', (tester) async {
    authorize = () => const FakeResponse(404);
    await open(tester);

    await submit(tester, '000000');

    expect(
      find.text(
        'Codice sbagliato o scaduto: generane uno nuovo sul dispositivo.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('authorize-device-submit')), findsOneWidget);
  });

  testWidgets('Quick Connect spento: avviso e nessuna Authorize', (
    tester,
  ) async {
    enabled = false;
    await open(tester);

    await submit(tester, '482913');

    expect(
      find.text('Quick Connect non è attivo su questo server.'),
      findsOneWidget,
    );
    expect(authorizeCalls(), isEmpty);
    expect(find.byKey(const Key('authorize-device-submit')), findsOneWidget);
  });

  testWidgets('nginx mentre Jellyfin riparte: server non raggiungibile', (
    tester,
  ) async {
    await open(tester);

    for (final status in restartGatewayStatuses) {
      authorize = () => FakeResponse(status);
      await submit(tester, '482913');
      expect(
        find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget,
        reason: '$status',
      );
    }

    authorize = () => const FakeResponse(500);
    await submit(tester, '482913');
    expect(find.text('Qualcosa è andato storto. Riprova.'), findsOneWidget);
  });

  testWidgets('con la richiesta in volo, Esc e Annulla non chiudono', (
    tester,
  ) async {
    final reply = Completer<void>();
    adapter.handler = (request) async {
      if (request.path == '/QuickConnect/Enabled') {
        return const FakeResponse(200, true);
      }
      await reply.future;
      return const FakeResponse(200, true);
    };
    await open(tester);
    await tester.enterText(
      find.byKey(const Key('authorize-device-code')),
      '482913',
    );
    await tester.tap(find.byKey(const Key('authorize-device-submit')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('authorize-device-submit')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Annulla'))
          .onPressed,
      isNull,
    );

    reply.complete();
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('Annulla chiude con false', (tester) async {
    await open(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets(
      'telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
      (tester) async {
        await open(tester, surfaceSize: size);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
