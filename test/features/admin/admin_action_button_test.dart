import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_action_button.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  Future<void> pumpButton(
      WidgetTester tester, Future<void> Function()? action) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: AdminActionButton(
              label: 'Avvia', icon: Icons.play_arrow, onPressed: action),
        ),
      ),
    );
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<OutlinedButton>(find.bySubtype<OutlinedButton>()).onPressed !=
      null;

  testWidgets('mentre l\'azione è in corso è disattivato', (tester) async {
    final pending = Completer<void>();
    var runs = 0;
    await pumpButton(tester, () {
      runs++;
      return pending.future;
    });

    await tester.tap(find.text('Avvia'));
    await tester.pump();
    expect(enabled(tester), isFalse);
    await tester.tap(find.text('Avvia'), warnIfMissed: false);
    expect(runs, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(enabled(tester), isTrue);
  });

  testWidgets('un errore diventa un avviso', (tester) async {
    await pumpButton(
        tester, () async => throw const ServerUnreachableException());

    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();

    expect(find.text(it.errorServerUnreachable), findsOneWidget);
    expect(enabled(tester), isTrue);
  });

  testWidgets('senza azione è disattivato', (tester) async {
    await pumpButton(tester, null);
    expect(enabled(tester), isFalse);
  });

  testWidgets('premuto due volte di fila: l\'azione parte una volta sola',
      (tester) async {
    final pending = Completer<void>();
    var runs = 0;
    await pumpButton(tester, () {
      runs++;
      return pending.future;
    });

    // Due pressioni prima che l'albero si ridisegni: la seconda trova il
    // pulsante ancora attivo nel vecchio frame.
    final onPressed =
        tester.widget<OutlinedButton>(find.bySubtype<OutlinedButton>()).onPressed!;
    onPressed();
    onPressed();

    expect(runs, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });

  group('log', () {
    late List<LogRecord> records;

    setUp(() {
      records = [];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
    });

    List<LogRecord> adminLog() =>
        [for (final r in records) if (r.loggerName == 'admin') r];

    testWidgets('un errore che non viene dal server: avviso nel log e '
        'messaggio generico', (tester) async {
      await pumpButton(tester, () async => throw StateError('difetto'));

      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();

      expect(find.text(it.errorGeneric), findsOneWidget);
      final log = adminLog().single;
      expect(log.level, Level.WARNING);
      expect(log.error, isA<StateError>());
      expect(enabled(tester), isTrue);
    });

    testWidgets('un errore del server non va nel log dell\'azione',
        (tester) async {
      await pumpButton(
          tester, () async => throw const ServerUnreachableException());

      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();

      expect(adminLog(), isEmpty);
    });
  });

  group('smontato mentre l\'azione è in corso', () {
    testWidgets('azione riuscita: niente errori', (tester) async {
      final pending = Completer<void>();
      await pumpButton(tester, () => pending.future);
      await tester.tap(find.text('Avvia'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('azione non riuscita: niente errori', (tester) async {
      final pending = Completer<void>();
      await pumpButton(tester, () => pending.future);
      await tester.tap(find.text('Avvia'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      pending.completeError(const ServerUnreachableException());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
