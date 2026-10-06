import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/activity_tab.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;

  setUp(() => api = FakeAdminApi()..activityValue = testActivity());

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: ActivityTab()),
        overrides: adminTestOverrides(api));
    await tester.pumpAndSettle();
  }

  testWidgets('voci con gravità, dettagli e titolo', (tester) async {
    await pumpTab(tester);

    expect(find.text('anna si è disconnesso da FireTV Soggiorno'), findsOneWidget);
    expect(find.text('Indirizzo IP: 203.0.113.7'), findsOneWidget);
    expect(find.byKey(const Key('activity-severity-12134-info')), findsOneWidget);
    expect(find.byKey(const Key('activity-severity-11950-warning')),
        findsOneWidget);
    expect(find.byKey(const Key('activity-severity-11904-error')), findsOneWidget);

    // Il dettaglio si apre con un clic.
    expect(find.text('Nome utente o password non validi.'), findsNothing);
    await tester.tap(find.text('Tentativo di accesso fallito da marco'));
    await tester.pump();
    expect(find.text('Nome utente o password non validi.'), findsOneWidget);

    // Solo la riproduzione ha un titolo da aprire.
    expect(find.text('Apri il titolo'), findsOneWidget);

    // Tutto letto: in fondo lo dice.
    expect(find.text('Non ci sono altre voci'), findsOneWidget);
  });

  testWidgets('filtri e Aggiorna', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('Utenti'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'activity:0:true');
    expect(find.text('WonderFlix Watch Party è stato Installato'), findsNothing);

    await tester.tap(find.text('Sistema'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'activity:0:false');
    expect(find.text('WonderFlix Watch Party è stato Installato'), findsOneWidget);

    await tester.tap(find.text('Aggiorna'));
    await tester.pumpAndSettle();
    expect(api.count('activity:0:false'), 2);
  });

  testWidgets('Aggiorna riparte dall\'alto, non da dove si era arrivati',
      (tester) async {
    api.activityValue = testActivityEntries(120);
    await pumpTab(tester);
    final scrollable = find.byType(Scrollable).last;

    await tester.scrollUntilVisible(find.text('Voce 80'), 500,
        scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0));
    expect(find.text('Voce 120'), findsNothing);

    await tester.tap(find.text('Aggiorna'));
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    expect(find.text('Voce 120'), findsOneWidget);
  });

  testWidgets('vuoto', (tester) async {
    api.activityValue = const [];
    await pumpTab(tester);

    expect(find.text('Nessuna voce'), findsOneWidget);
  });

  testWidgets('errore della prima pagina: Riprova', (tester) async {
    api.activityError = const ServerUnreachableException();
    await pumpTab(tester);

    expect(find.text('Riprova'), findsOneWidget);
    api.activityError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('anna si è disconnesso da FireTV Soggiorno'), findsOneWidget);
  });

  testWidgets('pagina dopo fallita: in fondo l\'errore e Riprova', (tester) async {
    api.activityValue = testActivityEntries(120);
    await pumpTab(tester);

    api.activityError = const ServerUnreachableException();
    await tester.scrollUntilVisible(find.text('Riprova'), 500,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();

    final it = lookupAppLocalizations(const Locale('it'));
    expect(find.text(it.errorServerUnreachable), findsOneWidget);
    expect(find.text('Voce 120'), findsNothing, reason: 'siamo in fondo');

    api.activityError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text(it.errorServerUnreachable), findsNothing);
    expect(api.calls, contains('activity:50:all'));
  });

  testWidgets('scorrendo in fondo arriva la pagina dopo', (tester) async {
    api.activityValue = testActivityEntries(120);
    await pumpTab(tester);
    expect(api.calls, ['activity:0:all']);

    await tester.scrollUntilVisible(find.text('Voce 71'), 500,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();

    expect(api.calls, contains('activity:50:all'));
  });
}
