import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_widgets.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  testWidgets('AdminCard: titolo e contenuto', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: AdminCard(
          title: 'Annuncio',
          icon: Icons.campaign,
          child: Text('contenuto'),
        ),
      ),
    );

    expect(find.text('Annuncio'), findsOneWidget);
    expect(find.text('contenuto'), findsOneWidget);
    expect(find.byIcon(Icons.campaign), findsOneWidget);
  });

  testWidgets('AdminCard: un titolo lungo si accorcia, senza sbordare',
      (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: AdminCard(
              title: 'Un titolo molto lungo ' * 10,
              icon: Icons.campaign,
              child: const Text('contenuto'),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.textContaining('Un titolo molto'));
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('AdminCardError: il messaggio e "Riprova"', (tester) async {
    var retries = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: AdminCardError(
            error: const ServerUnreachableException(),
            onRetry: () => retries++),
      ),
    );

    expect(find.text(it.errorServerUnreachable), findsOneWidget);
    await tester.tap(find.text(it.retry));
    expect(retries, 1);
  });
}
