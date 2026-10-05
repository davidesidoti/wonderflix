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
        body: PendingRequestActions(
          busy: busy,
          onApprove: () => calls.add('approva'),
          onDecline: () => calls.add('rifiuta'),
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

  testWidgets('Approva; durante l\'invio solo l\'indicatore', (tester) async {
    final calls = await pumpActions(tester);
    await tester.tap(find.text('Approva'));
    expect(calls, ['approva']);

    await pumpActions(tester, busy: true);
    expect(find.text('Approva'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
