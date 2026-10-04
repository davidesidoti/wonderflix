import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/features/player/queue_panel/queue_add_widgets.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  Future<void> pumpButtons(WidgetTester tester,
      {bool queued = false,
      bool full = false,
      required Future<void> Function({required bool next}) onAdd}) {
    return pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: QueueAddButtons(queued: queued, full: full, onAdd: onAdd),
        ),
      ),
    );
  }

  testWidgets('pulsanti: riproduci dopo e in coda, attesa, un clic alla volta',
      (tester) async {
    final calls = <bool>[];
    final gate = Completer<void>();
    await pumpButtons(tester, onAdd: ({required next}) {
      calls.add(next);
      return gate.future;
    });
    await tester.tap(find.byTooltip(l.partyQueuePlayNext));
    await tester.pump();
    expect(calls, [true]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip(l.partyQueueAddToEnd));
    await tester.pump();
    expect(calls, [true], reason: 'mentre aspetta non si ripreme');
    gate.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip(l.partyQueueAddToEnd));
    await tester.pump();
    expect(calls, [true, false]);
  });

  testWidgets('pulsanti: già in coda → ✓; coda piena → spenti',
      (tester) async {
    await pumpButtons(tester, queued: true, onAdd: ({required next}) async {});
    expect(find.text(l.partyQueueInQueue), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);

    final calls = <bool>[];
    await pumpButtons(tester, full: true, onAdd: ({required next}) async {
      calls.add(next);
    });
    expect(find.byTooltip(l.partyQueueFull(100)), findsNWidgets(2));
    await tester.tap(find.byIcon(LucideIcons.listStart));
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('intestazione: indietro, titolo, sottotitolo, chiudi',
      (tester) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: SizedBox(
          width: 360,
          child: QueuePanelHeader(
            title: 'Dark',
            subtitle: '3 stagioni',
            onBack: () => calls.add('back'),
            onClose: () => calls.add('close'),
          ),
        ),
      ),
    );
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('3 stagioni'), findsOneWidget);
    await tester.tap(find.byTooltip(l.navBack));
    await tester.tap(find.byTooltip(l.playerClosePanel));
    expect(calls, ['back', 'close']);
  });

  testWidgets('messaggio con Riprova', (tester) async {
    var retries = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: QueueMessage(
            text: l.partyQueueLoadFailed, onRetry: () => retries++),
      ),
    );
    await tester.tap(find.text(l.retry));
    expect(retries, 1);
  });
}
