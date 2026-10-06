import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_confirm_dialog.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('Annulla: no; il pulsante di conferma: sì', (tester) async {
    bool? result;
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAdminConfirmDialog(
              context,
              title: 'Annuncio',
              message: 'Arriva a tutti.',
              confirmLabel: 'Invia',
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('Annuncio'), findsOneWidget);
    expect(find.text('Arriva a tutti.'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
