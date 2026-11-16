import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/account/change_password_dialog.dart';
import 'package:wonderflix/ui/wf_confirm_dialog.dart';
import 'package:wonderflix/ui/wf_buttons.dart';
import 'package:wonderflix/ui/wf_dialog.dart';
import 'package:wonderflix/ui/wf_dialog_parts.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  testWidgets('finestra: aspetto, valore restituito, Esc chiude', (
    tester,
  ) async {
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
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      WfColors.surface,
    );

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

  testWidgets('semanticLabel: la finestra ha un nome e fa da ambito', (
    tester,
  ) async {
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
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.scopesRoute == true &&
            w.properties.namesRoute == true &&
            w.explicitChildNodes &&
            w.properties.label == 'Titolo della finestra',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Titolo della finestra'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'senza semanticLabel: il nome è quello predefinito delle finestre',
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
      final fallback = MaterialLocalizations.of(
        tester.element(find.byType(Dialog)),
      ).dialogLabel;
      expect(fallback, isNotEmpty);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.namesRoute == true &&
              w.properties.scopesRoute == true &&
              w.properties.label == fallback,
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  Widget opener(void Function(BuildContext) onOpen) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => onOpen(context),
        child: const Text('apri'),
      ),
    ),
  );

  Future<void> openAndSettle(WidgetTester tester) async {
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'stretto: la finestra è una pagina con la ✕ e restituisce il valore',
    (tester) async {
      String? result = 'niente';
      await pumpApp(
        tester,
        opener(
          (context) async => result = await showWfDialog<String>(
            context,
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).pop('ok'),
              child: const Text('conferma'),
            ),
          ),
        ),
        surfaceSize: const Size(390, 844),
      );
      await openAndSettle(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byTooltip('Chiudi'), findsOneWidget);
      expect(find.byTooltip('Indietro'), findsNothing);

      await tester.tap(find.text('conferma'));
      await tester.pumpAndSettle();
      expect(result, 'ok');

      await openAndSettle(tester);
      await tester.tap(find.byTooltip('Chiudi'));
      await tester.pumpAndSettle();
      expect(find.text('conferma'), findsNothing);
      expect(result, isNull);
    },
  );

  testWidgets('largo: la finestra è un Dialog come oggi', (tester) async {
    await pumpApp(
      tester,
      opener(
        (context) =>
            showWfDialog<void>(context, builder: (_) => const Text('dentro')),
      ),
    );
    await openAndSettle(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('Indietro'), findsNothing);
  });

  testWidgets('conferma breve: resta Dialog anche nello stretto', (
    tester,
  ) async {
    await pumpApp(
      tester,
      opener(
        (context) => showWfConfirmDialog(
          context,
          title: 'Sicuro?',
          message: 'm',
          confirmLabel: 'Sì',
          cancelLabel: 'No',
        ),
      ),
      surfaceSize: const Size(390, 844),
    );
    await openAndSettle(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tastiera aperta: il campo attivo resta visibile', (
    tester,
  ) async {
    // In orizzontale il contenuto non sta sopra la tastiera: deve scorrere.
    const inset = 200.0;
    await pumpApp(
      tester,
      opener((context) => showChangePasswordDialog(context)),
      surfaceSize: const Size(844, 390),
      overrides: [
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    await openAndSettle(tester);
    tester.view.viewInsets = FakeViewPadding(
      bottom: inset * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final last = find.byKey(const Key('change-password-confirm'));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(390 - inset));
    expect(tester.takeException(), isNull);
  });

  Widget footer(BuildContext c) => WfDialogFooter(
    note: '2 modifiche',
    cancelLabel: 'Annulla',
    onCancel: () => Navigator.maybePop(c),
    primary: WfButton.primary(
      label: 'Salva',
      icon: LucideIcons.check,
      onPressed: () {},
    ),
  );

  testWidgets('nello stretto il piede resta in fondo anche col testo grande', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(
      tester,
      opener(
        (context) => showWfDialog<void>(
          context,
          compactTitle: 'Modifica metadati',
          builder: (_) => const SizedBox(height: 2000, child: Text('corpo')),
          footer: footer,
        ),
      ),
      surfaceSize: const Size(390, 780),
    );
    await openAndSettle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Modifica metadati'), findsOneWidget);
    expect(find.byTooltip('Chiudi'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Salva')).dy, lessThanOrEqualTo(780));
    expect(
      tester.getBottomLeft(find.byType(WfDialogFooter)).dy,
      lessThanOrEqualTo(780),
    );
    // Il piede sta sotto il corpo, non sopra.
    expect(
      tester.getTopLeft(find.byType(WfDialogFooter)).dy,
      greaterThan(tester.getTopLeft(find.text('corpo')).dy),
    );
  });

  testWidgets('largo: il piede sta sotto il corpo a tutta larghezza', (
    tester,
  ) async {
    await pumpApp(
      tester,
      opener(
        (context) => showWfDialog<void>(
          context,
          builder: (_) => const SizedBox(height: 2000, child: Text('corpo')),
          footer: footer,
        ),
      ),
    );
    await openAndSettle(tester);
    expect(tester.takeException(), isNull);
    // La finestra è larga 480 (maxWidth), il piede anche: fuori dal padding.
    expect(tester.getSize(find.byType(WfDialogFooter)).width, 480);
    expect(tester.getBottomLeft(find.text('Salva')).dy, lessThanOrEqualTo(900));
  });

  testWidgets('la conferma usa testa e piede comuni', (tester) async {
    bool? result;
    await pumpApp(
      tester,
      opener(
        (context) async => result = await showWfConfirmDialog(
          context,
          title: 'Sicuro?',
          message: 'm',
          confirmLabel: 'Sì',
          cancelLabel: 'No',
        ),
      ),
    );
    await openAndSettle(tester);
    final title = tester.widget<Text>(find.text('Sicuro?'));
    expect(title.style?.fontFamily, WfText.displayFamily);
    expect(title.style?.fontSize, 32);
    expect(find.byType(WfDialogHeader), findsOneWidget);
    expect(find.byType(WfDialogFooter), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Sì'), matching: find.byType(WfButton)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<WfButton>(
            find.ancestor(of: find.text('Sì'), matching: find.byType(WfButton)),
          )
          .primary,
      isTrue,
    );
    await tester.tap(find.text('Sì'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
