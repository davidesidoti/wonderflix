import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
