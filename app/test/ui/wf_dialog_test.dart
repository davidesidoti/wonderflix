import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/account/change_password_dialog.dart';
import 'package:wonderflix/ui/wf_confirm_dialog.dart';
import 'package:wonderflix/ui/wf_dialog.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

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

  Widget opener(void Function(BuildContext) onOpen) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
              onPressed: () => onOpen(context), child: const Text('apri')),
        ),
      );

  Future<void> openAndSettle(WidgetTester tester) async {
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'stretto: la finestra è una pagina con la freccia indietro e restituisce il valore',
      (tester) async {
    String? result = 'niente';
    await pumpApp(
      tester,
      opener((context) async => result = await showWfDialog<String>(context,
          builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).pop('ok'),
              child: const Text('conferma')))),
      surfaceSize: const Size(390, 844),
    );
    await openAndSettle(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byTooltip('Indietro'), findsOneWidget);

    await tester.tap(find.text('conferma'));
    await tester.pumpAndSettle();
    expect(result, 'ok');

    await openAndSettle(tester);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.text('conferma'), findsNothing);
    expect(result, isNull);
  });

  testWidgets('largo: la finestra è un Dialog come oggi', (tester) async {
    await pumpApp(
      tester,
      opener((context) =>
          showWfDialog<void>(context, builder: (_) => const Text('dentro'))),
    );
    await openAndSettle(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('Indietro'), findsNothing);
  });

  testWidgets('conferma breve: resta Dialog anche nello stretto',
      (tester) async {
    await pumpApp(
      tester,
      opener((context) => showWfConfirmDialog(context,
          title: 'Sicuro?',
          message: 'm',
          confirmLabel: 'Sì',
          cancelLabel: 'No')),
      surfaceSize: const Size(390, 844),
    );
    await openAndSettle(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tastiera aperta: il campo attivo resta visibile',
      (tester) async {
    await pumpApp(
      tester,
      opener((context) => showChangePasswordDialog(context)),
      surfaceSize: const Size(390, 844),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
    );
    await openAndSettle(tester);
    // Il telefono ha la tastiera aperta: 300 punti in basso.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final last = find.byKey(const Key('change-password-confirm'));
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(tester.getRect(last).bottom, lessThan(844 - 300));
    expect(tester.takeException(), isNull);
  });
}
