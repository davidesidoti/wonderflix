import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/account/resend_code_button.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('attivo dopo 60 s; riparte solo dopo un invio riuscito',
      (tester) async {
    var calls = 0;
    var sent = true;
    await pumpApp(
        tester,
        Scaffold(
            body: ResendCodeButton(onResend: () async {
          calls++;
          return sent;
        })));

    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();
    expect(calls, 0);

    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Rimanda tra 1 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rimanda il codice'), findsOneWidget);

    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);

    // Un invio non riuscito non fa ripartire il conto.
    await tester.pump(ResendCodeButton.delay);
    sent = false;
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Rimanda il codice'), findsOneWidget);
  });
}
