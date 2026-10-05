import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/requests/pending_request_actions.dart';

import '../../support/pump_app.dart';

void main() {
  Future<List<String>> pumpActions(WidgetTester tester, {bool busy = false}) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        // `Align` dà ai pulsanti la loro misura, non quella della pagina.
        body: Align(
          alignment: Alignment.topLeft,
          child: PendingRequestActions(
            busy: busy,
            onApprove: () => calls.add('approva'),
            onDecline: () => calls.add('rifiuta'),
          ),
        ),
      ),
    );
    return calls;
  }

  testWidgets('Rifiuta chiede conferma con un secondo clic', (tester) async {
    final calls = await pumpActions(tester);

    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    expect(find.text('Conferma'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('Conferma'));
    await tester.pump();
    expect(calls, ['rifiuta']);
    expect(find.text('Rifiuta'), findsOneWidget);
  });

  testWidgets('la conferma scade', (tester) async {
    final calls = await pumpActions(tester);

    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    await tester.pump(declineConfirmFor);

    expect(find.text('Rifiuta'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('la conferma armata non sopravvive a un invio', (tester) async {
    final busy = ValueNotifier(false);
    addTearDown(busy.dispose);
    final calls = <String>[];
    // Sempre lo stesso widget: lo stato della riga resta, cambia solo `busy`.
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (context, value, _) => PendingRequestActions(
            busy: value,
            onApprove: () => calls.add('approva'),
            onDecline: () => calls.add('rifiuta'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    expect(find.text('Conferma'), findsOneWidget);

    // La riga è occupata (Approva è partito) e poi torna: i pulsanti
    // ricompaiono da capo, senza "Conferma".
    busy.value = true;
    await tester.pump();
    busy.value = false;
    await tester.pump();

    expect(find.text('Rifiuta'), findsOneWidget);
    expect(find.text('Conferma'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('Approva; durante l\'invio solo l\'indicatore', (tester) async {
    final calls = await pumpActions(tester);
    await tester.tap(find.text('Approva'));
    expect(calls, ['approva']);

    await pumpActions(tester, busy: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // I pulsanti tengono il posto ma non si vedono e non rispondono.
    expect(
      tester
          .widget<Visibility>(find.descendant(
              of: find.byType(PendingRequestActions),
              matching: find.byType(Visibility)))
          .visible,
      isFalse,
    );
    await tester.tap(find.text('Approva'), warnIfMissed: false);
    await tester.tap(find.text('Rifiuta'), warnIfMissed: false);
    await tester.pump();
    expect(calls, ['approva']);
  });

  testWidgets('durante l\'invio la riga non cambia misura', (tester) async {
    await pumpActions(tester);
    final idle = tester.getSize(find.byType(PendingRequestActions));

    await pumpActions(tester, busy: true);

    expect(tester.getSize(find.byType(PendingRequestActions)), idle);
    // L'indicatore sta al centro dello spazio dei pulsanti.
    expect(
      tester.getCenter(find.byType(CircularProgressIndicator)),
      tester.getCenter(find.byType(PendingRequestActions)),
    );
  });

  testWidgets('l\'indicatore ha un nome per lo screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpActions(tester, busy: true);

    expect(find.bySemanticsLabel('Operazione in corso'), findsOneWidget);
    // I pulsanti nascosti non sono nell'albero di chi usa lo screen reader.
    expect(find.bySemanticsLabel('Approva'), findsNothing);
    semantics.dispose();
  });

  testWidgets('il secondo tempo di Rifiuta dice cosa si conferma', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpActions(tester);
    final decline = find.byKey(const Key('request-decline'));
    expect(tester.getSemantics(decline).label, 'Rifiuta');

    await tester.tap(find.text('Rifiuta'));
    await tester.pump();

    expect(tester.getSemantics(decline).label, 'Rifiuta: Conferma');
    semantics.dispose();
  });
}
