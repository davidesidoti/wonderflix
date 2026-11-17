import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_buttons.dart';
import 'package:wonderflix/ui/wf_dialog.dart';
import 'package:wonderflix/ui/wf_dialog_parts.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('una nota di errore è rossa e ha l\'icona di avviso', (t) async {
    Widget footer(bool error) => Scaffold(
      body: WfDialogFooter(
        note: 'Il server non è raggiungibile',
        noteIsError: error,
        primary: WfButton.primary(
          label: 'Salva',
          icon: LucideIcons.check,
          onPressed: () {},
        ),
      ),
    );
    await pumpApp(t, footer(true));
    expect(
      t.widget<Text>(find.text('Il server non è raggiungibile')).style!.color,
      WfColors.error,
    );
    expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);

    await pumpApp(t, footer(false));
    expect(
      t.widget<Text>(find.text('Il server non è raggiungibile')).style!.color,
      WfColors.creamMuted,
    );
    expect(find.byIcon(LucideIcons.circleAlert), findsNothing);
  });

  testWidgets('il piede ha la nota a sinistra, Annulla e il primario', (
    t,
  ) async {
    await pumpApp(
      t,
      Scaffold(
        body: WfDialogFooter(
          note: '3 modifiche',
          cancelLabel: 'Annulla',
          onCancel: () {},
          primary: WfButton.primary(
            label: 'Salva',
            icon: LucideIcons.check,
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(find.text('3 modifiche'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('3 modifiche')).dx,
      lessThan(t.getTopLeft(find.text('Annulla')).dx),
    );
    expect(
      t.getTopLeft(find.text('Annulla')).dx,
      lessThan(t.getTopLeft(find.text('Salva')).dx),
    );
  });

  testWidgets('la testa: titolo in Bebas 32 e sottotitolo su una riga', (
    t,
  ) async {
    await pumpApp(
      t,
      const Scaffold(
        body: WfDialogHeader(
          title: 'Modifica',
          subtitle: 'Il titolo del film',
          leading: SizedBox(key: Key('poster'), width: 36, height: 54),
        ),
      ),
    );
    final title = t.widget<Text>(find.text('Modifica'));
    expect(title.style?.fontFamily, WfText.displayFamily);
    expect(title.style?.fontSize, 32);
    final sub = t.widget<Text>(find.text('Il titolo del film'));
    expect(sub.maxLines, 1);
    expect(sub.style?.color, WfColors.creamMuted);
    expect(
      t.getTopLeft(find.byKey(const Key('poster'))).dx,
      lessThan(t.getTopLeft(find.text('Modifica')).dx),
    );
  });

  Future<void> openGuarded(
    WidgetTester t,
    int changes, {
    bool blocked = false,
  }) async {
    await pumpApp(
      t,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWfDialog<void>(
              context,
              builder: (_) =>
                  WfDiscardGuard(
                    changes: changes,
                    child: PopScope(
                      canPop: !blocked,
                      child: const Text('corpo'),
                    ),
                  ),
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await t.tap(find.text('apri'));
    await t.pumpAndSettle();
    expect(find.text('corpo'), findsOneWidget);
  }

  testWidgets('con modifiche, Esc chiede prima di chiudere', (t) async {
    await openGuarded(t, 2);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Buttare le 2 modifiche?'), findsOneWidget);
    expect(
      find.text('Quello che hai cambiato non è ancora salvato.'),
      findsOneWidget,
    );

    await t.tap(find.text('Continua a modificare'));
    await t.pumpAndSettle();
    expect(find.text('Buttare le 2 modifiche?'), findsNothing);
    expect(find.text('corpo'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.tap(find.text('Butta'));
    await t.pumpAndSettle();
    expect(find.text('corpo'), findsNothing);
    expect(find.text('Butta'), findsNothing);
  });

  testWidgets('con modifiche, anche il clic fuori chiede', (t) async {
    await openGuarded(t, 1);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.text('Buttare la modifica?'), findsOneWidget);
    await t.tap(find.text('Butta'));
    await t.pumpAndSettle();
    expect(find.text('corpo'), findsNothing);
  });

  testWidgets('senza modifiche e pop bloccato da un altro PopScope: nessuna '
      'domanda', (t) async {
    await openGuarded(t, 0, blocked: true);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('corpo'), findsOneWidget);
    expect(find.text('Butta'), findsNothing);
  });

  testWidgets('senza modifiche Esc chiude subito', (t) async {
    await openGuarded(t, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('corpo'), findsNothing);
    expect(find.text('Butta'), findsNothing);
  });

  for (final size in [const Size(1440, 900), const Size(390, 780)]) {
    testWidgets('il piede segue lo stato del corpo a $size', (t) async {
      final key = GlobalKey();
      await pumpApp(
        t,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWfDialog<void>(
                context,
                builder: (_) => _Counter(key: key),
                footer: (_) => WfHostFooter(host: key),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
        surfaceSize: size,
      );
      await t.tap(find.text('apri'));
      await t.pumpAndSettle();
      expect(find.text('0 modifiche'), findsOneWidget);
      await t.tap(find.text('aggiungi'));
      await t.pump();
      expect(find.text('1 modifiche'), findsOneWidget);
      // Annulla del piede chiude con maybePop.
      await t.tap(find.text('Annulla'));
      await t.pumpAndSettle();
      expect(find.text('aggiungi'), findsNothing);
    });
  }

  testWidgets("con modifiche, l'Annulla del piede chiede prima di chiudere", (
    t,
  ) async {
    final key = GlobalKey();
    await pumpApp(
      t,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWfDialog<void>(
              context,
              builder: (_) => _Counter(key: key, guarded: true),
              footer: (_) => WfHostFooter(host: key),
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    );
    await t.tap(find.text('apri'));
    await t.pumpAndSettle();
    await t.tap(find.text('aggiungi'));
    await t.pump();
    await t.tap(find.text('Annulla'));
    await t.pumpAndSettle();
    expect(find.text('Buttare la modifica?'), findsOneWidget);
    await t.tap(find.text('Continua a modificare'));
    await t.pumpAndSettle();
    expect(find.text('1 modifiche'), findsOneWidget);
  });

  testWidgets('piede senza Annulla', (t) async {
    await pumpApp(
      t,
      Scaffold(
        body: WfDialogFooter(
          primary: WfButton.secondary(
            label: 'Chiudi',
            icon: LucideIcons.x,
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(find.text('Chiudi'), findsOneWidget);
    expect(find.text('Annulla'), findsNothing);
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key, this.guarded = false});

  final bool guarded;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> with WfFooterHost<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      onPressed: () => setState(() => n++),
      child: const Text('aggiungi'),
    );
    return widget.guarded ? WfDiscardGuard(changes: n, child: button) : button;
  }

  @override
  Widget buildFooter(BuildContext context) => WfDialogFooter(
        note: '$n modifiche',
        cancelLabel: 'Annulla',
        primary: WfButton.primary(
          label: 'Salva',
          icon: LucideIcons.check,
          onPressed: () {},
        ),
      );
}
