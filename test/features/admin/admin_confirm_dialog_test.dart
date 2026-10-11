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

  group('etichetta di conferma', () {
    const windowWidth = 1024.0;

    // `showWfDialog`: larga al più 480, con 24 di margine dentro.
    const contentLeft = windowWidth / 2 - 240 + 24;
    const contentRight = windowWidth / 2 + 240 - 24;

    Future<void> open(WidgetTester tester, String confirmLabel) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdminConfirmDialog(
                context,
                title: 'Titolo',
                message: 'Messaggio.',
                confirmLabel: confirmLabel,
              ),
              child: const Text('apri'),
            ),
          ),
        ),
        surfaceSize: const Size(windowWidth, 768),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
    }

    testWidgets('lunga ("Ripristina la Home predefinita"): non sborda',
        (tester) async {
      await open(tester, 'Ripristina la Home predefinita');
      expect(tester.takeException(), isNull);
      final confirm =
          find.widgetWithText(FilledButton, 'Ripristina la Home predefinita');
      expect(tester.getBottomRight(confirm).dx, lessThanOrEqualTo(contentRight));
      expect(tester.getTopLeft(find.widgetWithText(TextButton, 'Annulla')).dx,
          greaterThanOrEqualTo(contentLeft));
    });

    testWidgets('corta: il pulsante resta largo quanto il testo, a destra',
        (tester) async {
      await open(tester, 'Invia');
      expect(tester.takeException(), isNull);
      final confirm = find.widgetWithText(FilledButton, 'Invia');
      final text = find.descendant(of: confirm, matching: find.text('Invia'));
      // Il testo più il margine interno del pulsante, non lo spazio libero.
      expect(tester.getSize(confirm).width,
          lessThan(tester.getSize(text).width + 64));
      expect(tester.getBottomRight(confirm).dx, closeTo(contentRight, 0.5));
    });
  });
}
