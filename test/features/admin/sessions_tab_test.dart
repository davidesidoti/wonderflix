import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/sessions_tab.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;

  setUp(() => api = FakeAdminApi());

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: SessionsTab()),
        overrides: adminTestOverrides(api));
    await tester.pumpAndSettle();
  }

  testWidgets('chi guarda, chi è collegato e i party', (tester) async {
    api
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
    await pumpTab(tester);

    // Episodio transcodificato su FireTV.
    expect(find.text('viviroby'), findsOneWidget);
    expect(find.text('Jellyfin Android TV · FireTV Soggiorno'), findsOneWidget);
    expect(find.text('Lost · S1:E3 · Pilota'), findsOneWidget);
    expect(find.text('12:34 / 42:36'), findsOneWidget);
    expect(find.text('Transcodifica'), findsOneWidget);
    expect(find.text('→ H264 1080p · AAC · 8,2 Mbps · Software'), findsOneWidget);
    expect(find.text('codec video non supportato, codec audio non supportato'),
        findsOneWidget);

    // Film in remux, in pausa: niente riga della transcodifica.
    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Remux'), findsOneWidget);
    expect(find.byKey(const Key('session-paused-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-paused-s1')), findsNothing);
    expect(find.textContaining('→ HEVC'), findsNothing);

    // Collegato senza riprodurre.
    expect(find.text('davide.sidoti'), findsOneWidget);
    expect(find.text('WonderFlix · nocturne'), findsOneWidget);
    expect(find.textContaining('attivo '), findsOneWidget);

    // Il party.
    expect(find.text('Serata Lost'), findsOneWidget);
    expect(find.text('viviroby, Mario'), findsOneWidget);

    // La chiave API di Seerr non c'è.
    expect(find.text('Seerr'), findsNothing);
  });

  testWidgets('nessuno: tre testi vuoti', (tester) async {
    await pumpTab(tester);

    expect(find.text('Nessuno sta guardando'), findsOneWidget);
    expect(find.text('Nessun altro collegato'), findsOneWidget);
    expect(find.text('Nessun watch party in corso'), findsOneWidget);
  });

  testWidgets('primo caricamento fallito: errore e Riprova', (tester) async {
    api.sessionsError = const ServerUnreachableException();
    await pumpTab(tester);

    expect(find.text('Riprova'), findsOneWidget);

    api.sessionsError = null;
    api.sessionsValue = testSessions();
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('rilettura fallita: restano i dati con "Dati non aggiornati"',
      (tester) async {
    api.sessionsValue = testSessions();
    await pumpTab(tester);
    expect(find.textContaining('Dati non aggiornati'), findsNothing);

    api.sessionsError = const ServerUnreachableException();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
    expect(find.text('viviroby'), findsOneWidget);
  });
}
