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

  testWidgets('semanticLabel: la finestra ha un nome e fa da ambito', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWfDialog<void>(
              context,
              semanticLabel: 'Titolo della finestra',
              builder: (_) => const Text('contenuto'),
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.scopesRoute == true &&
          w.properties.namesRoute == true &&
          w.explicitChildNodes &&
          w.properties.label == 'Titolo della finestra'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Titolo della finestra'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('senza semanticLabel: il nome è quello predefinito delle finestre',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWfDialog<void>(
              context,
              builder: (_) => const Text('contenuto'),
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    // Una rotta senza nome non va annunciata: ripiega sul testo di Material
    // ("Finestra di dialogo"), come `AlertDialog`.
    final fallback =
        MaterialLocalizations.of(tester.element(find.byType(Dialog))).dialogLabel;
    expect(fallback, isNotEmpty);
    expect(
      find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.namesRoute == true &&
          w.properties.scopesRoute == true &&
          w.properties.label == fallback),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
