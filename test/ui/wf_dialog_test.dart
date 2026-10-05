import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_dialog.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('finestra: aspetto, valore restituito, Esc chiude', (tester) async {
    String? result = 'niente';
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showWfDialog<String>(
                context,
                builder: (dialogContext) => TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop('ok'),
                  child: const Text('conferma'),
                ),
              );
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('conferma'), findsOneWidget);
    expect(tester.widget<Dialog>(find.byType(Dialog)).backgroundColor, WfColors.surface);

    await tester.tap(find.text('conferma'));
    await tester.pumpAndSettle();
    expect(result, 'ok');

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('conferma'), findsNothing);
    expect(result, isNull);
  });
}
