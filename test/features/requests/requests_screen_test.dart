import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_navigation.dart';
import 'package:wonderflix/features/requests/requests_screen.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;
  const manager = RequestsMe(canRequest: true, canManage: true, hasAccount: true);

  setUp(() => api = FakeRequestsApi());

  Future<void> pumpScreen(WidgetTester tester, {RequestsTab? initialTab}) async {
    await pumpApp(
      tester,
      Scaffold(body: RequestsScreen(initialTab: initialTab)),
      overrides: requestsTestOverrides(api),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('utente normale: le sue richieste, senza schede', (tester) async {
    api.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 1, title: 'Dune', year: 2021, status: RequestStatus.approved),
    ];
    await pumpScreen(tester);

    expect(find.text('RICHIESTE'), findsOneWidget);
    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Approvata'), findsOneWidget);
    expect(find.text('Le mie'), findsNothing);
    expect(find.textContaining('chiesto da'), findsNothing);
    expect(api.calls.where((c) => c.startsWith('list:pending')), isEmpty);
  });

  testWidgets('admin con richieste in attesa: si apre su "Da approvare (2)"',
      (tester) async {
    api
      ..meValue = manager
      ..lists[RequestsFilter.pending] = [
        testMediaRequest(id: 1, title: 'Dune', requester: 'Garg'),
        testMediaRequest(id: 2, title: 'Brothers', requester: 'sronweb'),
      ]
      ..lists[RequestsFilter.mine] = [testMediaRequest(id: 3, title: 'Mia')];
    await pumpScreen(tester);

    expect(find.text('Da approvare (2)'), findsOneWidget);
    expect(find.text('Le mie'), findsOneWidget);
    expect(find.text('Tutte'), findsOneWidget);
    expect(find.textContaining('chiesto da Garg'), findsOneWidget);
    expect(find.text('Mia (2024)'), findsNothing);

    await tester.tap(find.text('Le mie'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Mia (2024)'), findsOneWidget);
    expect(find.textContaining('chiesto da'), findsNothing);
  });

  testWidgets('admin senza richieste in attesa: si apre su "Le mie"',
      (tester) async {
    api.meValue = manager;
    await pumpScreen(tester);

    expect(find.text('Da approvare (0)'), findsOneWidget);
    expect(find.text('Non hai ancora chiesto niente. Cerca un titolo che manca e premi Richiedi.'),
        findsOneWidget);
  });

  testWidgets('scheda dall\'indirizzo e pagine vuote', (tester) async {
    api.meValue = manager;
    await pumpScreen(tester, initialTab: RequestsTab.all);
    expect(find.text('Nessuna richiesta'), findsOneWidget);

    await tester.tap(find.text('Da approvare (0)'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Niente da approvare'), findsOneWidget);
  });

  testWidgets('errore e Riprova', (tester) async {
    api.failure = RequestsFailure.network;
    await pumpScreen(tester);
    expect(find.text('Riprova'), findsOneWidget);

    api
      ..failure = null
      ..lists[RequestsFilter.mine] = [testMediaRequest(id: 1, title: 'Dune', year: 2021)];
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Dune (2021)'), findsOneWidget);
  });

  testWidgets('scorrendo in fondo carica le altre', (tester) async {
    api.lists[RequestsFilter.mine] = [
      for (var i = 1; i <= 25; i++) testMediaRequest(id: i, title: 'Titolo $i'),
    ];
    await pumpScreen(tester);
    expect(api.calls, isNot(contains('list:mine:20:20')));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump();

    expect(api.calls, contains('list:mine:20:20'));
  });
}
